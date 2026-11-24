/**
 * File: DiagramTextWrappingEquivalenceTests.swift
 * -----------------------------------------------
 * Layer: Tests
 * Description: Checks that wrapping on UTF-8 bytes, with widths continued over printable ASCII, gives the lines and
 *              the widths, to the bit, of release 0.6.1's wrapping on Strings, kept here, on random labels of ASCII and
 *              other text, runs of JavaScript white space, soft hyphens and emphasis, at many widths; that a label's
 *              bytes decide whether it is read for markup as its scalars did; and C4's spoken kind names.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 24/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams
import XCTest

final class DiagramTextWrappingEquivalenceTests: XCTestCase {
    /// Words, white space of every kind JavaScript has, soft hyphens, zero-width spaces, Chinese and Japanese text with
    /// its punctuation, accents, a combining mark, an emoji and a tab, which Core Text measures where the table does not.
    private static let parts = ["word", "a", "Wrapping", "x1", "(", ")", ",", ".", "-", ":", "!", "?", "'", "\"", "~", "{", "}",
                                " ", " ", "  ", "   ", "\t", "\n", "\r", "\u{0B}", "\u{0C}", "\u{A0}", "\u{1680}", "\u{2000}", "\u{2003}",
                                "\u{200A}", "\u{2028}", "\u{2029}", "\u{202F}", "\u{205F}", "\u{3000}", "\u{FEFF}", "\u{AD}", "\u{AD}",
                                "hy\u{AD}phen", "\u{200B}", "日本語", "中", "、", "。", "（", "「", "」", "é", "e\u{301}", "\u{1F600}", "ü", "→", "«", "»"]
    private static let styles: [DiagramTextStyle] = [[], [], .bold, .italic, .monospaced, [.bold, .italic]]
    private static let widths: [CGFloat] = [0, 1, 5, 12, 20, 33.5, 47, 60, 80, 99.25, 120, 150, 200, 260, 400]

    private struct Generator {
        var state: UInt64

        mutating func next(below bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(bound))
        }
    }

    private func randomLine(_ generator: inout Generator, asciiOnly: Bool) -> [ReferenceMeasuredSpan] {
        let parts = asciiOnly ? Self.parts.filter { part in part.unicodeScalars.allSatisfy { scalar in scalar.value >= 0x20 && scalar.value < 0x7F } }
            : Self.parts
        return (0..<(1 + generator.next(below: 4))).map { _ in
            let text = (0..<generator.next(below: 14)).map { _ in parts[generator.next(below: parts.count)] }.joined()
            return ReferenceMeasuredSpan(text: text, style: Self.styles[generator.next(below: Self.styles.count)], width: 0)
        }
    }

    private func assertSameWrapping<Measurer: DiagramTextMeasuring>(_ measurer: Measurer, seed: UInt64, lineCount: Int, asciiOnly: Bool,
                                                                   file: StaticString = #filePath, line: UInt = #line) {
        var generator = Generator(state: seed)
        var wrappedLineCount = 0
        for _ in 0..<lineCount {
            let spans = randomLine(&generator, asciiOnly: asciiOnly)
            for maximumWidth in Self.widths {
                var wrapping = ReferenceTextWrapping(measuring: DiagramStyledMeasuring(measurer), lines: ReferenceMeasuredLines(keepsRuns: true),
                                                   maximumWidth: maximumWidth)
                wrapping.wrap(spans)
                let wrapped = wrapping.finishedLines
                var reference = StringPieceTextWrapping(measuring: DiagramStyledMeasuring(measurer), maximumWidth: maximumWidth)
                reference.wrap(spans)
                var expected = ReferenceMeasuredLines(keepsRuns: true)
                for line in reference.lines { expected.add(line.spans, width: line.width) }
                let description = "\(spans.map(\.text).debugDescription) at \(maximumWidth)"
                XCTAssertEqual(wrapped.lines, expected.lines, description, file: file, line: line)
                XCTAssertEqual(wrapped.widths.map(\.bitPattern), expected.widths.map(\.bitPattern), description, file: file, line: line)
                XCTAssertEqual(wrapped.runs.map { runs in runs.map(\.text) }, expected.runs.map { runs in runs.map(\.text) }, description, file: file, line: line)
                XCTAssertEqual(wrapped.runs.map { runs in runs.map(\.style) }, expected.runs.map { runs in runs.map(\.style) }, description,
                               file: file, line: line)
                XCTAssertEqual(wrapped.runs.map { runs in runs.map(\.width.bitPattern) }, expected.runs.map { runs in runs.map(\.width.bitPattern) },
                               description, file: file, line: line)
                XCTAssertEqual(wrapped.hasEmphasis, expected.hasEmphasis, description, file: file, line: line)
                wrappedLineCount += expected.lines.count
            }
        }
        XCTAssertGreaterThan(wrappedLineCount, lineCount * Self.widths.count, "some lines wrap", file: file, line: line)
    }

    /// At 16 points the system font's advances are binary fractions short enough that any order of adding them gives the
    /// same sum; at 13.7 and 17.3 they are rounded, so that a width added up in another order differs in its last bits.
    private static let fonts = [DiagramFont(postScriptName: nil, size: 16), DiagramFont(postScriptName: nil, size: 13.7),
                                DiagramFont(postScriptName: "Helvetica", size: 17.3)]

    func testCoreTextWrappingOfPrintableASCIIIsTheStringWrappingToTheBit() {
        for (index, font) in Self.fonts.enumerated() {
            assertSameWrapping(CoreTextDiagramTextMeasurer(font: font), seed: 0x5EED_0001 + UInt64(index), lineCount: 800, asciiOnly: true)
        }
    }

    func testCoreTextWrappingOfAnyTextIsTheStringWrappingToTheBit() {
        for (index, font) in Self.fonts.enumerated() {
            assertSameWrapping(CoreTextDiagramTextMeasurer(font: font), seed: 0x5EED_0011 + UInt64(index), lineCount: 600, asciiOnly: false)
        }
    }

    /// Adding a piece's own width to the width before it, instead of continuing the sum, rounds differently: the check
    /// above would see it.
    func testAddingSeparateWidthsRoundsDifferently() {
        let measurer = CoreTextDiagramTextMeasurer(font: Self.fonts[1])
        guard let advances = measurer.printableASCIIAdvances else { return XCTFail("a registered face has advances") }
        let words = ["Wrapping ", "a ", "label ", "of ", "many ", "words ", "differs ", "in ", "its ", "last ", "bits"]
        var continued: CGFloat = 0
        var added: CGFloat = 0
        var differs = false
        for word in words {
            continued = advances.width(continuing: continued, over: word.utf8)
            added += measurer.width(of: word)
            differs = differs || continued != added
        }
        XCTAssertEqual(continued.bitPattern, measurer.width(of: words.joined()).bitPattern)
        XCTAssertTrue(differs)
    }

    func testOtherMeasurersStillMeasureTheJoinedText() {
        assertSameWrapping(UniformWidthTextMeasurer(characterWidth: 7.3), seed: 0x5EED_0004, lineCount: 1_000, asciiOnly: false)
    }
}

/// The wrapping of release 0.6.1, kept as it was written: each piece a String, trimmed into a new String, joined with
/// `+=` and the joined text measured again. The pieces are read scalar by scalar (Pele's pattern itself), so that the
/// ASCII shortcut is checked too.
struct StringPieceTextWrapping<Measurer: DiagramTextMeasuring> {
    private var measuring: DiagramStyledMeasuring<Measurer>
    private let maximumWidth: CGFloat
    private(set) var lines: [(spans: [ReferenceMeasuredSpan], width: CGFloat)] = []
    private var current: [ReferenceMeasuredSpan] = []
    private var width: CGFloat = 0

    init(measuring: DiagramStyledMeasuring<Measurer>, maximumWidth: CGFloat) {
        self.measuring = measuring
        self.maximumWidth = maximumWidth
    }

    /// The measurer, with the fonts it made for emphasis, to measure the next line with.
    var finishedMeasuring: DiagramStyledMeasuring<Measurer> { measuring }

    /// Lays `line` into lines; every span of a line is wrapped together, the last one ending the line.
    mutating func wrap(_ line: [ReferenceMeasuredSpan]) {
        for (index, span) in line.enumerated() {
            wrap(span, isLastOfLine: index == line.count - 1)
        }
        if !current.isEmpty || lines.isEmpty { commit() }
    }

    private mutating func wrap(_ span: ReferenceMeasuredSpan, isLastOfLine: Bool) {
        let pieces = DiagramTextPieces.pieces(ofScalars: span.text)
        let softHyphenWidths = span.text.unicodeScalars.contains(DiagramTextPieces.softHyphen)
            ? StringPieceSoftHyphenWidths(pieces: pieces, style: span.style, isLastOfLine: isLastOfLine, measuring: &measuring) : nil
        for (index, written) in pieces.enumerated() {
            var piece = written
            let pieceWidth = softHyphenWidths?.own[index] ?? measuring.width(of: JavaScriptStringTrimming.trimmedEnd(piece), style: span.style)
            if width > 0, !fits(piece, index: index, pieceWidth: pieceWidth, style: span.style, softHyphenWidths: softHyphenWidths) {
                // Breaking at a space leaves a soft hyphen before it hidden.
                commit(showingHyphen: JavaScriptStringTrimming.trimmedStart(piece) == piece)
                piece = JavaScriptStringTrimming.trimmedStart(piece)
            }
            append(piece, pieceWidth: pieceWidth, style: span.style)
        }
    }

    private mutating func fits(_ piece: String, index: Int, pieceWidth: CGFloat, style: DiagramTextStyle, softHyphenWidths: StringPieceSoftHyphenWidths?) -> Bool {
        guard let softHyphenWidths, piece.unicodeScalars.last == DiagramTextPieces.softHyphen else { return width + pieceWidth <= maximumWidth }
        var shown = piece.unicodeScalars
        shown.removeLast()
        shown.append("-")
        return width + measuring.width(of: String(shown), style: style) <= maximumWidth || width + softHyphenWidths.rest[index] <= maximumWidth
    }

    private mutating func append(_ piece: String, pieceWidth: CGFloat, style: DiagramTextStyle) {
        if var last = current.popLast() {
            if last.style == style {
                last.text += piece
                // Measured again only when the piece adds width, so that zero-width pieces take no time.
                if pieceWidth > 0 || JavaScriptStringTrimming.endsWithWhitespace(piece) {
                    let before = last.width
                    last.width = measuring.width(of: last.text, style: style)
                    width += last.width - before
                }
                current.append(last)
                return
            }
            current.append(last)
        }
        let pieceFullWidth = measuring.width(of: piece, style: style)
        current.append(ReferenceMeasuredSpan(text: piece, style: style, width: pieceFullWidth))
        width += pieceFullWidth
    }

    /// Ends the line: its last span's trailing spaces dropped and, when `showingHyphen`, a soft hyphen it ends with
    /// shown as `-`.
    private mutating func commit(showingHyphen: Bool = false) {
        if var last = current.popLast() {
            var trimmed = JavaScriptStringTrimming.trimmedEnd(last.text)
            if showingHyphen, last.text.unicodeScalars.last == DiagramTextPieces.softHyphen {
                var shown = trimmed.unicodeScalars
                shown.removeLast()
                shown.append("-")
                trimmed = String(shown)
            }
            if trimmed != last.text {
                last.text = trimmed
                let trimmedWidth = measuring.width(of: trimmed, style: last.style)
                width += trimmedWidth - last.width
                last.width = trimmedWidth
            }
            current.append(last)
        }
        lines.append((current, width))
        current = []
        width = 0
    }
}

/// The widths Pele works out for the pieces of a span with a soft hyphen: each piece without its trailing spaces and
/// its final soft hyphen (`own`), and the width of the rest of its word from each piece on (`rest`), unknown past the
/// span unless the span ends the line.
private struct StringPieceSoftHyphenWidths {
    let own: [CGFloat]
    let rest: [CGFloat]

    init<Measurer>(pieces: [String], style: DiagramTextStyle, isLastOfLine: Bool, measuring: inout DiagramStyledMeasuring<Measurer>) {
        var own = [CGFloat](repeating: 0, count: pieces.count)
        var rest = [CGFloat](repeating: 0, count: pieces.count + 1)
        for index in pieces.indices.reversed() {
            let endsWithHyphen = pieces[index].unicodeScalars.last == DiagramTextPieces.softHyphen
            var end = JavaScriptStringTrimming.trimmedEnd(pieces[index]).unicodeScalars
            if endsWithHyphen { end.removeLast() }
            own[index] = measuring.width(of: String(end), style: style)
            if !endsWithHyphen {
                rest[index] = own[index]
            } else if index == pieces.count - 1 {
                rest[index] = isLastOfLine ? own[index] : .infinity
            } else {
                rest[index] = own[index] + rest[index + 1]
            }
        }
        self.own = own
        self.rest = rest
    }
}

/// Checks that the bytes alone decide whether a label is read for its markup as its scalars decided in release 0.6.1,
/// and that what C4 diagrams say of their shapes' kinds is the kinds' names in words.
final class DiagramLabelByteCheckEquivalenceTests: XCTestCase {
    private static let parts = ["word", " ", "a", "<", "<br>", "\\", "\\n", "\n", "\r", "*", "_", "&", "&amp;", "#", ";", "#quot;", "#9829;",
                                "# ;", "#;", "#a b;", "fa:fa-", "fab:fa-", "fas:fa-x", "fax:fa-", "f a:fa-", ":fa-", ":fa", "fa:", ":", "a:fa-b",
                                "\u{FB02}", "\u{FB01}", "\u{FEFF}", "\u{FF01}", "é", "日本", "\u{A0}", "\t", "ok", "x1", "-"]

    func testTheBytesDecideAsTheScalarsDid() {
        var state: UInt64 = 0x00C0_FFEE_D00D
        var markedCount = 0
        for _ in 0..<30_000 {
            var text = ""
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            for _ in 0..<Int((state >> 40) % 7) {
                state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                text += Self.parts[Int((state >> 33) % UInt64(Self.parts.count))]
            }
            for isLiteral in [false, true] {
                var scalars = Array(text.unicodeScalars)
                if isLiteral { scalars = DiagramLabelLineBreaks.literalText(scalars) }
                let expected = Self.isUnmarkedReadScalarByScalar(scalars)
                XCTAssertEqual(DiagramLabelLineBreaks.isUnmarked(Array(text.utf8), isLiteral: isLiteral), expected, "\(text.debugDescription) \(isLiteral)")
                if !expected { markedCount += 1 }
            }
        }
        XCTAssertGreaterThan(markedCount, 10_000)
    }

    func testEachKindIsSpokenAsItsNameInWords() {
        for kind in C4ShapeKind.allCases {
            XCTAssertEqual(MermaidDiagramAccessibility.spokenName(of: kind), kind.rawValue.replacingOccurrences(of: "_", with: " "))
        }
    }
}

extension DiagramLabelByteCheckEquivalenceTests {
    /// Release 0.6.1's test of whether Pele lays the text out as one line as written, trimmed (its `RE_MARKUP` test), on
    /// the text's scalars: no `<`, backslash, line break, `*` or `_`, no `fa:fa-` icon, no `&`, and no Mermaid code
    /// (`#name;`, which Pele hides behind characters it then tests for).
    static func isUnmarkedReadScalarByScalar(_ scalars: [Unicode.Scalar]) -> Bool {
        var hasHash = false
        var hasSemicolon = false
        for scalar in scalars {
            switch scalar {
            // Pele also reads for markup any text with a `ﬂ`, the first character of its hidden entity codes.
            case "<", "\\", "\n", "*", "_", "&", "\u{FB02}": return false
            case "#": hasHash = true
            case ";": hasSemicolon = true
            default: break
            }
        }
        if hasHash, hasSemicolon, DiagramLabelEntities.mermaidCodesAsHTML(scalars) != scalars { return false }
        return !DiagramLabelIcons.containsIconName(scalars[...])
    }
}
