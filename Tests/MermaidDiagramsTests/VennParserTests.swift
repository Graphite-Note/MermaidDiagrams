/**
 * File: VennParserTests.swift
 * ---------------------------
 * Layer: Tests
 * Description: The inputs of Mermaid 12.1.0's Venn parser spec (venn.spec.ts, as Pele ports it in tests/compat/venn),
 *              the seeds of Pele's differential test of its lexer and parser, and the errors with their lines.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class VennParserTests: XCTestCase {
    private func venn(_ source: String) throws -> VennDiagram {
        try VennReading.venn(source)
    }

    private func subsets(_ diagram: VennDiagram) -> [[String]] {
        diagram.subsets.map(\.sets)
    }

    // MARK: Mermaid's parser spec

    func testSimple() throws {
        let diagram = try venn("venn-beta\n      title foo bar\n      set A\n      set B\n      union A,B\n  ")
        XCTAssertEqual(diagram.title, "foo bar")
        XCTAssertEqual(diagram.subsets, [VennSubset(sets: ["A"], size: 10, label: nil), VennSubset(sets: ["B"], size: 10, label: nil),
                                         VennSubset(sets: ["A", "B"], size: 2.5, label: nil)])
    }

    func testBracketLabelsQuotedOrNot() throws {
        for source in ["venn-beta\n  set A[\"Alpha\"]\n  set B[\"Beta\"]\n  union A,B[\"AB\"]\n", "venn-beta\n  set A[Alpha]\n  set B[Beta]\n  union A,B[AB]\n"] {
            let diagram = try venn(source)
            XCTAssertEqual(diagram.subsets.map(\.label), ["Alpha", "Beta", "AB"], source)
            XCTAssertEqual(diagram.subsets.map(\.size), [10, 10, 2.5], source)
        }
    }

    func testSizesAfterAColon() throws {
        XCTAssertEqual(try venn("venn-beta\n  set A:20\n  set B:12\n  union A,B:3\n").subsets.map(\.size), [20, 12, 3])
        let labelled = try venn("venn-beta\n  title foo bar\n  set A[\"Alpha\"]:20\n  set B[\"Beta\"]:12\n  set C[\"Gamma\"]:30\n"
                                + "  union A,B[\"AB\"]:5.3\n  union C,A,B:1\n")
        XCTAssertEqual(subsets(labelled), [["A"], ["B"], ["C"], ["A", "B"], ["A", "B", "C"]])
        XCTAssertEqual(labelled.subsets.map(\.size), [20, 12, 30, 5.3, 1])
        XCTAssertEqual(labelled.subsets.map(\.label), ["Alpha", "Beta", "Gamma", "AB", nil])
    }

    func testTextsWithBracketLabelsAndIndentedTextsWithout() throws {
        let labelled = try venn("venn-beta\n  set A\n    text A1[\"foo bar\"]\n  set B\n    text B1[\"hello, world\"]\n  union A,B\n    text AB1[\"shared note\"]\n")
        XCTAssertEqual(labelled.texts, [VennText(sets: ["A"], identifier: "A1", label: "foo bar"), VennText(sets: ["B"], identifier: "B1", label: "hello, world"),
                                        VennText(sets: ["A", "B"], identifier: "AB1", label: "shared note")])
        let plain = try venn("venn-beta\n  set A[\"Frontend\"]\n    text A1\n    text A2\n  set B[\"Backend\"]\n    text B1\n  union A,B[\"APIs\"]\n")
        XCTAssertEqual(plain.texts, [VennText(sets: ["A"], identifier: "A1", label: nil), VennText(sets: ["A"], identifier: "A2", label: nil),
                                     VennText(sets: ["B"], identifier: "B1", label: nil)])
    }

    func testStylesOfASetAnOverlapAndAText() throws {
        func styles(_ source: String) throws -> [VennStyle] { try venn(source).styles }
        XCTAssertEqual(try styles("venn-beta\n  set A\n  set B\n  union A,B\n  style A fill:#ff6b6b\n"),
                       [VennStyle(targets: ["A"], declarations: [VennStyleDeclaration(property: "fill", value: "#ff6b6b")])])
        XCTAssertEqual(try styles("venn-beta\n  set A\n  set B\n  union A,B\n  style A,B color:#333\n"),
                       [VennStyle(targets: ["A", "B"], declarations: [VennStyleDeclaration(property: "color", value: "#333")])])
        XCTAssertEqual(try styles("venn-beta\n  set A\n    text A1[\"React\"]\n  style A1 color:red\n"),
                       [VennStyle(targets: ["A1"], declarations: [VennStyleDeclaration(property: "color", value: "red")])])
        XCTAssertEqual(try styles("venn-beta\n  set A\n  set B\n  union A,B\n  style A fill:#ff6b6b, color:#333\n"),
                       [VennStyle(targets: ["A"], declarations: [VennStyleDeclaration(property: "fill", value: "#ff6b6b"),
                                                                 VennStyleDeclaration(property: "color", value: "#333")])])
        XCTAssertEqual(try styles("venn-beta\n  set A\n  set B\n  style A fill:rgb(255, 0, 128)\n  style B fill:rgba(255, 0, 128, 0.5)\n").map(\.declarations),
                       [[VennStyleDeclaration(property: "fill", value: "rgb(255, 0, 128)")], [VennStyleDeclaration(property: "fill", value: "rgba(255, 0, 128, 0.5)")]])
    }

    func testIndentModeWithStyles() throws {
        let diagram = try venn("venn-beta\n  set A[\"Frontend\"]:20\n    text A1[\"React\"]\n  set B[\"Backend\"]:12\n  union A,B[\"Shared\"]:3\n"
                               + "    text AB1[\"OpenAPI\"]\n  style A fill:#ff6b6b\n  style A,B color:#333\n  style A1 color:red\n")
        XCTAssertEqual(diagram.subsets.map(\.label), ["Frontend", "Backend", "Shared"])
        XCTAssertEqual(diagram.texts.map(\.sets), [["A"], ["A", "B"]])
        XCTAssertEqual(diagram.styles.map(\.targets), [["A"], ["A", "B"], ["A1"]])
    }

    func testASetTakesOneIdentifierAndAUnionTwoKnownOnes() {
        XCTAssertNotNil(VennReading.readError("venn-beta\n    set A,B\n"))
        XCTAssertEqual(VennReading.readError("venn-beta\n    union A\n"), .invalidSyntax(line: 2, problem: .venn(.unionOfOneSet)))
        XCTAssertEqual(VennReading.readError("venn-beta\n    set Foo\n    union Foo,Buz\n"), .invalidSyntax(line: 3, problem: .venn(.unknownSetIdentifiers(["Buz"]))))
    }

    func testQuotedIdentifiersAreSortedWithoutTheirQuotes() throws {
        XCTAssertEqual(subsets(try venn("venn-beta\n    set \"Foo Bar\"\n    set Buz\n    union \"Foo Bar\",Buz\n")), [["Foo Bar"], ["Buz"], ["Buz", "Foo Bar"]])
    }

    // MARK: The seeds of Pele's differential test, every one of which Mermaid's grammar accepts

    func testPelesSeedsRead() throws {
        let seeds = [
            "venn-beta\nset A\nset B\nunion A,B\n",
            "venn-beta\n  set A[\"Alpha\"]:20\n    text A1[\"React\"]\n    text A2\n    text \"q\"\n    text 5\n  set B[Beta]:12\n  union A,B[\"AB\"]:3\n"
                + "    text AB1[\"OpenAPI\"]\n  style A fill:#ff6b6b\n  style A,B color:#333\n  style A1 color:red\n",
            "venn-beta\ntitle A title\nset A\n  text x\nset B set C\nunion A,B,C[all]:1.5 union A,C\ntext A,B t1[\"one\"]\ntext C \"two\"\ntext A 3\n",
            "\n\n  venn-beta\n%% comment\n  set A %% trailing\n  set B\n\n   \n  union A,B\n    text T[\"x\"]\n\n    text U\ntext A V\n",
            "venn-beta\nset A\nstyle A fill:rgb(255, 0, 128), color:rgba(1,2,3,0.5), stroke:\"dashed red\", stroke-width:2 px, x:#fff 5 a\n",
            "venn-beta\nset \"Foo Bar\"\nset Buz\nunion \"Foo Bar\",Buz\n  text \"a note\"[\"with label\"]\n",
            "venn-beta\r\nset A\r\n  text x\r\nset B\r\n",
            "venn-beta\nset A\n  text a\n  text b\nunion A,A\n  text c\ntitle last one\n",
        ]
        for seed in seeds { XCTAssertNoThrow(try venn(seed), seed) }
        let third = try venn(seeds[2])
        XCTAssertEqual(subsets(third), [["A"], ["B"], ["C"], ["A", "B", "C"], ["A", "C"]])
        XCTAssertEqual(third.texts.map(\.identifier), ["x", "t1", "two", "3"])
        XCTAssertEqual(third.texts.map(\.sets), [["A"], ["A", "B"], ["C"], ["A"]])
        let commented = try venn(seeds[3])
        XCTAssertEqual(commented.texts.map(\.identifier), ["T", "U", "V"], "A blank line keeps the indented texts under their union")
        XCTAssertEqual(commented.texts.map(\.sets), [["A", "B"], ["A", "B"], ["A"]])
        let styled = try venn(seeds[4]).styles[0].declarations
        XCTAssertEqual(styled.map(\.value), ["rgb(255, 0, 128)", "rgba(1,2,3,0.5)", "dashed red", "2 px", "#fff 5 a"])
        XCTAssertEqual(try venn(seeds[5]).texts, [VennText(sets: ["Buz", "Foo Bar"], identifier: "a note", label: "with label")])
        XCTAssertEqual(try venn(seeds[6]).texts.map(\.sets), [["A"]])
        let repeated = try venn(seeds[7])
        XCTAssertEqual(repeated.subsets.last, VennSubset(sets: ["A", "A"], size: 2.5, label: nil))
        XCTAssertEqual(repeated.title, "last one")
    }

    func testKeywordsInAnyCaseAndATitleWithNothingAfterIt() throws {
        let shouting = try venn("venn-beta\nSET A\nSet B:5\nUNION A,B\n  TEXT t\nSTYLE A FILL:Red\nTITLE Shout\n")
        XCTAssertEqual(subsets(shouting), [["A"], ["B"], ["A", "B"]])
        XCTAssertEqual(shouting.texts.map(\.identifier), ["t"])
        XCTAssertEqual(shouting.styles.first?.declarations, [VennStyleDeclaration(property: "FILL", value: "Red")])
        XCTAssertEqual(shouting.title, "Shout")
        let bare = try venn("venn-beta\nset A\ntitle\n  text kept\n")
        XCTAssertEqual(bare.texts.map(\.sets), [["A"]], "A bare title is skipped like a comment, so it does not end indented text")
        XCTAssertEqual(try venn("venn-beta\n  title \"Team overlap\"\n  set A").title, "Team overlap")
        XCTAssertEqual(try venn("---\ntitle: From front matter\n---\nvenn-beta\n  set A").title, "From front matter")
    }

    /// Pele's lexer takes JavaScript's white space (`isSpace`) after `title` and inside a color, and ends a title only at
    /// a line feed, `#` or `;`, and its `trim` takes the same white space off a bare title and a bracket label.
    func testWhiteSpaceAsJavaScriptSeesIt() throws {
        XCTAssertEqual(try venn("venn-beta\ntitle\u{00A0}Hello\nset A").title, "Hello")
        XCTAssertEqual(try venn("venn-beta\ntitle\u{3000}Wide space\nset A").title, "Wide space")
        XCTAssertEqual(try venn("venn-beta\nset A\nstyle A fill:rgb(1,\u{00A0}2, 3)").styles.first?.declarations.first?.value, "rgb(1,\u{00A0}2, 3)")
        let returned = try venn("venn-beta\ntitle A\rset B")
        XCTAssertEqual(returned.title, "A\rset B", "A carriage return alone does not end the title")
        XCTAssertTrue(returned.subsets.isEmpty)
        XCTAssertEqual(try venn("venn-beta\nset A\ntitle\u{00A0}\n  text kept\n").texts.map(\.sets), [["A"]])
        XCTAssertEqual(try venn("venn-beta\nset A[\u{00A0}Alpha\u{2003}]").subsets[0].label, "Alpha")
    }

    func testSizesAsJavaScriptsParseFloatReadsThem() throws {
        XCTAssertEqual(try venn("venn-beta\nset A:+.5\nset B:-5\nset C:1.5").subsets.map(\.size), [0.5, -5, 1.5])
        XCTAssertEqual(try venn("venn-beta\nset A:" + String(repeating: "9", count: 400)).subsets[0].size, .infinity)
    }

    func testErrorsSayWhatBrokeOnWhichLine() {
        XCTAssertEqual(VennReading.readError("venn-beta\n  set A\n  set é"), .invalidSyntax(line: 3, problem: .unexpectedText("é")))
        XCTAssertEqual(VennReading.readError("venn-beta\n  set A:x"), .invalidSyntax(line: 2, problem: .venn(.expectedSize)))
        XCTAssertEqual(VennReading.readError("venn-beta\n  text 5"), .invalidSyntax(line: 2, problem: .venn(.expectedIdentifier)))
        XCTAssertEqual(VennReading.readError("venn-beta\n  text A"), .invalidSyntax(line: 2, problem: .venn(.expectedTextIdentifier)))
        XCTAssertEqual(VennReading.readError("venn-beta\n  style A fill"), .invalidSyntax(line: 2, problem: .venn(.expectedStyleDeclaration)))
        XCTAssertEqual(VennReading.readError("venn-beta\n  A"), .invalidSyntax(line: 2, problem: .venn(.expectedStatement)))
        XCTAssertEqual(VennReading.readError("venn-beta\n  set A[\"unclosed"), .invalidSyntax(line: 2, problem: .unexpectedText("[\"unclosed")))
        XCTAssertEqual(VennReading.readError("venn-beta\n  set venn-beta"), .invalidSyntax(line: 2, problem: .venn(.expectedIdentifier)))
    }

    func testCountsAreBoundedByTheLimits() {
        var limits = MermaidDiagramLimits.standard
        limits.maximumNodeCount = 3
        limits.maximumEdgeCount = 4
        XCTAssertEqual(VennReading.readError("venn-beta\nset A\nset B\nset C\nset D", limits: limits), .tooManyNodes(limit: 3))
        XCTAssertEqual(VennReading.readError("venn-beta\nset A\nset B\nunion A,B\nunion A,B,A", limits: limits), .tooManyEdges(limit: 4))
    }
}
