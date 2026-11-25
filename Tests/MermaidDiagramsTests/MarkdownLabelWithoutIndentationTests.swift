/**
 * File: MarkdownLabelWithoutIndentationTests.swift
 * ------------------------------------------------
 * Layer: Tests
 * Description: A Markdown label that holds a line of text from its first byte and no carriage return, as a
 *              requirement's `checkout_req` does, is decoded without being dedented, to the same lines and spans as
 *              0.7.0's decoder makes; texts that are dedented or whose line breaks are carriage returns still are.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

@testable import MermaidDiagrams
import XCTest

final class MarkdownLabelWithoutIndentationTests: XCTestCase {
    func testMarkdownTextIsDecodedAsTheReferenceDecodesItWithOrWithoutIndentation() {
        let texts = [
            "checkout_req", "checkout_req ", " checkout_req", "\tchecked_out", "a_b\n  c_d", "  a_b\n  c_d", "  a_b\n\n  c_d", "  a_b\n c_d", "a\r\nb_c",
            "a_b\rc", "\r", "\n", "", " ", "\u{3000}x_y", "x_y\u{3000}", "\u{A0}\u{A0}x_y\n\u{A0}z", "\n  x_y", "x\n\n  y_z", "_a_", "  _a_\n  *b*",
            "line_one\nline_two", "  \n_x_", "x_y\n  ", "\u{FEFF}a_b", "数_据", "e\u{301}_x", "a_b<br>  c_d", "a_b\\n  c",
        ]
        for text in texts {
            DiagramLabelByteDecoderTests.assertSame(DiagramLabelDecoder.label(from: text, form: .markdown),
                                                    ReferenceDiagramLabelDecoder.label(from: text, form: .markdown), "\(text.debugDescription)")
        }
    }

    /// Generated lines of words with underscores, indented or not, joined by line feeds or carriage returns.
    func testGeneratedMarkdownLinesAreDecodedAsTheReferenceDecodesThem() {
        let indents = ["", " ", "  ", "\t", "\u{A0}", "\u{3000}"]
        let words = ["checkout_req", "a", "_b_", "c_d_e", "**f**", "数", "x y", ""]
        let breaks = ["\n", "\r\n", "\r", "\n\n"]
        var state: UInt64 = 0x5EED_0425
        func next(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(bound))
        }
        for _ in 0..<4_000 {
            let lineCount = 1 + next(4)
            let text = (0..<lineCount).map { index in
                (index == 0 ? "" : breaks[next(breaks.count)]) + indents[next(indents.count)] + words[next(words.count)] + indents[next(indents.count)]
            }.joined()
            DiagramLabelByteDecoderTests.assertSame(DiagramLabelDecoder.label(from: text, form: .markdown),
                                                    ReferenceDiagramLabelDecoder.label(from: text, form: .markdown), "\(text.debugDescription)")
        }
    }
}
