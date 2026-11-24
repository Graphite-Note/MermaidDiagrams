/**
 * File: DiagramLabelByteDecoderTests.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: Checks that decoding a label's bytes gives 0.7.0's scalar decoding, line for line and span for span: on
 *              every label every corpus decodes, and on random text of line breaks, tags, Markdown markers, entity codes
 *              (valid, unknown, out of range, surrogates), icon names, white space of every width and text beyond ASCII
 *              in all three forms; and that long and hostile labels decode in time that grows with their length.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

import Foundation
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark
import XCTest

final class DiagramLabelByteDecoderTests: XCTestCase {
    private static let pieces = [
        "<br>", "<BR/>", "<br />", "<br\t/>", "<bR  >", "<br", "\n", "\\n", "\\N", "\\", "\r", "\r\n", "<b>", "</b>", "<strong>", "</strong>", "<i>",
        "</i>", "<em>", "</EM>", "<code>", "</code>", "<kbd>", "<span class=\"x\">", "</span>", "<u>", "<sub>", "List<T>", "<notatag>", "<a-b>",
        "<longtagname>", "<blockquote>", "</figcaption>", "<b/>", "< b>", "<>", "*", "**", "_", "__", "word_with_underscore", "a*b", "#quot;",
        "#9829;", "#0;", "#nothing;", "#;", "&amp;", "&#65;", "&#x41;", "&#X1F600;", "&#xD800;", "&#1114112;", "&#99999999999;", "&lt;",
        "&unknown;", "&;", "&#;", "&#x;", "fa:fa-car", "fab:fa-x", "fa:fa-", " fa:fa-y", ":fa-", "ﬂ", " ", "  ", "\t", "\u{A0}", "\u{3000}",
        "\u{2003}", "\u{FEFF}", "\u{2028}", "数据", "é", "e\u{301}", "\u{1F600}", "\u{AD}", "text", "a", "7", "#", ";", "&", "<", ">", "/", ":",
    ]
    private static let forms: [DiagramLabelDecoder.Form] = [.plain, .markdown, .literal]

    private struct Generator {
        var state: UInt64

        mutating func next(below bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(bound))
        }
    }

    /// Asserts the label is the reference's: lines, spans and how Pele reads it.
    static func assertSame(_ label: DiagramLabel, _ reference: DiagramLabel, _ description: @autoclosure () -> String, file: StaticString = #filePath,
                           line: UInt = #line) {
        XCTAssertEqual(label.lines, reference.lines, description(), file: file, line: line)
        XCTAssertEqual(label.lines.map { line in Array(line.utf8) }, reference.lines.map { line in Array(line.utf8) }, description(), file: file, line: line)
        XCTAssertEqual(label.spans, reference.spans, description(), file: file, line: line)
        XCTAssertEqual(label.spans?.map { line in line.map { span in Array(span.text.utf8) } }, reference.spans?.map { line in line.map { span in Array(span.text.utf8) } },
                       description(), file: file, line: line)
        XCTAssertEqual(label.isReadWithoutMarkup, reference.isReadWithoutMarkup, description(), file: file, line: line)
        XCTAssertEqual(label.spokenText, reference.spokenText, description(), file: file, line: line)
        XCTAssertEqual(label, reference, description(), file: file, line: line)
    }

    func testRandomTextDecodesAsTheScalarDecoderDecodesIt() {
        var generator = Generator(state: 0x5EED_D001)
        var markedCount = 0
        for _ in 0..<12_000 {
            let text = (0..<generator.next(below: 14)).map { _ in Self.pieces[generator.next(below: Self.pieces.count)] }.joined()
            for form in Self.forms {
                let label = DiagramLabelDecoder.label(from: text, form: form)
                Self.assertSame(label, ReferenceDiagramLabelDecoder.label(from: text, form: form), "\(text.debugDescription) as \(form)")
                if !label.isReadWithoutMarkup { markedCount += 1 }
            }
        }
        XCTAssertGreaterThan(markedCount, 20_000, "most random texts have markup")
    }

    /// The test on bytes in memory, which skips sixteen at a time, answers as the test that reads each byte, wherever a
    /// byte looked for falls against the sixteen-byte steps.
    func testTheSixteenByteMarkupTestAnswersAsTheByteByByteTest() {
        var generator = Generator(state: 0x5EED_D011)
        let fillers = ["a", "word ", "数", "é", "\u{1F600}", "fa", "f", ";", "#a", "x:y", "\u{EF}", "\u{FF01}"]
        let triggers = ["<", "\\", "\n", "*", "_", "&", "#x1;", "#;", "ﬂ", ":fa-", "fa:fa-", "fab:fa-", "fax:fa-", ":", "#"]
        var unmarkedCount = 0
        for _ in 0..<20_000 {
            var text = (0..<generator.next(below: 40)).map { _ in fillers[generator.next(below: fillers.count)] }.joined()
            if generator.next(below: 3) > 0 {
                let trigger = triggers[generator.next(below: triggers.count)]
                let offset = text.unicodeScalars.count == 0 ? 0 : generator.next(below: text.unicodeScalars.count + 1)
                var scalars = Array(text.unicodeScalars)
                scalars.insert(contentsOf: trigger.unicodeScalars, at: offset)
                text = String(String.UnicodeScalarView(scalars))
            }
            for isLiteral in [false, true] {
                let bytes = Array(text.utf8)
                let expected = DiagramLabelLineBreaks.isUnmarked(bytes, isLiteral: isLiteral)
                XCTAssertEqual(bytes.withUnsafeBufferPointer { bytes in DiagramLabelLineBreaks.isUnmarked(bytes, isLiteral: isLiteral) }, expected,
                               "\(text.debugDescription) \(isLiteral)")
                if expected { unmarkedCount += 1 }
            }
        }
        XCTAssertGreaterThan(unmarkedCount, 5_000)
    }

    /// Every label the preparation of every corpus decodes, decoded again by 0.7.0's code.
    func testEveryLabelOfEveryCorpusIsTheScalarDecodersLabel() throws {
        let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))
        let observed = ObservedLabels()
        DiagramLabelDecodingObservation.observer = { text, form, label in observed.check(text, form: form, label: label) }
        defer { DiagramLabelDecodingObservation.observer = nil }
        for (_, sources) in try OutputDigest.corpora() {
            for source in sources {
                _ = OutputDigest.Outcome(source: source, typography: typography, narrowColumnWidths: [])
            }
        }
        XCTAssertGreaterThan(observed.labelCount, 10_000, "labels checked")
        XCTAssertGreaterThan(observed.markedCount, 150, "labels with markup checked")
        XCTAssertEqual(observed.differences, [], "labels unlike 0.7.0's")
    }

    /// Long labels of breaks, entities, tags, Markdown markers and icons: tenfold text decodes within forty times the time.
    func testLongLabelsDecodeInTimeThatGrowsWithTheirLength() {
        let texts: [(String, (Int) -> String)] = [
            ("entities and breaks", { count in String(repeating: "#35;&amp;<br>", count: count) }),
            ("tags", { count in String(repeating: "<b>x</b><span a=1>y</span>", count: count) }),
            ("markers", { count in String(repeating: "**a** _b_ ", count: count) }),
            ("unclosed markers", { count in String(repeating: "*", count: count * 4) }),
            ("icons", { count in String(repeating: "fa:fa-car ", count: count) }),
            ("unclosed tags", { count in String(repeating: "<b ", count: count * 3) }),
            ("indented Markdown", { count in String(repeating: "   line\r\n", count: count) }),
        ]
        for (name, text) in texts {
            for form in Self.forms {
                func seconds(_ count: Int) -> Double {
                    let written = text(count)
                    let started = Date()
                    _ = DiagramLabelDecoder.label(from: written, form: form)
                    return Date().timeIntervalSince(started)
                }
                _ = seconds(100)
                let small = (0..<3).map { _ in seconds(500) }.min() ?? 0
                let large = (0..<3).map { _ in seconds(5_000) }.min() ?? 0
                XCTAssertLessThan(large, max(small, 0.000_5) * 40, "\(name) as \(form): \(small) s for 500, \(large) s for 5,000")
            }
        }
    }
}

/// The corpus labels the observer saw, each decoded again by the reference and compared.
private final class ObservedLabels: @unchecked Sendable {
    private(set) var labelCount = 0
    private(set) var markedCount = 0
    private(set) var differences: [String] = []

    func check(_ text: String, form: DiagramLabelDecoder.Form, label: DiagramLabel) {
        let reference = ReferenceDiagramLabelDecoder.label(from: text, form: form)
        labelCount += 1
        if !label.isReadWithoutMarkup { markedCount += 1 }
        let isSame = label.lines.map { line in Array(line.utf8) } == reference.lines.map { line in Array(line.utf8) }
            && label.spans?.map { line in line.map { span in "\(span.style.rawValue)|" + span.text } }
            == reference.spans?.map { line in line.map { span in "\(span.style.rawValue)|" + span.text } }
            && label.isReadWithoutMarkup == reference.isReadWithoutMarkup
        if !isSame, differences.count < 20 { differences.append("\(text.debugDescription) as \(form): \(label.lines) against \(reference.lines)") }
    }
}
