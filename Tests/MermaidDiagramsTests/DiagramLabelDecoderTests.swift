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

/// Each expectation is what Pele 1.13.0's `layoutLabel` (text/label.ts) makes of the same text after its preprocessing
/// (`encodeEntities`), run in Deno on these inputs.
final class DiagramLabelDecoderTests: XCTestCase {
    private func lines(_ text: String, form: DiagramLabelDecoder.Form = .plain) -> [String] {
        DiagramLabelDecoder.label(from: text, form: form).lines
    }

    private func spans(_ text: String, form: DiagramLabelDecoder.Form = .plain) -> [[DiagramLabelSpan]]? {
        DiagramLabelDecoder.label(from: text, form: form).spans
    }

    func testEveryLineBreakTagAndLineBreakEndsALine() {
        XCTAssertEqual(lines("one<br>two<BR/>three<br />four\nfive"), ["one", "two", "three", "four", "five"])
        XCTAssertEqual(lines("a\\nb\\Nc"), ["a", "b", "c"], "A written backslash and n breaks the line, in either case")
    }

    func testOnlyABreakTagWithSpacesBeforeItsSlashEndsALine() {
        // `<br\s*\/?>`: `<br class="x">` is another tag, dropped; `<br/ >` is no tag at all and stays as text.
        XCTAssertEqual(lines("first<br  />second<BR\t/>third<br class=\"x\">fourth<br/ >fifth"), ["first", "second", "thirdfourth<br/ >fifth"])
        XCTAssertEqual(lines("<brand>kept as a tag</brand> word<br"), ["<brand>kept as a tag</brand> word<br"])
    }

    func testOtherTagsAreDroppedAndALessThanSignThatStartsNoTagStays() {
        XCTAssertEqual(lines("<b>bold</b> and <span style=\"x\">styled</span>"), ["bold and styled"])
        XCTAssertEqual(lines("a < b and c<5"), ["a < b and c<5"])
        XCTAssertEqual(lines("List<T> and Map<K, V>"), ["List<T> and Map<K, V>"])
    }

    func testMermaidAndHTMLEntityCodesBecomeTheirCharacters() {
        XCTAssertEqual(lines("#quot;quoted#quot; #9829; #35;"), ["\"quoted\" ♥ #"])
        XCTAssertEqual(lines("&lt;tag&gt; &amp; &copy;"), ["<tag> & ©"])
    }

    func testAnHTMLCodeOfDigitsIsReadAsMermaidsFirst() {
        // Mermaid hides `#65;` in `&#65;` as its own code, which comes back as `&#65;` after the `&`.
        XCTAssertEqual(lines("&#65;&#x42;"), ["&A&&x42;"])
    }

    func testAnUnknownEntityOrOneThatIsNoCharacterStaysAsHTMLsCode() {
        XCTAssertEqual(lines("#unknown; &nothing; #1114112; #0;"), ["&unknown; &nothing; &#1114112; &#0;"])
    }

    func testAnEntityCodeIsDecodedAfterTagsAreDroppedSoItsTextStays() {
        XCTAssertEqual(lines("#lt;b#gt;not bold#lt;/b#gt;"), ["<b>not bold</b>"])
    }

    func testAMarkdownStringsEmphasisBecomesSpansAndUnderscoresBetweenLettersStay() {
        let label = DiagramLabelDecoder.label(from: "**Bold** and *italic* in snake_case\n__strong__ _Markdown_", form: .markdown)
        XCTAssertEqual(label.lines, ["Bold and italic in snake_case", "strong Markdown"])
        XCTAssertEqual(label.spans, [
            [DiagramLabelSpan(text: "Bold", style: .bold), DiagramLabelSpan(text: " and ", style: []), DiagramLabelSpan(text: "italic", style: .italic),
             DiagramLabelSpan(text: " in snake_case", style: [])],
            [DiagramLabelSpan(text: "strong", style: .bold), DiagramLabelSpan(text: " ", style: []), DiagramLabelSpan(text: "Markdown", style: .italic)],
        ])
    }

    func testAMarkerOpensOnlyBeforeTextAndWhenItComesAgain() {
        XCTAssertEqual(spans("a * b * c", form: .markdown), nil)
        XCTAssertEqual(lines("**unclosed bold", form: .markdown), ["**unclosed bold"])
        XCTAssertEqual(spans("2*3*4", form: .markdown), [[DiagramLabelSpan(text: "2", style: []), DiagramLabelSpan(text: "3", style: .italic),
                                                          DiagramLabelSpan(text: "4", style: [])]])
        XCTAssertEqual(spans("***both***", form: .markdown), [[DiagramLabelSpan(text: "both", style: [.bold, .italic])]])
    }

    func testHTMLEmphasisCarriesOverLineBreaksAndNests() {
        XCTAssertEqual(spans("<i>open italic<br>still italic</i> after"), [[DiagramLabelSpan(text: "open italic", style: .italic)],
                                                                           [DiagramLabelSpan(text: "still italic", style: .italic),
                                                                            DiagramLabelSpan(text: " after", style: [])]])
        XCTAssertEqual(spans("<i>it <b>bi</b></i> <code>mono</code>"), [[DiagramLabelSpan(text: "it ", style: .italic),
                                                                          DiagramLabelSpan(text: "bi", style: [.bold, .italic]),
                                                                          DiagramLabelSpan(text: " ", style: []),
                                                                          DiagramLabelSpan(text: "mono", style: .monospaced)]])
    }

    func testAnIconNameIsLeftOutWithTheSpaceAfterIt() {
        XCTAssertEqual(lines("fa:fa-twitter for peace"), ["for peace"])
        XCTAssertEqual(lines("A fa:fa-camera-retro perhaps?"), ["A perhaps?"])
        XCTAssertEqual(lines("x fa:fa-ban"), ["x"], "At the end, the spaces before it go too")
        XCTAssertEqual(lines("fab:fa-truck-bold a custom icon"), ["a custom icon"])
        XCTAssertEqual(lines("sofa:fa-bed here"), ["sohere"])
        XCTAssertEqual(lines("fa:fa-spinner"), [""])
    }

    func testRunsOfSpacesAreKeptAndLinesAreTrimmed() {
        XCTAssertEqual(lines("  wide \t  gap  "), ["wide \t  gap"])
        XCTAssertEqual(lines("  indented\n    more\n  less", form: .markdown), ["indented", "more", "less"])
    }

    func testLiteralTextKeepsItsTagsAndIconsAndStillBreaksAtBreakTags() {
        XCTAssertEqual(lines("<b>kept</b> &amp; <i>as written</i><br/>next  line", form: .literal), ["<b>kept</b> & <i>as written</i>", "next  line"])
        XCTAssertEqual(lines("fa:fa-x stays", form: .literal), ["fa:fa-x stays"])
        XCTAssertEqual(lines("plain", form: .literal), ["plain"])
    }
}
