/**
 * File: DiagramTextBlockEquivalenceTests.swift
 * --------------------------------------------
 * Layer: Tests
 * Description: Checks that random labels of every kind of text measured into a text storage, wrapped and broken between
 *              characters, are 0.7.0's blocks to the bit, in fonts whose advances sum exactly and fonts whose do not, and
 *              that spans of spaces alone wrap as they did at every width, and that long lines, many lines and long words
 *              are measured in time that grows with their length only.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

import CoreGraphics
import Foundation
@testable import MermaidDiagrams
import XCTest

final class DiagramTextBlockEquivalenceTests: XCTestCase {
    /// Words, white space of every kind JavaScript has (the space, a tab, a line feed, a carriage return, the vertical tab
    /// and form feed, the no-break, ogham, en quad to hair, line, paragraph, narrow no-break, medium mathematical and
    /// ideographic spaces and the byte order mark), soft hyphens, zero-width spaces, Chinese and Japanese text with its
    /// punctuation, accents, a combining mark, emoji, guillemets, quotes and braces: every part the wrapping's own
    /// equivalence test with release 0.6.1's String wrapping draws from, so that the wrapping on bytes meets each of them.
    private static let parts = ["word", "a", "Wrapping", "x1", "(", ")", ",", ".", "-", ":", "!", "?", "'", "\"", "~", "{", "}", " ", " ", "  ", "   ",
                                "\t", "\n", "\r", "\r\n", "\u{0B}", "\u{0C}", "\u{A0}", "\u{1680}", "\u{2000}", "\u{2003}", "\u{200A}", "\u{2028}",
                                "\u{2029}", "\u{202F}", "\u{205F}", "\u{3000}", "\u{FEFF}", "\u{AD}", "hy\u{AD}phen", "\u{200B}", "日本語", "中", "、", "。",
                                "（", "「", "」", "é", "e\u{301}", "\u{1F600}", "ü", "«", "»", "→", "LongUnbrokenWordOfManyLetters"]
    private static let styles: [DiagramTextStyle] = [[], [], [], .bold, .italic, .monospaced, [.bold, .italic]]
    private static let widths: [CGFloat] = [0, 1, 5, 12, 20, 33.5, 47, 60, 80, 99.25, 120, 150, 200, 260, 400]
    /// 16, 14 and 12 points sum exactly; 12.8, 17.3 and 9.1 do not.
    private static let fonts = [16, 14, 12, 12.8, 17.3, 9.1].map { size in DiagramFont(postScriptName: nil, size: size) }

    private struct Generator {
        var state: UInt64

        mutating func next(below bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(bound))
        }
    }

    /// A label of one to three lines, each of one to four spans, with an emphasis or not; or a label read by the decoder.
    private static func randomLabel(_ generator: inout Generator, asciiOnly: Bool) -> DiagramLabel {
        let parts = asciiOnly ? Self.parts.filter { part in part.utf8.allSatisfy { byte in byte < 0x80 } } : Self.parts
        func text() -> String { (0..<generator.next(below: 12)).map { _ in parts[generator.next(below: parts.count)] }.joined() }
        switch generator.next(below: 4) {
        case 0:
            return DiagramLabel(text())
        case 1:
            return DiagramLabel(lines: (0..<(1 + generator.next(below: 3))).map { _ in text() })
        default:
            let lines = (0..<(1 + generator.next(below: 3))).map { _ in
                (0..<generator.next(below: 4)).map { _ in DiagramLabelSpan(text: text(), style: Self.styles[generator.next(below: Self.styles.count)]) }
                    .filter { span in !span.text.isEmpty }
            }
            return DiagramLabel(spans: lines)
        }
    }

    private func assertSameBlocks<Measurer: DiagramTextMeasuring>(_ measurer: Measurer, seed: UInt64, labelCount: Int, asciiOnly: Bool,
                                                                 file: StaticString = #filePath, line: UInt = #line) {
        var generator = Generator(state: seed)
        var severalLineCount = 0
        for _ in 0..<labelCount {
            let label = Self.randomLabel(&generator, asciiOnly: asciiOnly)
            for maximumWidth in Self.widths {
                let description = "\(label.lines.debugDescription) at \(maximumWidth) in \(measurer.fontSize)"
                let block = DiagramTextBlock(label: label, measurer: measurer, maximumWidth: maximumWidth)
                DiagramTextStorageTests.assertSame(block, ReferenceTextBlock(label: label, measurer: measurer, maximumWidth: maximumWidth),
                                                   fontSize: measurer.fontSize, description, file: file, line: line)
                let broken = DiagramTextBlock(label: label, measurer: measurer, fittingWidth: maximumWidth)
                DiagramTextStorageTests.assertSame(broken, ReferenceTextBlock(label: label, measurer: measurer, wrappingWidth: maximumWidth,
                                                                              breakingWidth: maximumWidth),
                                                   fontSize: measurer.fontSize, "broken " + description, file: file, line: line)
                if broken.lineCount > 1 { severalLineCount += 1 }
            }
        }
        XCTAssertGreaterThan(severalLineCount, labelCount, "many labels wrap or break", file: file, line: line)
    }

    func testPrintableASCIILabelsAreTheReferenceBlocksToTheBit() {
        for (index, font) in Self.fonts.enumerated() {
            assertSameBlocks(CoreTextDiagramTextMeasurer(font: font), seed: 0x5EED_B001 + UInt64(index), labelCount: 160, asciiOnly: true)
        }
    }

    func testLabelsOfAnyTextAreTheReferenceBlocksToTheBit() {
        for (index, font) in Self.fonts.enumerated() {
            assertSameBlocks(CoreTextDiagramTextMeasurer(font: font), seed: 0x5EED_B011 + UInt64(index), labelCount: 120, asciiOnly: false)
        }
    }

    /// A span of spaces alone after text on its line, in the line's emphasis or another, at every quarter point of width
    /// from none to past the whole line: where the spaces do not fit after the text, the line is not ended for them, as
    /// 0.7.0 wrapped it (counting their width there makes an extra empty line).
    func testSpansOfSpacesAloneWrapAsTheReferenceAtEveryWidth() {
        let spaces = ["", " ", "   "]
        var labels: [DiagramLabel] = []
        for leading in ["ab", "word x1"] {
            for between in spaces.dropFirst() {
                for style in [DiagramTextStyle(), .bold] {
                    for trailing in ["", "cd", " ef"] {
                        let line = [DiagramLabelSpan(text: leading, style: []), DiagramLabelSpan(text: between, style: style)]
                            + (trailing.isEmpty ? [] : [DiagramLabelSpan(text: trailing, style: [])])
                        labels.append(DiagramLabel(spans: [line]))
                        labels.append(DiagramLabel(spans: [line, [DiagramLabelSpan(text: "next", style: .italic)]]))
                    }
                }
            }
        }
        for size in [16.0, 14, 12, 12.8] {
            let measurer = CoreTextDiagramTextMeasurer(font: DiagramFont(postScriptName: nil, size: size))
            for label in labels {
                for quarter in 0...(4 * 120) {
                    let maximumWidth = CGFloat(quarter) / 4
                    let description = "\(label.lines.debugDescription) at \(maximumWidth) in \(size)"
                    DiagramTextStorageTests.assertSame(DiagramTextBlock(label: label, measurer: measurer, maximumWidth: maximumWidth),
                                                       ReferenceTextBlock(label: label, measurer: measurer, maximumWidth: maximumWidth),
                                                       fontSize: size, description)
                }
            }
        }
    }

    func testOtherMeasurersMeasureAlike() {
        assertSameBlocks(UniformWidthTextMeasurer(characterWidth: 7.3), seed: 0x5EED_B021, labelCount: 200, asciiOnly: false)
    }

    func testBlocksOfLabelsWrittenOnAnotherThreadAreTheReferenceBlocks() {
        let measurer = CoreTextDiagramTextMeasurer(font: DiagramFont(postScriptName: nil, size: 16))
        let made = LabelBox()
        let thread = Thread {
            var generator = Generator(state: 0x5EED_B031)
            var labels: [DiagramLabel] = []
            for _ in 0..<200 { labels.append(Self.randomLabel(&generator, asciiOnly: false)) }
            made.set(labels)
        }
        thread.start()
        while made.labels == nil {}
        for label in made.labels ?? [] {
            let block = DiagramTextBlock(label: label, measurer: measurer, maximumWidth: 60)
            DiagramTextStorageTests.assertSame(block, ReferenceTextBlock(label: label, measurer: measurer, maximumWidth: 60), fontSize: 16, label.lines.debugDescription)
        }
    }

    /// Long lines, many lines and long words: the time per byte stays the same as the text grows tenfold.
    func testLongTextIsMeasuredInTimeThatGrowsWithItsLength() {
        let measurer = CoreTextDiagramTextMeasurer(font: DiagramFont(postScriptName: nil, size: 16))
        let texts: [(String, (Int) -> String)] = [
            ("words", { count in String(repeating: "word ", count: count) }),
            ("lines", { count in String(repeating: "line<br>", count: count) }),
            ("one word", { count in String(repeating: "x", count: count * 5) }),
            ("one word beyond ASCII", { count in String(repeating: "数", count: count * 2) }),
            ("emphasis", { count in String(repeating: "<b>bold</b> plain ", count: count / 3) }),
        ]
        for (name, text) in texts {
            func seconds(_ count: Int) -> Double {
                let label = DiagramLabelDecoder.label(from: text(count), form: .plain)
                let started = Date()
                _ = DiagramTextBlock(label: label, measurer: measurer, fittingWidth: 120)
                return Date().timeIntervalSince(started)
            }
            _ = seconds(200)
            let small = (0..<3).map { _ in seconds(1_000) }.min() ?? 0
            let large = (0..<3).map { _ in seconds(10_000) }.min() ?? 0
            XCTAssertLessThan(large, max(small, 0.000_5) * 40, "\(name): \(small) s for 1,000, \(large) s for 10,000")
        }
    }
}

/// Labels one thread makes and hands to another.
private final class LabelBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [DiagramLabel]?

    func set(_ labels: [DiagramLabel]) {
        lock.lock()
        stored = labels
        lock.unlock()
    }

    var labels: [DiagramLabel]? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}
