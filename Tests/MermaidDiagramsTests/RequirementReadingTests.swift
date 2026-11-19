/**
 * File: RequirementReadingTests.swift
 * -----------------------------------
 * Layer: Tests
 * Description: The requirement diagram reader's quirks as Mermaid's lexer and Pele's parser have them, its typed errors
 *              with their lines, and its limits.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class RequirementReadingTests: XCTestCase {
    private func assertProblem(_ source: String, line: Int, _ problem: MermaidSyntaxProblem, file: StaticString = #filePath, lineNumber: UInt = #line) {
        XCTAssertThrowsError(try RequirementParserTests.read(source), file: file, line: lineNumber) { error in
            XCTAssertEqual(error as? MermaidDiagramReadError, .invalidSyntax(line: line, problem: problem), source, file: file, line: lineNumber)
        }
    }

    func testEachSyntaxErrorNamesWhatWasExpectedAndItsLine() {
        assertProblem("requirement\nrequirement a {\n}", line: 1, .requirement(.expectedKeyword))
        assertProblem("requirementDiagram x\n", line: 1, .requirement(.expectedLineBreak))
        assertProblem("requirementDiagram\nrequirement a {\nfoo: 1\n}", line: 3, .requirement(.expectedRequirementField))
        assertProblem("requirementDiagram\nelement a {\nid: 1\n}", line: 3, .requirement(.expectedElementField))
        assertProblem("requirementDiagram\nrequirement a {\nrisk: extreme\n}", line: 3, .requirement(.expectedRisk))
        assertProblem("requirementDiagram\nrequirement a {\nverifymethod: guess\n}", line: 3, .requirement(.expectedVerificationMethod))
        assertProblem("requirementDiagram\nrequirement a {\nid 1\n}", line: 3, .requirement(.expectedColon))
        assertProblem("requirementDiagram\nrequirement a\n}", line: 2, .requirement(.expectedOpeningBrace))
        assertProblem("requirementDiagram\na - likes -> b\n", line: 2, .requirement(.expectedRelationKind))
        assertProblem("requirementDiagram\na - contains - b\n", line: 2, .requirement(.expectedArrow))
        assertProblem("requirementDiagram\na b\n", line: 2, .requirement(.expectedNameStatement))
        assertProblem("requirementDiagram\ntitle My title\n", line: 2, .requirement(.expectedStatement))
        assertProblem("requirementDiagram\nstyle a \"x\"\n", line: 2, .requirement(.expectedStyle))
        assertProblem("requirementDiagram\nclass\n", line: 3, .requirement(.expectedNameList))
        assertProblem("requirementDiagram\na > b\n", line: 2, .unexpectedText("> b"))
    }

    /// Mermaid's lexer reads whitespace before a line break as whitespace, line break included: spaces after the keyword
    /// break the grammar. A style statement ends at its line break without a token, and Pele ends every text with a line
    /// break, so one on the last line is read as one on any other.
    func testWhitespaceAndStyleStatementsAsMermaidsLexerReadsThem() throws {
        assertProblem("requirementDiagram \nrequirement a {\n}", line: 2, .requirement(.expectedLineBreak))
        XCTAssertEqual(try RequirementParserTests.read("requirementDiagram\nrequirement a {\n}\nstyle a fill:red").requirements.first?.styleDeclarations,
                       ["fill:red"])
        XCTAssertNoThrow(try RequirementParserTests.read("requirementDiagram\nrequirement a {\n}\nstyle a fill:red\n"))
        XCTAssertEqual(try RequirementParserTests.read("requirementDiagram\nrequirement a {\n}\nstyle a color: red\n").requirements.first?.styleDeclarations,
                       ["color:red"])
    }

    /// Pele makes every `\r\n` and lone `\r` a line break before it reads a diagram: a lone `\r` ends a line, and the lines
    /// of an error count it.
    func testCarriageReturnsBreakLinesAsPeleMakesThem() throws {
        let diagram = try RequirementParserTests.read("requirementDiagram\r\nrequirement a {\rid: 1\r\n}\relement b {\r}\r")
        XCTAssertEqual(diagram.requirements.first?.identifier, "1")
        XCTAssertEqual(diagram.elements.map(\.name), ["b"])
        assertProblem("requirementDiagram\rrequirement a \r{\r}", line: 2, .requirement(.expectedOpeningBrace))
        assertProblem("requirementDiagram\rrequirement a {\rid:\r1\r}", line: 3, .requirement(.expectedName))
    }

    /// Mermaid drops the last semicolon of a `style` or `classDef` line that holds a color (`text.replace(/style.*:\S*#.*;/g)`),
    /// and Pele hides an entity code (`#name;`) from its lexer, where no rule reads it at a token's start: it is no color
    /// in a style statement, and no comment.
    func testColorSemicolonsAndEntityCodesAsPeleReadsThem() throws {
        let diagram = try RequirementParserTests.read("""
            requirementDiagram
            element e {
            }
            style e fill:#f9f;
            classDef c fill:#000,color:#fff;
            style e stroke:#3;33
            """)
        XCTAssertEqual(diagram.elements.first?.styleDeclarations, ["fill:#f9f", "stroke:#333"])
        XCTAssertEqual(diagram.styleClasses.first?.styleDeclarations, ["fill:#000", "color:#fff"])
        assertProblem("requirementDiagram\nclassDef c fill:#000;color:#fff;\n", line: 2, .unexpectedText("#000;color:#fff"))
        assertProblem("requirementDiagram\nelement e {\n}\nstyle e fill:#f9f,stroke:#333;str:#333;stroke-width:4px\n", line: 4, .unexpectedText("#333;str:#333stroke-widt"))
        assertProblem("requirementDiagram\n#amp; element e {\n}\n", line: 2, .unexpectedText("#amp; element e {"))
        XCTAssertEqual(try RequirementParserTests.read("requirementDiagram\nelement e {\ntype: a #amp; b\n}\n").elements.first?.type, "a #amp; b")
    }

    /// Pele takes out a line that holds only a comment, with the blank lines before it, before its lexer looks for a
    /// direction anywhere on a line; an error after it still names its line as written.
    func testACommentLineIsTakenOutBeforeDirectionsAreFound() throws {
        XCTAssertEqual(try RequirementParserTests.read("requirementDiagram\n%% direction LR\nelement e {\n}\n").direction, .topToBottom)
        XCTAssertEqual(try RequirementParserTests.read("requirementDiagram\n%%{init: {}}%% direction LR\n").direction, .leftToRight)
        assertProblem("requirementDiagram\n\n  %% a comment\n%% another\nrequirement a\n}", line: 5, .requirement(.expectedOpeningBrace))
    }

    /// A line that holds `direction` and a direction anywhere is one direction token, as Mermaid's rule `.*direction\s+LR[^\n]*` reads it.
    func testADirectionAnywhereOnALineIsTheWholeLine() throws {
        let diagram = try RequirementParserTests.read("requirementDiagram\nrequirement a {\n}\nanything direction LR then more\nelement b {\n}\n")
        XCTAssertEqual(diagram.direction, .leftToRight)
        XCTAssertEqual(diagram.elements.map(\.name), ["b"])
        XCTAssertEqual(try RequirementParserTests.read("requirementdiagram\nDIRECTION rl\n").direction, .rightToLeft)
    }

    func testNamesKeywordsAndRepeatedDeclarations() throws {
        let diagram = try RequirementParserTests.read("""
            requirementDiagram
            Requirement "a b" {
            id: 1
            id: 2
            }
            requirement "a b" {
            id: 3
            }
            ELEMENT  foo bar  {
            Type: "kind, of"
            }
            "a b" - contains -> foo bar
            """)
        XCTAssertEqual(diagram.requirements.map(\.name), ["a b"])
        XCTAssertEqual(diagram.requirements.first?.identifier, "1", "the first of two repeated fields, and the first declaration, win")
        XCTAssertEqual(diagram.elements.first?.name, "foo bar")
        XCTAssertEqual(diagram.elements.first?.type, "kind, of")
        XCTAssertEqual(diagram.relations, [RequirementDiagramRelation(kind: .contains, source: "a b", target: "foo bar")])
    }

    /// Mermaid stops a `style` at the first name that is no node; `class` passes over it.
    func testAStyleStopsAtTheFirstUnknownName() throws {
        let diagram = try RequirementParserTests.read("requirementDiagram\nrequirement a {\n}\nelement b {\n}\nstyle x,a fill:red\nclass x,b c\n")
        XCTAssertEqual(diagram.requirements.first?.styleDeclarations, [])
        XCTAssertEqual(diagram.elements.first?.classNames, ["default", "c"])
    }

    func testCountsPastTheLimitsAreRefusedBeforeTheyAreMade() throws {
        var limits = MermaidDiagramLimits.standard
        limits.maximumNodeCount = 2
        limits.maximumEdgeCount = 2
        XCTAssertThrowsError(try RequirementParserTests.read("requirementDiagram\nrequirement a {\n}\nelement b {\n}\nelement c {\n}\n", limits: limits)) { error in
            XCTAssertEqual(error as? MermaidDiagramReadError, .tooManyNodes(limit: 2))
        }
        XCTAssertThrowsError(try RequirementParserTests.read("requirementDiagram\na - copies -> b\na - copies -> b\na - copies -> b\n", limits: limits)) { error in
            XCTAssertEqual(error as? MermaidDiagramReadError, .tooManyEdges(limit: 2))
        }
        var builder = RequirementDiagramBuilder(limits: .standard)
        try builder.addRequirement(named: "a", kind: .requirement)
        try builder.defineClasses(names: ["c"], declarations: Array(repeating: "a:b", count: 1_000))
        for _ in 0..<999 { try builder.setClasses(names: ["a"], classNames: ["c"]) }
        XCTAssertThrowsError(try builder.setClasses(names: ["a"], classNames: ["c"])) { error in
            XCTAssertEqual(error as? RequirementDiagramBuilder.Refusal, .tooManyStyleCopies)
        }
    }

    /// Mermaid's `requirementDb` spec: classes keep the declarations that set a color for text, and a class given before it
    /// is defined copies its declarations when it is.
    func testTheDatabaseSpecsClassesAndStyles() throws {
        var builder = RequirementDiagramBuilder(limits: .standard)
        try builder.addRequirement(named: "requirement", kind: .requirement)
        try builder.addElement(named: "element")
        try builder.setStyle(names: ["requirement"], declarations: ["color:red"])
        try builder.setStyle(names: ["element"], declarations: ["stroke-width:4px", "stroke: yellow"])
        try builder.defineClasses(names: ["myClass"], declarations: ["fill:#f9f,color:red"])
        XCTAssertEqual(builder.diagram.requirements.first?.styleDeclarations, ["color:red"])
        XCTAssertEqual(builder.diagram.elements.first?.styleDeclarations, ["stroke-width:4px", "stroke: yellow"])
        XCTAssertEqual(builder.diagram.styleClasses.first?.textStyleDeclarations, ["bgFill:#f9f,color:red"])
        try builder.setClasses(names: ["requirement", "element"], classNames: ["myClass"])
        XCTAssertEqual(builder.diagram.requirements.first?.styleDeclarations, ["color:red", "fill:#f9f,color:red"])
        XCTAssertEqual(builder.diagram.elements.first?.classNames, ["default", "myClass"])
    }
}
