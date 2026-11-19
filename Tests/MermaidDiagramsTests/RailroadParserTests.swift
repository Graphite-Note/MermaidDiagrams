/**
 * File: RailroadParserTests.swift
 * -------------------------------
 * Layer: Tests
 * Description: Railroad diagrams are read in their four notations as Mermaid's parsers read them: the inputs of
 *              Mermaid's railroad specs as Pele ports them, and Pele's own tests of how each notation becomes one tree.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

/// Reads a railroad diagram for a test through `MermaidDiagramReader`.
enum RailroadReading {
    static func diagram(_ source: String, limits: MermaidDiagramLimits = .standard) throws(MermaidDiagramReadError) -> RailroadDiagram {
        guard case .railroad(let diagram) = try MermaidDiagramReader.read(source, limits: limits) else { throw .noDiagram }
        return diagram
    }

    static func readError(_ source: String, limits: MermaidDiagramLimits = .standard) -> MermaidDiagramReadError? {
        do {
            _ = try diagram(source, limits: limits)
            return nil
        } catch {
            return error
        }
    }
}

final class RailroadParserTests: XCTestCase {
    private typealias Expression = RailroadExpression

    private func t(_ value: String) -> Expression { .terminal(value) }
    private func n(_ name: String) -> Expression { .nonterminal(name) }
    private func s(_ text: String) -> Expression { .special(text) }
    private func repeated(_ element: Expression, _ minimum: Double, _ maximum: Double = .infinity) -> Expression {
        .repetition(element, minimum: minimum, maximum: maximum)
    }

    private func definition(_ keyword: String, _ body: String) throws -> Expression {
        try XCTUnwrap(try RailroadReading.diagram(keyword + "\n" + body).rules.first).definition
    }

    private func constructors(_ expression: String) throws -> Expression { try definition("railroad-beta", "r = \(expression) ;") }
    private func ebnf(_ expression: String) throws -> Expression { try definition("railroad-ebnf-beta", "r = \(expression) ;") }
    private func abnf(_ expression: String) throws -> Expression { try definition("railroad-abnf-beta", "r = \(expression) ;") }
    private func peg(_ expression: String) throws -> Expression { try definition("railroad-peg-beta", "R <- \(expression) ;") }

    // MARK: The detectors' specs

    func testTheFourKeywordsAreDetectedWithoutRegardToCaseAndOnlyTheLowerCaseOnesRead() throws {
        for keyword in ["railroad-beta", "railroad-ebnf-beta", "railroad-abnf-beta", "railroad-peg-beta"] {
            let body = keyword == "railroad-beta" ? "rule = terminal(\"test\") ;" : keyword == "railroad-peg-beta" ? "rule <- \"test\" ;" : "rule = \"test\" ;"
            for written in [keyword, "  " + keyword, "\n\n" + keyword] {
                XCTAssertEqual(try RailroadReading.diagram(written + "\n" + body).notation.keyword, keyword, written)
            }
            for written in [keyword.uppercased(), keyword.capitalized] {
                XCTAssertEqual(RailroadReading.readError(written + "\n" + body), .invalidSyntax(line: 1, problem: .railroad(.expectedKeyword(written))),
                               "Detected as a railroad diagram, then refused by its grammar")
            }
        }
        XCTAssertEqual(RailroadNotation(typeKeyword: "Railroad-EBNF-Beta"), .extendedBackusNaurForm)
        XCTAssertNil(RailroadNotation(typeKeyword: "flowchart"))
        XCTAssertEqual(RailroadReading.readError("railroad-beta-x\nr = terminal(\"a\") ;"),
                       .invalidSyntax(line: 1, problem: .railroad(.expectedKeyword("railroad-beta-x"))))
        XCTAssertEqual(RailroadReading.readError("rule = \"test\" ;"), .unsupportedDiagramType(keyword: "rule"))
        XCTAssertEqual(RailroadReading.readError("   \n  \t  "), .noDiagram)
    }

    // MARK: railroadDb.spec.ts

    func testRulesAreKeptInOrderAndANameDefinedTwiceRefersToTheLaterOne() throws {
        let diagram = try RailroadReading.diagram("railroad-beta\ntest = terminal(\"first\") ;\ntest = terminal(\"second\") ;")
        XCTAssertEqual(diagram.rules.count, 2)
        XCTAssertEqual(diagram.rule(named: "test"), RailroadRule(name: "test", definition: t("second")))
        XCTAssertNil(diagram.rule(named: "nonexistent"))
    }

    // MARK: railroadDiagram.spec.ts

    func testTheConstructorNotationSpecIsRead() throws {
        XCTAssertEqual(try definition("\n        railroad-beta", "        rule = terminal(\"hello\") ;\n      "), t("hello"))
        XCTAssertEqual(try constructors("nonterminal(\"expression\")"), n("expression"))
        XCTAssertEqual(try constructors("sequence(terminal(\"a\"), terminal(\"b\"), terminal(\"c\"))"), .sequence([t("a"), t("b"), t("c")]))
        XCTAssertEqual(try constructors("sequence(terminal(\"a\"))"), t("a"))
        XCTAssertEqual(try constructors("choice(terminal(\"a\"), terminal(\"b\"), terminal(\"c\"))"), .choice([t("a"), t("b"), t("c")]))
        XCTAssertEqual(try constructors("choice(terminal(\"a\"))"), t("a"))
        XCTAssertEqual(try constructors("optional(terminal(\"a\"))"), .optional(t("a")))
        XCTAssertEqual(try constructors("zeroOrMore(terminal(\"a\"))"), repeated(t("a"), 0))
        XCTAssertEqual(try constructors("oneOrMore(terminal(\"a\"))"), repeated(t("a"), 1))
        XCTAssertEqual(try constructors("special(\"any character\")"), s("any character"))
        XCTAssertEqual(try RailroadReading.diagram("\n  railroad-beta\n  title \"Test Grammar\"\n  rule = terminal(\"a\") ;\n").title, "Test Grammar")
        XCTAssertEqual(try constructors("sequence(\n choice(terminal(\"a\"), terminal(\"b\")),\n oneOrMore(choice(terminal(\"c\"), terminal(\"d\")))\n)"),
                       .sequence([.choice([t("a"), t("b")]), repeated(.choice([t("c"), t("d")]), 1)]))
        XCTAssertEqual(try constructors("zeroOrMore(choice(terminal(\"a\"), terminal(\"b\")))"), repeated(.choice([t("a"), t("b")]), 0))
        XCTAssertEqual(try constructors("terminal(\"hello world\")"), t("hello world"))
        XCTAssertEqual(try RailroadReading.diagram("railroad-beta\nmy_rule = terminal(\"test\") ;\nrule123 = terminal(\"test\") ;").rules.map(\.name),
                       ["my_rule", "rule123"])
        XCTAssertEqual(try definition("railroad-beta", "/* this is a comment */\nrule = terminal(\"a\") ;"), t("a"))
    }

    func testTheSpecsRealWorldGrammarsAreRead() throws {
        let expression = try RailroadReading.diagram("""
        railroad-beta
        title "Simple Expression"
        expression = sequence(nonterminal("term"), zeroOrMore(sequence(choice(terminal("+"), terminal("-")), nonterminal("term")))) ;
        term = sequence(nonterminal("factor"), zeroOrMore(sequence(choice(terminal("*"), terminal("/")), nonterminal("factor")))) ;
        factor = choice(nonterminal("number"), sequence(terminal("("), nonterminal("expression"), terminal(")"))) ;
        number = oneOrMore(nonterminal("digit")) ;
        digit = choice(terminal("0"), terminal("1"), terminal("2"), terminal("3"), terminal("4"), terminal("5"), terminal("6"), terminal("7"), terminal("8"), terminal("9")) ;
        """)
        XCTAssertEqual(expression.title, "Simple Expression")
        XCTAssertEqual(expression.rules.map(\.name), ["expression", "term", "factor", "number", "digit"])
        let json = try RailroadReading.diagram("""
        railroad-beta
        title "JSON Subset"
        value = choice(nonterminal("string"), nonterminal("number"), terminal("true"), terminal("false"), terminal("null")) ;
        string = sequence(terminal("\\""), zeroOrMore(nonterminal("character")), terminal("\\"")) ;
        number = oneOrMore(nonterminal("digit")) ;
        character = choice(nonterminal("letter"), nonterminal("digit")) ;
        letter = choice(terminal("a"), terminal("b"), terminal("c")) ;
        digit = choice(terminal("0"), terminal("1"), terminal("2")) ;
        """)
        XCTAssertEqual(json.rules.count, 6)
        XCTAssertEqual(json.rules[1].definition, .sequence([t("\""), repeated(n("character"), 0), t("\"")]))
    }

    func testTheSpecsErrorsAreRefused() {
        XCTAssertNotNil(RailroadReading.readError("\n        railroad-beta\n        rule = terminal(\"a\")\n      "))
        XCTAssertNotNil(RailroadReading.readError("\n        railroad-beta\n        rule = terminal(\"unclosed) ;\n      "))
        XCTAssertEqual(RailroadReading.readError("railroad-beta\nrule = terminal(\"a\")"), .invalidSyntax(line: 2, problem: .railroad(.expectedSemicolon)))
        XCTAssertEqual(try RailroadReading.diagram("\n  railroad-beta\n  title \"Empty Grammar\"\n").rules, [])
        XCTAssertTrue(try MermaidDiagramReader.read("railroad-beta\ntitle \"Empty Grammar\"", limits: .standard).hasNothingToDraw)
    }

    // MARK: railroad.test.ts

    func testTheParserTestsTitleAccessibilityAndComments() throws {
        let diagram = try RailroadReading.diagram("railroad-beta\ntitle Example Grammar\naccTitle: Accessible Railroad\naccDescr: Railroad description\nrule = terminal(\"a\") ;")
        XCTAssertEqual(diagram.title, "Example Grammar")
        XCTAssertEqual(diagram.accessibilityTitle, "Accessible Railroad")
        XCTAssertEqual(diagram.accessibilityDescription, "Railroad description")
        let commented = try RailroadReading.diagram("railroad-beta\n/* comment before the first rule */\nrule = terminal(\"a\") ;\nnext = nonterminal(\"rule\") ;")
        XCTAssertEqual(commented.rules.map(\.name), ["rule", "next"])
    }

    /// Pele reads the text with its line breaks made `\n` first, so a description in braces written with Windows' line
    /// breaks is the same as one written with `\n`.
    func testADescriptionInBracesReadsWindowsLineBreaksAsLineBreaks() throws {
        for lineBreak in ["\n", "\r\n", "\r"] {
            let source = ["railroad-beta", "accDescr {", "  line  one", "", "  line two", "}", "r = terminal(\"a\") ;"].joined(separator: lineBreak)
            XCTAssertEqual(try RailroadReading.diagram(source).accessibilityDescription, "line one\nline two", lineBreak.debugDescription)
        }
    }

    /// Mermaid removes its comment lines (`%%` and text, with the blank lines before them) from the text before its
    /// railroad parsers read it, so one inside a string or a description in braces is not part of it; an error is still
    /// on the line it is written on.
    func testCommentLinesAreRemovedEvenInsideStringsAndDescriptions() throws {
        let diagram = try RailroadReading.diagram("""
        railroad-beta
        accDescr {
          first
          %% not described
          second
        }
        r = terminal("a

          %% not matched
        b") ;
        s = terminal("%%{kept}") ;
        t = terminal("c
        %%
        d") ;
        """)
        XCTAssertEqual(diagram.accessibilityDescription, "first\nsecond")
        XCTAssertEqual(diagram.rules.map(\.definition), [t("a\nb"), t("%%{kept}"), t("c\n%%\nd")])
        XCTAssertEqual(RailroadReading.readError("railroad-beta\n%% one\n\n  %% two\nr = terminal(\"a\") ;\n%% three\ns = x ;"),
                       .invalidSyntax(line: 7, problem: .railroad(.expectedExpression)))
        XCTAssertEqual(RailroadReading.readError("railroad-beta\r\nr = terminal(\"a\r\n%% c\r\nb\") ;\r\ns = x ;"),
                       .invalidSyntax(line: 5, problem: .railroad(.expectedExpression)))
    }

    /// A string, or a special sequence, written over two lines holds the `\n` Pele reads there, whether the text was
    /// written with `\n` or Windows' `\r\n`; an escaped `\r` stays a carriage return.
    func testALineBreakInsideAStringIsReadAsALineFeed() throws {
        for lineBreak in ["\n", "\r\n"] {
            let lines = ["%% a comment", "railroad-ebnf-beta", "r = \"a", "b\" \"c\\r\" ? x", "y ? ;", "s = ) ;"]
            let source = lines.joined(separator: lineBreak)
            let diagram = try RailroadReading.diagram(lines.dropLast().joined(separator: lineBreak))
            XCTAssertEqual(diagram.rules.first?.definition, .sequence([t("a\nb"), t("c\r"), s("x\ny")]), lineBreak.debugDescription)
            XCTAssertEqual(RailroadReading.readError(source), .invalidSyntax(line: 6, problem: .railroad(.expectedExpression)), lineBreak.debugDescription)
        }
    }

    // MARK: ebnfDiagram.spec.ts, abnfDiagram.spec.ts, pegDiagram.spec.ts

    func testTheNotationSpecsAreRead() throws {
        XCTAssertEqual(try ebnf("\"terminal\""), t("terminal"))
        XCTAssertEqual(try ebnf("other_rule"), n("other_rule"))
        XCTAssertEqual(try ebnf("\"a\" \"b\" \"c\""), .sequence([t("a"), t("b"), t("c")]))
        XCTAssertEqual(try ebnf("\"a\" | \"b\" | \"c\""), .choice([t("a"), t("b"), t("c")]))
        XCTAssertEqual(try ebnf("\"a\"?"), .optional(t("a")))
        XCTAssertEqual(try ebnf("[ \"a\" ]"), .optional(t("a")))
        XCTAssertEqual(try ebnf("\"a\"*"), repeated(t("a"), 0))
        XCTAssertEqual(try ebnf("\"a\"+"), repeated(t("a"), 1))
        XCTAssertEqual(try ebnf("{ \"a\" }"), repeated(t("a"), 0))
        XCTAssertEqual(try ebnf("? special ?"), s("special"))
        XCTAssertEqual(try abnf("\"hello\""), t("hello"))
        XCTAssertEqual(try abnf("%x41"), t("%x41"))
        XCTAssertEqual(try abnf("other-rule"), n("other-rule"))
        XCTAssertEqual(try abnf("\"a\" \"b\" \"c\""), .sequence([t("a"), t("b"), t("c")]))
        XCTAssertEqual(try abnf("\"a\" / \"b\" / \"c\""), .choice([t("a"), t("b"), t("c")]))
        XCTAssertEqual(try abnf("[ \"a\" ]"), .optional(t("a")))
        XCTAssertEqual(try abnf("*\"a\""), repeated(t("a"), 0))
        XCTAssertEqual(try abnf("1*\"a\""), repeated(t("a"), 1))
        XCTAssertEqual(try peg("\"hello\""), t("hello"))
        XCTAssertEqual(try peg("other_rule"), n("other_rule"))
        XCTAssertEqual(try peg("\"a\" \"b\" \"c\""), .sequence([t("a"), t("b"), t("c")]))
        XCTAssertEqual(try peg("\"a\" / \"b\" / \"c\""), .choice([t("a"), t("b"), t("c")]))
        XCTAssertEqual(try peg("\"a\"?"), .optional(t("a")))
        XCTAssertEqual(try peg("\"a\"*"), repeated(t("a"), 0))
        XCTAssertEqual(try peg("\"a\"+"), repeated(t("a"), 1))
        XCTAssertEqual(try peg("."), s("."))
        XCTAssertEqual(try peg("&\"a\""), s("&\"a\""))
        XCTAssertEqual(try peg("!\"a\""), s("!\"a\""))
        for keyword in ["railroad-ebnf-beta", "railroad-abnf-beta", "railroad-peg-beta"] {
            XCTAssertEqual(try RailroadReading.diagram("\n  \(keyword)\n  title \"Test Grammar\"\n  r\(keyword.contains("peg") ? " <-" : " =") \"a\" ;").title,
                           "Test Grammar")
            XCTAssertEqual(RailroadReading.readError("\(keyword)\nrule\(keyword.contains("peg") ? " <-" : " =") \"a\""),
                           .invalidSyntax(line: 2, problem: .railroad(.expectedSemicolon)))
        }
    }

    func testTheNotationSpecsRealWorldGrammarsAreRead() throws {
        let expression = try RailroadReading.diagram("""
        railroad-ebnf-beta
        title "Simple Expression"
        expression = term ( "+" term | "-" term )* ;
        term = factor ( "*" factor | "/" factor )* ;
        factor = number | "(" expression ")" ;
        number = digit+ ;
        digit = "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" ;
        """)
        XCTAssertEqual(expression.rules.count, 5)
        let uri = try RailroadReading.diagram("""
        railroad-abnf-beta
        title "URI"
        URI = scheme ":" hier-part ;
        scheme = ALPHA *( ALPHA / DIGIT / "+" / "-" / "." ) ;
        hier-part = "//" authority path-abempty ;
        """)
        XCTAssertEqual(uri.rules.map(\.name), ["URI", "scheme", "hier-part"])
        let calculator = try RailroadReading.diagram("""
        railroad-peg-beta
        title "Calculator"
        Expression <- Term (("+" / "-") Term)* ;
        Term <- Factor (("*" / "/") Factor)* ;
        Factor <- Number / "(" Expression ")" ;
        Number <- Digit+ ;
        Digit <- "0" / "1" / "2" / "3" / "4" / "5" / "6" / "7" / "8" / "9" ;
        """)
        XCTAssertEqual(calculator.title, "Calculator")
        XCTAssertEqual(calculator.rules.first?.name, "Expression")
    }
}
