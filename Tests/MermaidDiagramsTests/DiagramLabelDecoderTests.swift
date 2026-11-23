/**
 * File: DiagramLabelDecoderTests.swift
 * ------------------------------------
 * Layer: Tests
 * Description: How the text written for a node, an edge or a group becomes the lines drawn.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.4
 * Date: 23/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class DiagramLabelDecoderTests: XCTestCase {
    private func lines(_ text: String, form: DiagramLabelDecoder.Form = .plain) -> [String] {
        DiagramLabelDecoder.label(from: text, form: form).lines
    }

    func testEveryLineBreakTagAndLineBreakEndsALine() {
        XCTAssertEqual(lines("one<br>two<BR/>three<br />four\nfive"), ["one", "two", "three", "four", "five"])
    }

    /// Pele breaks at `<br\s*\/?>` only (text/label.ts `RE_BREAK`); `<br class="x">` is another `br` tag, dropped
    /// without a break, and `<br/ >` is no tag at all, so it stays as text.
    func testALineBreakTagWithSpacesBeforeItsSlashEndsALineAndOtherFormsDoNot() {
        XCTAssertEqual(lines("first<br  />second<BR\t/>third<br class=\"x\">fourth<br/ >fifth"), ["first", "second", "thirdfourth<br/ >fifth"])
        XCTAssertEqual(lines("<b>kept</b> word<br"), ["kept word<br"])
    }

    func testAWrittenBackslashAndNEndsALine() {
        XCTAssertEqual(lines("one\\ntwo"), ["one", "two"])
        XCTAssertEqual(lines("\\node"), ["", "ode"])
    }

    func testHTMLTagsAreDroppedAndAnythingElseShapedLikeATagStays() {
        XCTAssertEqual(lines("<b>bold</b> and <span style=\"x\">styled</span>"), ["bold and styled"])
        XCTAssertEqual(lines("a < b and c<5"), ["a < b and c<5"])
        XCTAssertEqual(lines("List<T> and <brand>kept</brand>"), ["List<T> and <brand>kept</brand>"])
    }

    func testMermaidAndHTMLEntityCodesBecomeTheirCharacters() {
        XCTAssertEqual(lines("#quot;quoted#quot; #9829; #35;"), ["\"quoted\" ♥ #"])
        XCTAssertEqual(lines("&lt;tag&gt; &amp; &#65;&#x42;"), ["<tag> & AB"])
    }

    func testAnUnknownEntityOrOneThatIsNoCharacterStaysAsWritten() {
        XCTAssertEqual(lines("#unknown; &nothing; #1114112;"), ["#unknown; &nothing; #1114112;"])
    }

    func testAnEntityCodeIsDecodedAfterTagsAreDroppedSoItsTextStays() {
        XCTAssertEqual(lines("#lt;b#gt;not bold#lt;/b#gt;"), ["<b>not bold</b>"])
    }

    func testAMarkdownStringLosesItsEmphasisMarkersAndKeepsUnderscoresBetweenLetters() {
        XCTAssertEqual(lines("**Bold** and *italic* in snake_case\n__strong__ _Markdown_", form: .markdown),
                       ["Bold and italic in snake_case", "strong Markdown"])
        // A marker that opens nothing (no text after it, or none of its kind later) is text, as in Pele's `inline`.
        XCTAssertEqual(lines("2 * 3 and a* b", form: .markdown), ["2 * 3 and a* b"])
    }

    /// Pele trims each line and draws the spaces inside it as written (text/label.ts `layoutLines`).
    func testLinesAreTrimmedAndTheirSpacesInsideKept() {
        XCTAssertEqual(lines("  wide \t  gap  "), ["wide \t  gap"])
        XCTAssertEqual(lines("\n first  <br>  second \n"), ["first", "second"])
    }

    func testLiteralTextKeepsItsTagsAndStillBreaksAtBreakTags() {
        XCTAssertEqual(lines("<b>kept</b> &amp; <i>as written</i><br/>next  line", form: .literal), ["<b>kept</b> & <i>as written</i>", "next  line"])
        XCTAssertEqual(lines("plain", form: .literal), ["plain"])
    }
}
