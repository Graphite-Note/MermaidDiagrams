/**
 * File: FlowchartPeleGrammarTests.swift
 * -------------------------------------
 * Layer: Tests
 * Description: A flowchart's identifiers, node texts, `&` groups, link identifiers and group headers read as Pele's
 *              lexer and parser read them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class FlowchartPeleGrammarTests: XCTestCase {
    private func identifiers(_ source: String) throws -> [String] {
        try FlowchartReading.flowchart(source).nodes.map(\.identifier)
    }

    /// flow-singlenode.spec.js: Pele's `idString` runs over every token an identifier takes, keywords inside a node
    /// string included.
    func testAnIdentifierRunsOverPeriodsHyphensSlashesAndKeywordsInside() throws {
        XCTAssertEqual(try identifiers("graph TD;a.graph.node;node-end;default.node;default/node;href.node;click-node;"),
                       ["a.graph.node", "node-end", "default.node", "default/node", "href.node", "click-node"])
    }

    /// `#`, `:`, `&`, `,`, `*`, `.`, `\`, `-` and `/` alone, or at either end of a word, are identifiers.
    func testSpecialCharactersAloneOrAtEitherEndAreIdentifiers() throws {
        for written in ["#", ":", "&", ",", "*", ".", "\\", "-", "/", "#node", ":node", "node&", "node,", "node-", "node/"] {
            XCTAssertEqual(try identifiers("graph TD; \(written) --> A"), [written, "A"], written)
        }
    }

    /// `A&B` is one identifier (`&` is a node string's character); `A & B` names two nodes; the `&` needs a space on
    /// either side, as Pele's `node` reads it, so `A &B` is refused.
    func testAnAmpersandGroupsNodesOnlyBetweenSpaces() throws {
        XCTAssertEqual(try identifiers("graph TD\nA&B --> C"), ["A&B", "C"])
        XCTAssertEqual(try FlowchartReading.flowchart("graph TD\nA & B --> C").edges.count, 2)
        XCTAssertNotNil(FlowchartReading.readError("graph TD\nA &B --> C"))
        XCTAssertNotNil(FlowchartReading.readError("graph TD\nA[x]&B --> C"))
    }

    /// flow-text.spec.js: `odd->Vertex Text]` is node `odd-` drawn as an odd shape: `-` before `>` is a token of its own.
    func testAHyphenBeforeAnOddShapeEndsTheIdentifier() throws {
        let diagram = try FlowchartReading.flowchart("graph TD;A_node-->odd->Vertex Text];")
        XCTAssertEqual(diagram.nodes.map(\.identifier), ["A_node", "odd-"])
        XCTAssertEqual(diagram.nodes[1].shape, .asymmetric)
    }

    /// A character that is neither ASCII nor one of the lexer's letters is no token Pele reads.
    func testALetterBeyondASCIIIsPartOfAnIdentifierAndAnEmojiIsRefused() throws {
        XCTAssertEqual(try identifiers("graph TD\nÉtape_2 --> 東京"), ["Étape_2", "東京"])
        XCTAssertNotNil(FlowchartReading.readError("graph TD\nA🙂 --> B"))
    }

    /// flow-edges.spec.js: a link's identifier may follow a space, and runs to the last `@` of its word.
    func testALinksIdentifierFollowsASpace() throws {
        let diagram = try FlowchartReading.flowchart("flowchart LR\nA id1@-->B")
        XCTAssertEqual(diagram.nodes.map(\.identifier), ["A", "B"])
        XCTAssertEqual(diagram.edges.count, 1)
    }

    /// flow-text.spec.js: Pele's text state ends plain text at a bracket, a parenthesis, a brace, a bar or a quotation
    /// mark, so these are refused, as Mermaid's specs expect.
    func testBracketsAndQuotationMarksInsidePlainTextAreRefused() {
        for source in ["graph TD; A[This is a () in text];", "graph TD; A[This is a \"()\" in text];", "graph TD; node[hello ) world] --> works",
                       "graph TD;A(this node has \"string\" and text)-->|this link has \"string\" and text|C;", "graph TD;A-->|a (b)|B",
                       "graph TD;A[a | b]", "graph TD;A[]", "graph TD;A[\"\"]", "graph TD;A[ \"a\"]"] {
            XCTAssertNotNil(FlowchartReading.readError(source), source)
        }
    }

    /// A string may be followed by plain text, which Pele's `text` appends to it; a string holds any bracket.
    func testAStringHoldsBracketsAndPlainTextMayFollowIt() throws {
        let diagram = try FlowchartReading.flowchart("graph TD;A[\"a (b)\" c]-->|\"[x]\"|B[/a/b\\]")
        XCTAssertEqual(diagram.nodes[0].label, DiagramLabel("a (b) c"))
        XCTAssertEqual(diagram.edges[0].label, DiagramLabel("[x]"))
        XCTAssertEqual(diagram.nodes[1].label, DiagramLabel("a/b"))
        XCTAssertEqual(diagram.nodes[1].shape, .trapezoid)
    }

    /// subgraph.spec.js: a header with spaces before the line's end names no group (`subGraph0`), as Pele's
    /// `addSubGraph` reads its text with them.
    func testAGroupHeaderEndingInSpacesIsATitleWithoutAnIdentifier() throws {
        let diagram = try FlowchartReading.flowchart("graph TD\nA-->B\nsubgraph myTitle   \n\n    c-->d \nend\n")
        XCTAssertEqual(diagram.subgraphs.map(\.title), [DiagramLabel("myTitle")])
        XCTAssertNotEqual(diagram.subgraphs.first?.identifier, "myTitle")
    }

    /// A node written without text is labelled with its identifier as Pele lays its text out: `\n` written in it
    /// breaks the line.
    func testANodesIdentifierIsLaidOutAsItsText() throws {
        XCTAssertEqual(try FlowchartReading.flowchart("graph TD; \\node --> A").nodes[0].label.lines, ["", "ode"])
    }
}
