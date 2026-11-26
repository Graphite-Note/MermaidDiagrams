/**
 * File: DiagramFlatTextMarkdownTests.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: Markdown strings measured on the flat path (`DiagramFlatTextMeasuring.measure(markdown:)`) against their
 *              blocks from the label decoder's Markdown: texts without markup, underscores inside words, and every
 *              Markdown text that must still take the decoder, in three faces at four widths, from Strings and from
 *              bytes, and that the fast path takes the texts it is meant to.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics
import XCTest
@testable import MermaidDiagrams

final class DiagramFlatTextMarkdownTests: XCTestCase {
    /// 16 and 12 points sum exactly, 12.8 does not.
    private static let measurers = [CoreTextDiagramTextMeasurer(font: DiagramFont(postScriptName: nil, size: 16)),
                                    CoreTextDiagramTextMeasurer(font: DiagramFont(postScriptName: nil, size: 12)),
                                    CoreTextDiagramTextMeasurer(font: DiagramFont(postScriptName: nil, size: 12.8))]
    private static let widths: [CGFloat] = [.infinity, 240, 40, 0]

    private static let writtenTexts = [
        "REQ_001", "test_entity", "  checkout_req  ", "a_b c_d e_f g_h i_j k_l m_n o_p q_r s_t u_v w_x y_z", "snake_case_name with more_words here",
        "_leading", "trailing_", "a__b", "a_ b", "a _b", "_italic_", "__bold__", "x_*y*", "é_x", "x_é", "a_b\tc", "a_b<br>c_d", "a_b\nc_d",
        "a_b &amp; c", "a_b #35; c", "a_b:fa-car", "a\\_b", "1_2", "Z_9_a", "", "   ", "plain words only", "a*b", "**bold** text_here",
    ]

    func testMarkdownStringsMeasureAsTheirBlocks() {
        var random = RandomMarkdownTexts(seed: 0x4D_2D_5F)
        let texts = Self.writtenTexts + (0..<3_000).map { _ in random.text() }
        for measurer in Self.measurers {
            for width in Self.widths {
                XCTAssertEqual(Self.differences(texts, measurer: measurer, maximumWidth: width), [], "\(measurer.fontSize) pt at \(width)")
            }
        }
    }

    /// Texts with underscores inside words, and without markup, stay on the flat path: their lines are ranges of the
    /// source, not bytes the decoder made.
    func testUnderscoresInsideWordsAndUnmarkedTextsStayOnTheFlatPath() {
        let flat = DiagramFlatMeasurer(Self.measurers[0])
        for text in ["REQ_001", "test_entity", "a_b c_d e_f", "snake_case_name with more_words here", "plain words", "  checkout_req  "] {
            var lines = DiagramMeasuredLines()
            var bytes = Array(text.utf8)
            let measured = bytes.withUnsafeMutableBufferPointer { bytes in
                DiagramFlatTextMeasuring.measure(markdown: UnsafeBufferPointer(bytes), MermaidTextRange(start: 0, end: bytes.count), measurer: flat,
                                                 maximumWidth: 60, into: &lines)
            }
            XCTAssertGreaterThan(measured.lineCount, 0, text)
            for index in measured.lineIndices { XCTAssertLessThan(lines[index].start, DiagramMeasuredLines.derivedOffset, "\(text): line \(index)") }
        }
        for text in ["_leading", "a__b", "_italic_", "x_é", "a_b\tc", "a\\_b"] {
            var lines = DiagramMeasuredLines()
            var bytes = Array(text.utf8)
            let measured = bytes.withUnsafeMutableBufferPointer { bytes in
                DiagramFlatTextMeasuring.measure(markdown: UnsafeBufferPointer(bytes), MermaidTextRange(start: 0, end: bytes.count), measurer: flat,
                                                 maximumWidth: 60, into: &lines)
            }
            for index in measured.lineIndices { XCTAssertGreaterThanOrEqual(lines[index].start, DiagramMeasuredLines.derivedOffset, "\(text): line \(index)") }
        }
    }

    /// Each text measured from its String, and from bytes around which other text is written, drawn against its block.
    private static func differences<Measurer: DiagramTextMeasuring>(_ texts: [String], measurer: Measurer, maximumWidth: CGFloat) -> [String] {
        let flat = DiagramFlatMeasurer(measurer)
        var differences: [String] = []
        var bytes: [UInt8] = []
        var ranges: [MermaidTextRange] = []
        for text in texts {
            bytes += Array("a_b<br>".utf8)
            let start = bytes.count
            bytes += Array(text.utf8)
            ranges.append(MermaidTextRange(start: start, end: bytes.count))
            bytes += Array("_x **".utf8)
        }
        bytes.withUnsafeBufferPointer { source in
            for batchStart in stride(from: 0, to: texts.count, by: 100) {
                var lines = DiagramMeasuredLines()
                var fromBlocks = DiagramSceneBuilder()
                var fromStrings = DiagramSceneBuilder()
                var fromBytes = DiagramSceneBuilder()
                for index in batchStart..<min(batchStart + 100, texts.count) {
                    let center = CGPoint(x: CGFloat(index % 7) * 31.5, y: CGFloat(index) * 1.25)
                    let block = DiagramTextBlock(label: DiagramLabelDecoder.label(from: texts[index], form: .markdown), measurer: measurer, maximumWidth: maximumWidth)
                    fromBlocks.text(block.translated(by: CGVector(dx: center.x, dy: center.y)), .foreground, part: .label)
                    let written = DiagramFlatTextMeasuring.measure(markdownWritten: texts[index], measurer: flat, maximumWidth: maximumWidth, into: &lines)
                    fromStrings.text(written.centered(at: center), of: lines, .foreground, part: .label)
                    let read = DiagramFlatTextMeasuring.measure(markdown: source, ranges[index], measurer: flat, maximumWidth: maximumWidth, into: &lines)
                    fromBytes.text(read.centered(at: center), of: lines, source: source, .foreground, part: .label)
                    if written.size != block.size || read.size != block.size || written.lineHeight != block.lineHeight {
                        differences.append("size of \(texts[index].debugDescription)")
                    }
                }
                let expected = fromBlocks.scene(size: CGSize(width: 300, height: 300), font: SceneComparison.font)
                if let difference = SceneComparison.difference(fromStrings.scene(size: CGSize(width: 300, height: 300), font: SceneComparison.font), expected) {
                    differences.append("from Strings, batch \(batchStart): \(difference)")
                }
                if let difference = SceneComparison.difference(fromBytes.scene(size: CGSize(width: 300, height: 300), font: SceneComparison.font), expected) {
                    differences.append("from bytes, batch \(batchStart): \(difference)")
                }
            }
        }
        return differences
    }
}

/// Random Markdown texts of words, underscores and the bytes around them that decide whether Markdown reads them as
/// markup: stars, breaks, entities, tabs, letters past ASCII.
private struct RandomMarkdownTexts {
    private var state: UInt64
    private static let pieces = ["a", "b", "Z", "9", "0", "_", "_", "_", "__", " ", " ", "  ", "*", "**", "<br>", "\t", "é", "&amp;", "#35;", ":", "\\",
                                 "word", "snake_case", "REQ_", "x_y", "\n"]

    init(seed: UInt64) {
        state = seed
    }

    private mutating func next(_ bound: Int) -> Int {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Int((state >> 33) % UInt64(bound))
    }

    mutating func text() -> String {
        // Most texts are of letters, digits, spaces and underscores alone, as a requirement's names and values are.
        let simple = next(3) > 0
        let pieceBound = simple ? 11 : Self.pieces.count
        return (0..<(1 + next(14))).map { _ in Self.pieces[next(pieceBound)] }.joined()
    }
}
