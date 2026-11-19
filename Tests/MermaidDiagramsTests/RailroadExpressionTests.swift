/**
 * File: RailroadExpressionTests.swift
 * -----------------------------------
 * Layer: Tests
 * Description: How each railroad notation becomes one expression tree, as Pele's model tests state it after Mermaid's
 *              four parsers: collapsing, escapes, postfixes and exceptions, repeats, predicates, titles, comments and
 *              what the grammars refuse.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class RailroadExpressionTests: XCTestCase {
    private typealias Expression = RailroadExpression

    private func t(_ value: String) -> Expression { .terminal(value) }
    private func n(_ name: String) -> Expression { .nonterminal(name) }
    private func s(_ text: String) -> Expression { .special(text) }
    private func sequence(_ elements: Expression...) -> Expression { .sequence(elements) }
    private func choice(_ alternatives: Expression...) -> Expression { .choice(alternatives) }
    private func repeated(_ element: Expression, _ minimum: Double, _ maximum: Double = .infinity) -> Expression {
        .repetition(element, minimum: minimum, maximum: maximum)
    }

    private func model(_ source: String) throws -> RailroadDiagram { try RailroadReading.diagram(source) }
    private func definition(_ keyword: String, _ body: String) throws -> Expression {
        try XCTUnwrap(try model(keyword + "\n" + body).rules.first).definition
    }
    private func constructors(_ expression: String) throws -> Expression { try definition("railroad-beta", "r = \(expression) ;") }
    private func ebnf(_ expression: String) throws -> Expression { try definition("railroad-ebnf-beta", "r = \(expression) ;") }
    private func abnf(_ expression: String) throws -> Expression { try definition("railroad-abnf-beta", "r = \(expression) ;") }
    private func peg(_ expression: String) throws -> Expression { try definition("railroad-peg-beta", "R <- \(expression) ;") }

    func testTheConstructorNotationIsBuiltNodeForNode() throws {
        XCTAssertEqual(try constructors("nonterminal('b')"), n("b"))
        XCTAssertEqual(try constructors("choice(terminal(\"a\"), nonterminal(\"b\"), special(\"c\"))"), choice(t("a"), n("b"), s("c")))
        XCTAssertEqual(try constructors("sequence(choice(sequence(terminal(\"a\"))))"), t("a"))
        XCTAssertEqual(try constructors("optional(choice(terminal(\"a\")))"), .optional(t("a")))
        XCTAssertEqual(try ebnf("( ( a ) )"), n("a"))
        XCTAssertEqual(try abnf("( ( a ) )"), n("a"))
        XCTAssertEqual(try peg("( ( a ) )"), n("a"))
    }

    func testStringsReadThreeEscapesAndKeepAnyOtherEscapedCharacter() throws {
        XCTAssertEqual(try constructors("terminal(\"a\\nb\\tc\\rd\")"), t("a\nb\tc\rd"))
        XCTAssertEqual(try constructors("terminal(\"\\\"\\\\\\x\\0\")"), t("\"\\x0"))
        XCTAssertEqual(try ebnf("'it\\'s'"), t("it's"))
        XCTAssertEqual(try peg("\"\\b\""), t("b"))
        XCTAssertEqual(try abnf("\"a\\\" b"), sequence(t("a\\"), n("b")), "ABNF strings have no escapes")
    }

    func testExtendedBackusNaurFormInBothStyles() throws {
        XCTAssertEqual(try ebnf("a b , c"), sequence(n("a"), n("b"), n("c")))
        XCTAssertEqual(try ebnf("a | \"b\" c"), choice(n("a"), sequence(t("b"), n("c"))))
        XCTAssertEqual(try ebnf("[ a ]"), .optional(n("a")))
        XCTAssertEqual(try ebnf("{ a | b }"), repeated(choice(n("a"), n("b")), 0))
        XCTAssertEqual(try ebnf("a? b* c+"), sequence(.optional(n("a")), repeated(n("b"), 0), repeated(n("c"), 1)))
        XCTAssertEqual(try ebnf("?  any character  ?"), s("any character"))
        XCTAssertEqual(try definition("railroad-ebnf-beta", "r ::= a ;"), n("a"))
    }

    func testPostfixesAndExceptionsApplyLeftToRightToEverythingBeforeThem() throws {
        XCTAssertEqual(try ebnf("a?*+"), repeated(repeated(.optional(n("a")), 0), 1))
        XCTAssertEqual(try ebnf("a - b"), sequence(n("a"), t("-"), n("b")))
        XCTAssertEqual(try ebnf("a - b - \"c\""), sequence(sequence(n("a"), t("-"), n("b")), t("-"), t("c")))
        XCTAssertEqual(try ebnf("a - ( b | c )*"), repeated(sequence(n("a"), t("-"), choice(n("b"), n("c"))), 0))
        XCTAssertEqual(try ebnf("a* - [ b ]"), sequence(repeated(n("a"), 0), t("-"), .optional(n("b"))))
    }

    func testASpecialSequenceStartsAtAnyQuestionMarkThatHasAPartner() throws {
        XCTAssertEqual(try ebnf("a? b?"), sequence(n("a"), s("b")))
        XCTAssertEqual(try model("railroad-ebnf-beta\nr = a? ;\nq = b? ;").rules.map(\.definition), [.optional(n("a")), .optional(n("b"))])
    }

    func testAugmentedBackusNaurFormRepeats() throws {
        XCTAssertEqual(try abnf("*a"), repeated(n("a"), 0))
        XCTAssertEqual(try abnf("1*a"), repeated(n("a"), 1))
        XCTAssertEqual(try abnf("2*4a"), repeated(n("a"), 2, 4))
        XCTAssertEqual(try abnf("*4a"), repeated(n("a"), 0, 4))
        XCTAssertEqual(try abnf("3a"), repeated(n("a"), 3, 3))
        XCTAssertEqual(try abnf("1a"), repeated(n("a"), 1, 1))
        XCTAssertEqual(try abnf("007a"), repeated(n("a"), 7, 7))
        XCTAssertEqual(try abnf("0*1a"), .optional(n("a")))
        XCTAssertEqual(try abnf("*1\"a\""), .optional(t("a")))
        XCTAssertEqual(try abnf("2*( a / b )"), repeated(choice(n("a"), n("b")), 2))
        XCTAssertEqual(try abnf("3[ a ]"), repeated(.optional(n("a")), 3, 3))
        XCTAssertEqual(try abnf(String(repeating: "9", count: 400) + "a"), repeated(n("a"), .infinity, .infinity))
    }

    func testAugmentedBackusNaurFormValuesGroupsAndAlternation() throws {
        XCTAssertEqual(try abnf("%x41 %d65.66 %b1000001 %x30-39"), sequence(t("%x41"), t("%d65.66"), t("%b1000001"), t("%x30-39")))
        XCTAssertEqual(try abnf("a / \"b\" c / [ d ]"), choice(n("a"), sequence(t("b"), n("c")), .optional(n("d"))))
        XCTAssertEqual(try abnf("rule-name DIGIT"), sequence(n("rule-name"), n("DIGIT")))
    }

    func testAnAugmentedRuleEndsOnlyAtASemicolonThatEndsItsLine() throws {
        let rules = try model("railroad-abnf-beta\nr = a ; a comment, so the rule goes on\n  b ;\ns = c ;").rules
        XCTAssertEqual(rules, [RailroadRule(name: "r", definition: sequence(n("a"), n("b"))), RailroadRule(name: "s", definition: n("c"))])
        XCTAssertNotNil(RailroadReading.readError("railroad-abnf-beta\nr = a ; \n"))
    }

    func testParsingExpressionSuffixesAndPredicatesShownAsSpecialText() throws {
        XCTAssertEqual(try peg("a? b* c+"), sequence(.optional(n("a")), repeated(n("b"), 0), repeated(n("c"), 1)))
        XCTAssertEqual(try peg("a / \"b\" c"), choice(n("a"), sequence(t("b"), n("c"))))
        XCTAssertEqual(try peg("&a"), s("&a"))
        XCTAssertEqual(try peg("!\"x\""), s("!\"x\""))
        XCTAssertEqual(try peg("!."), s("!."))
        XCTAssertNotNil(RailroadReading.readError("railroad-peg-beta\nR <- !&a ;"))
        XCTAssertEqual(try peg("!( a b )"), s("!(...)"))
        XCTAssertEqual(try peg("!a*"), s("!(...)"))
        XCTAssertEqual(try peg("&( a )"), s("&a"))
        XCTAssertEqual(try peg("( !a )+"), repeated(s("!a"), 1))
        XCTAssertNotNil(RailroadReading.readError("railroad-peg-beta\nR <- a** ;"))
    }

    func testTitlesAndAccessibilityStatements() throws {
        let quoted = try model("railroad-ebnf-beta\ntitle   \"A \\\"quoted\\\"\\ttitle\"   \naccTitle:   Acc   title\naccDescr: One   line\nr = a ;")
        XCTAssertEqual(quoted.title, "A \"quoted\"\ttitle")
        XCTAssertEqual(quoted.accessibilityTitle, "Acc title")
        XCTAssertEqual(quoted.accessibilityDescription, "One line")
        let braced = try model("railroad-peg-beta\ntitle 'single'\naccDescr {\n   Two\n   lines\n}\nR <- a ;")
        XCTAssertEqual(braced.title, "single")
        XCTAssertEqual(braced.accessibilityDescription, "Two\nlines")
        XCTAssertEqual(try model("railroad-beta title Plain  title %% comment\nr = terminal(\"a\") ;").title, "Plain title")
        XCTAssertEqual(try model("railroad-abnf-beta\ntitle \"a\\tb\"\nr = a ;").title, "a\\tb", "ABNF titles lose their quotes but keep their backslashes")
        XCTAssertEqual(try model("railroad-ebnf-beta\ntitle first\ntitle second\nr = a ;").title, "second")
        XCTAssertNil(try model("railroad-ebnf-beta\nr = a ;").title)
        XCTAssertNil(try model("railroad-ebnf-beta\ntitle first\ntitle\nr = a ;").title, "An empty last title sets none")
    }

    func testItsOwnTitleIsPreferredToTheFrontMatters() throws {
        XCTAssertEqual(try model("---\ntitle: Front\n---\nrailroad-ebnf-beta\nr = a ;").title, "Front")
        XCTAssertEqual(try model("---\ntitle: Front\n---\nrailroad-ebnf-beta\ntitle Own\nr = a ;").title, "Own")
        XCTAssertEqual(try model("---\ntitle: Front\n---\nrailroad-ebnf-beta\ntitle\nr = a ;").title, "Front")
    }

    func testNamesMayStartWithTitleButNoTitleFollowsTheFirstRule() throws {
        let titles = try model("railroad-ebnf-beta\ntitles = a ;")
        XCTAssertNil(titles.title)
        XCTAssertEqual(titles.rules, [RailroadRule(name: "titles", definition: n("a"))])
        XCTAssertNotNil(RailroadReading.readError("railroad-ebnf-beta\nr = a ;\ntitle Late"))
        XCTAssertNotNil(RailroadReading.readError("railroad-ebnf-beta\nr = title ;"))
    }

    func testKeywordsStayOutOfNamesOnlyWhenTheyStandAlone() throws {
        XCTAssertEqual(try model("railroad-beta\nterminals = nonterminal(\"choice\") ;").rules[0], RailroadRule(name: "terminals", definition: n("choice")))
        XCTAssertEqual(RailroadReading.readError("railroad-beta\nterminal = terminal(\"a\") ;"), .invalidSyntax(line: 2, problem: .railroad(.expectedRuleName)))
    }

    func testCommentsAreSkippedInEachNotation() throws {
        XCTAssertEqual(try ebnf("a (* iso *) /* w3c */ b"), sequence(n("a"), n("b")))
        XCTAssertEqual(try constructors("/* c */ terminal(\"a\") /* d */"), t("a"))
        XCTAssertEqual(try peg("a # to the end of the line\n b"), sequence(n("a"), n("b")))
        XCTAssertNotNil(RailroadReading.readError("railroad-ebnf-beta\nr = a (*) b ;"))
        XCTAssertEqual(try definition("railroad-ebnf-beta", "%% a comment line\nr = a ; %% after the rule"), n("a"))
    }

    func testWhatTheGrammarsRefuseIsRefused() {
        let refused = [
            "railroad-ebnf-beta\nr = ;", "railroad-ebnf-beta\nr = a", "railroad-ebnf-beta\nr = ( ) ;", "railroad-ebnf-beta\nr = a | ;",
            "railroad-ebnf-beta\nr = a , ;", "railroad-ebnf-beta\nr = [ a ) ;", "railroad-ebnf-beta\nr = a - ;", "railroad-beta\nr = sequence() ;",
            "railroad-beta\nr = optional(terminal(\"a\"), terminal(\"b\")) ;", "railroad-beta\nr = terminal(a) ;",
            "railroad-beta\nr = terminal(\"unclosed) ;", "railroad-abnf-beta\nr = a /\n ;", "railroad-abnf-beta\nr = 2* ;", "railroad-peg-beta\nR <- ;",
            "railroad-peg-beta\nR = a ;", "railroad-peg-beta\nR <- a ) ;", "railroad-peg-beta\nR <- & ;",
        ]
        for source in refused {
            guard case .invalidSyntax = RailroadReading.readError(source) else { return XCTFail("Refused as a syntax problem: \(source.debugDescription)") }
        }
        XCTAssertEqual(RailroadReading.readError("railroad-ebnf-beta\nr = [ a ) ;"), .invalidSyntax(line: 2, problem: .railroad(.expectedClosing("]"))))
        XCTAssertEqual(RailroadReading.readError("railroad-beta\nr = terminal(a) ;"), .invalidSyntax(line: 2, problem: .railroad(.expectedQuotedText)))
        XCTAssertEqual(RailroadReading.readError("railroad-peg-beta\nR = a ;"), .invalidSyntax(line: 2, problem: .unexpectedText("= a ;")),
                       "A PEG has no token for `=`")
        XCTAssertEqual(RailroadReading.readError("railroad-ebnf-beta\nR <- a ;"), .invalidSyntax(line: 2, problem: .unexpectedText("<- a ;")))
        XCTAssertEqual(RailroadReading.readError("railroad-ebnf-beta\nR a ;"), .invalidSyntax(line: 2, problem: .railroad(.expectedDefinitionSign)))
    }

    func testOptionsAreReadFromTheFrontMatter() throws {
        let diagram = try model("---\nconfig:\n  railroad:\n    arcRadius: 4\n    showMarkers: false\n    fontSize: 12\n---\nrailroad-ebnf-beta\nr = a ;")
        XCTAssertEqual(diagram.options.arcRadius, 4)
        XCTAssertEqual(diagram.options.fontSize, 12)
        XCTAssertFalse(diagram.options.showsMarkers)
        XCTAssertNil(diagram.options.padding)
    }
}
