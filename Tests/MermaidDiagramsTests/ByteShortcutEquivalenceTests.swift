/**
 * File: ByteShortcutEquivalenceTests.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: Checks the shortcuts that read bytes or scalars where the old code read characters against the old
 *              reading: Gantt date templates, tree view lines, the YAML reader's white space, a flowchart text's
 *              trimming, the removal of !important in any case, the typography's held measurers and a YAML mapping's
 *              plain keys.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams
import XCTest

final class ByteShortcutEquivalenceTests: XCTestCase {
    /// A generator of texts made of `parts`, the same at every run.
    private static func texts(of parts: [String], count: Int, longest: UInt64, seed: UInt64) -> [String] {
        var state = seed
        var texts = parts + [""]
        for _ in 0..<count {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            var text = ""
            for _ in 0..<Int((state >> 40) % longest) {
                state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                text += parts[Int((state >> 33) % UInt64(parts.count))]
            }
            texts.append(text)
        }
        return texts
    }

    func testAnASCIIGanttTemplateSplitAtItsBytesGivesThePiecesOfItsCharacters() {
        let parts = ["YYYY", "YY", "MM", "M", "MMM", "DD", "Do", "D", "d", "dddd", "HH", "h", "mm", "ss", "SSS", "A", "a", "X", "x", "Z", "ZZ", "Q",
                     "[", "]", "[]", "[at]", "-", "/", ":", " ", "T", "w", "k", "\n", "E"]
        for template in Self.texts(of: parts, count: 10_000, longest: 8, seed: 0x5EED_0001) {
            XCTAssertEqual(GanttDateFormat.pieces(ofASCII: Array(template.utf8)), GanttDateFormat.pieces(ofCharacters: template),
                           template.debugDescription)
        }
    }

    func testATreeViewLineToldFromItsFirstScalarPassesAsItsCharactersSay() {
        let parts = [" ", "\t", "  ", "%%", "%", "{", "title", "title ", "title\t", "titles", "t", "accTitle", "accDescr", "acc", "a", ":", "{", "x",
                     "name", "├── ", "└─", "│", "┃", "\u{A0}", "\u{3000}", "\u{301}", "é", "#", "-"]
        for line in Self.texts(of: parts, count: 20_000, longest: 6, seed: 0x5EED_0002) {
            XCTAssertEqual(TreeViewBoxDrawingReader.passesUnchanged(line), TreeViewBoxDrawingReader.passesUnchangedReadingCharacters(line),
                           line.debugDescription)
        }
    }

    func testATreeViewTitleAmongBoxDrawingPassesUnchanged() throws {
        let lines = try TreeViewBoxDrawingReader.lines(after: 1, in: "treeView-beta\n  title Files\n├── src\n│   └── main.swift\n")
        XCTAssertEqual(lines.map(\.text), ["treeView-beta", "  title Files", "    src", "        main.swift", ""])
    }

    func testTheYAMLReadersASCIIWhiteSpaceIsUnicodes() {
        for value in UInt32(0)..<0x80 {
            let scalar = Unicode.Scalar(value)!
            XCTAssertEqual(SequenceAttributesFlowSyntax.isWhitespace(scalar), scalar.properties.isWhitespace, "U+\(String(value, radix: 16))")
        }
        for scalar in ["\u{85}", "\u{A0}", "\u{2028}", "\u{3000}", "\u{FEFF}", "é"] as [Unicode.Scalar] {
            XCTAssertEqual(SequenceAttributesFlowSyntax.isWhitespace(scalar), scalar.properties.isWhitespace)
        }
    }

    func testAFlowchartTextIsTrimmedWhereEitherEndIsNotPrintableASCII() throws {
        for (statement, label) in [("A[ text ]", "text"), ("A[text ]", "text"), ("A[ text]", "text"), ("A[\ttext\t]", "text"), ("A[text]", "text"),
                                   ("A[ é ]", "é"), ("A[é]", "é"), ("A[\u{A0}text\u{A0}]", "text")] {
            let diagram = try FlowchartReading.flowchart("flowchart TD\n" + statement)
            XCTAssertEqual(diagram.nodes.first?.label, DiagramLabel(label), statement)
        }
        XCTAssertFalse(MermaidByte.startsAndEndsWithPrintableASCII(" a"))
        XCTAssertFalse(MermaidByte.startsAndEndsWithPrintableASCII("a\u{7F}"))
        XCTAssertTrue(MermaidByte.startsAndEndsWithPrintableASCII("a b"))
    }

    func testImportanceIsTakenOutInAnyCase() {
        XCTAssertEqual(MermaidByte.withoutImportance("red !IMPORTANT"), "red ")
        XCTAssertEqual(MermaidByte.withoutImportance("red!Important!important"), "red")
        XCTAssertEqual(MermaidByte.withoutImportance("red important"), "red important")
    }

    func testAPlainYAMLKeyIsTheTextItsFlowValueGives() throws {
        let parts = ["a", "Z", "_", "-", "0", "9", "x", "null", "Null", "NULL", "true", "True", "TRUE", "false", "False", "FALSE", "~", ".", "inf",
                     ".inf", "nan", "e", "E", "+", "1e3", "0x1F", "0o7", "0b1", " ", "#", "é", "'", "\""]
        var plainCount = 0
        for key in Self.texts(of: parts, count: 20_000, longest: 4, seed: 0x5EED_0003) {
            let scalars = Array(key.unicodeScalars)
            guard let plain = SequenceAttributesBlockSyntax.plainKeyText(scalars) else { continue }
            plainCount += 1
            let read = try SequenceAttributesFlowSyntax.value(in: scalars, at: 0, stops: []).0.javaScriptText
            XCTAssertEqual(plain, read, key.debugDescription)
        }
        XCTAssertGreaterThan(plainCount, 1_000)
        for key in ["null", "Null", "TRUE", "False", "1e3", "-a", "", "a b", "é"] {
            XCTAssertNil(SequenceAttributesBlockSyntax.plainKeyText(Array(key.unicodeScalars)), key)
        }
    }

    func testTheTypographyGivesAHeldMeasurerOnlyOfTheSizeAndEmphasisAskedFor() {
        let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 14))
        let held = [typography.nodeText, typography.edgeText, typography.boldNodeText, typography.smallText, typography.rowText, typography.axisText,
                    typography.boldEdgeText, typography.boldRowText, typography.monospacedEdgeText, typography.monospacedAxisText,
                    typography.italicEdgeText]
        let sizes = Set(held.map(\.fontSize)).union([1, 33])
        for size in sizes {
            for isBold in [false, true] {
                for isItalic in [false, true] {
                    for isMonospaced in [false, true] {
                        let measurer = typography.measurer(size: size, isBold: isBold, isItalic: isItalic, isMonospaced: isMonospaced)
                        let asked = "size \(size), bold \(isBold), italic \(isItalic), monospaced \(isMonospaced)"
                        XCTAssertEqual(measurer.fontSize, size, asked)
                        XCTAssertEqual(measurer.isBold, isBold, asked)
                        XCTAssertEqual(measurer.isItalic, isItalic, asked)
                        XCTAssertEqual(measurer.isMonospaced, isMonospaced, asked)
                    }
                }
            }
        }
    }
}
