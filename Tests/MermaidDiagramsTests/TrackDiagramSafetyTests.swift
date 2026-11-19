/**
 * File: TrackDiagramSafetyTests.swift
 * -----------------------------------
 * Layer: Tests
 * Description: Pele's worst cases for event models and railroad diagrams are read and laid out, or refused with a typed
 *              error, quickly and without a crash; railroad nesting is bounded on a secondary thread's stack.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class TrackDiagramSafetyTests: XCTestCase {
    private static var typography: DiagramTypography { DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16)) }
    private static let size = 50_000

    private static func repeated(_ count: Int, _ part: (Int) -> String) -> String {
        (0..<count).map(part).joined()
    }

    /// Reads and lays out `source` (across and down a column, or regular and tight), or takes its typed error; true
    /// when it was laid out.
    @discardableResult
    private static func outcome(of source: String, typography: DiagramTypography = typography) -> Bool {
        let diagram: MermaidDiagram
        do { diagram = try MermaidDiagramReader.read(source, limits: .standard) } catch { return false }
        switch diagram {
        case .eventModel(let model):
            _ = EventModelLayoutEngine.layout(model, typography: typography)
            _ = EventModelLayoutEngine.layout(model, typography: typography, columnWidth: 280)
        case .railroad(let railroad):
            _ = RailroadLayoutEngine.layout(railroad, typography: typography)
            _ = RailroadLayoutEngine.layout(railroad, typography: typography, columnWidth: 280)
        default: return false
        }
        return true
    }

    private func assertQuick(_ cases: [(String, String)], seconds: Double) {
        let typography = Self.typography
        for (name, source) in cases {
            let start = Date()
            Self.outcome(of: source, typography: typography)
            XCTAssertLessThan(Date().timeIntervalSince(start), seconds, name)
        }
    }

    /// Pele's event model worst cases (`tests/eventmodeling/stress.test.ts`), each within two seconds.
    func testPelesEventModelWorstCasesAreQuick() {
        let head = "eventmodeling\n"
        let size = Self.size
        func number(_ index: Int) -> String { String(format: "%03d", index % 1_000) }
        let kinds = ["ui", "cmd", "evt", "rmo", "pcr"]
        assertQuick([
            ("1,000 frames across the lanes", head + Self.repeated(1_000) { index in "tf \(number(index)) \(kinds[index % 5]) E\(index)\n" }),
            ("1,000 frames in one lane", head + Self.repeated(1_000) { index in "tf \(number(index)) evt E\(index)\n" }),
            ("1,000 frames in 1,000 namespaces", head + Self.repeated(1_000) { index in "tf \(number(index)) evt N\(index).E\n" }),
            ("1,000 frames that each name earlier frames", head + Self.repeated(1_000) { index in
                "tf \(number(index)) evt E\(index)" + Self.repeated(min(index, 9)) { back in " ->> \(number(index - back - 1))" } + "\n"
            }),
            ("one frame with 9,000 sources", head + "tf 001 cmd A\ntf 002 evt B" + String(repeating: " ->> 001", count: 5_000) + "\n"),
            ("a frame number reused", head + String(repeating: "tf 01 evt A\n", count: 4_000)),
            ("500 data blocks, each referenced", head + Self.repeated(500) { index in "tf \(number(index)) evt E\(index) [[D\(index)]]\n" }
                + Self.repeated(300) { index in "data D\(index) {\n  a: \(index)\n}\n" }),
            ("one data block of 10,000 lines", head + "tf 01 evt A [[D]]\ndata D {\n" + String(repeating: "a: 1\n", count: 9_000) + "}\n"),
            ("one data line of 50,000 characters", head + "tf 01 evt A { " + String(repeating: "x", count: size - 40) + " }\n"),
            ("inline data of 25,000 braces", head + "tf 01 evt A " + String(repeating: "{", count: size / 2 - 20) + String(repeating: "}", count: size / 2 - 20) + "\n"),
            ("1,000 notes and specifications", head + "tf 01 evt A\n" + Self.repeated(700) { index in "note 01 {\n n\(index)\n}\ngwt 01 given evt A then evt B\n" }),
            ("a specification of 5,000 statements", head + "tf 01 evt A\ngwt 01 given" + String(repeating: " evt A", count: 4_000) + " then evt B\n"),
            ("a qualified name of 10,000 parts", head + "tf 01 evt " + String(repeating: "a.", count: 10_000) + "z\n"),
            ("one 50,000 character name", head + "tf 01 evt " + String(repeating: "a", count: size - 40) + "\n"),
            ("unclosed braces, one per line", head + String(repeating: "tf 01 evt A {\n", count: size / 14 - 2)),
            ("an open brace and closing braces that end no block", head + "data D {\n" + String(repeating: "}x\n", count: size / 3 - 10)),
            ("lines of opening braces", head + String(repeating: String(repeating: "{", count: 99) + "\n", count: size / 100 - 1)),
            ("one line of quotes", head + "tf 01 evt A " + String(repeating: "\"", count: size - 40)),
            ("unclosed block comment", head + "/*" + String(repeating: " x\n", count: size / 3 - 10)),
            ("many block comment openers", head + String(repeating: "/* ", count: size / 3 - 10)),
            ("unclosed accDescr after every frame", head + String(repeating: "tf 01 evt A accDescr {\n", count: size / 23 - 1)),
            ("accDescr after long blanks", head + String(repeating: "x" + String(repeating: " ", count: 90) + "accDescr ", count: size / 100 - 1)),
            ("unclosed directive openers", head + String(repeating: "x %%{\n", count: size / 6 - 3)),
            ("unclosed front matter fences", head + String(repeating: "x\n---\n", count: size / 6 - 3)),
            ("digits", head + "tf " + String(repeating: "1", count: size - 20)),
            ("keywords run together", head + String(repeating: "tfevtuidatanote", count: size / 15 - 1)),
        ], seconds: 2)
    }

    /// Pele's railroad worst cases (`tests/railroad/stress.test.ts`), each within three seconds.
    func testPelesRailroadWorstCasesAreQuick() {
        let size = Self.size
        let constructors = "railroad-beta\n", extended = "railroad-ebnf-beta\n", augmented = "railroad-abnf-beta\n", expressions = "railroad-peg-beta\n"
        assertQuick([
            ("special sequence opener before a long run", extended + "r = ?" + String(repeating: " a", count: size / 2 - 20)),
            ("question marks separated by blanks", extended + "r = " + String(repeating: "?  ", count: size / 3 - 10)),
            ("unclosed ISO comment openers", extended + "r = " + String(repeating: "(* a ", count: size / 5 - 5)),
            ("ISO comment openers without a closer", extended + "r = " + String(repeating: "(*)", count: size / 3 - 10)),
            ("unclosed block comment openers", constructors + String(repeating: "/* a ", count: size / 5 - 5)),
            ("comments opened and closed", extended + String(repeating: "/**/(**)", count: size / 8 - 5)),
            ("braced descriptions never closed", extended + String(repeating: "accDescr { ", count: size / 11 - 2)),
            ("one-line descriptions", constructors + String(repeating: "accDescr: " + String(repeating: "% ", count: 45) + "\n", count: size / 101 - 1)),
            ("one long title", constructors + "title " + String(repeating: "a % ", count: size / 4 - 5)),
            ("unclosed double quote", constructors + "r = terminal(\"" + String(repeating: "a\\\"", count: size / 3 - 10)),
            ("unclosed ABNF string", augmented + "r = \"" + String(repeating: "a ", count: size / 2 - 20)),
            ("front matter fences that do not close", extended + "r = a " + String(repeating: "---\n", count: size / 4 - 10)),
            ("directive openers that do not close", constructors + String(repeating: "%%{ a ", count: size / 6 - 5)),
            ("dashes", extended + "r = a " + String(repeating: "-", count: size - 30)),
            ("digits with no star", augmented + "r = " + String(repeating: "1", count: size - 40) + "a ;"),
            ("numeric values with long tails", augmented + "r = %x" + String(repeating: "41.", count: size / 3 - 10) + " ;"),
            ("semicolon comments", augmented + String(repeating: "; a comment\n", count: size / 12 - 2)),
            ("keywords glued into one name", constructors + String(repeating: "terminal", count: size / 8 - 3)),
            ("one 25,000 character name", extended + String(repeating: "a", count: size / 2 - 20) + " = " + String(repeating: "b", count: size / 2 - 20) + " ;"),
            ("one long terminal", extended + "r = \"" + String(repeating: "word ", count: size / 5 - 10) + "\" ;"),
            ("terminal of entity codes and markup", extended + "r = \"" + String(repeating: "#35;&amp;<br>*_", count: size / 15 - 5) + "\" ;"),
            ("25,000 nested groups", extended + "r = " + String(repeating: "(", count: size / 2 - 20) + "a" + String(repeating: ")", count: size / 2 - 20) + " ;"),
            ("postfix operators", extended + "r = a" + String(repeating: "*+?", count: 1_600) + " ;"),
            ("unclosed brackets", extended + "r = " + String(repeating: "([{", count: size / 3 - 10)),
            ("choice of 4,000 alternatives", extended + "r = " + Self.repeated(4_000) { index in "a\(index) | " } + "z ;"),
            ("sequence of 4,000 elements", extended + "r = " + String(repeating: "a ", count: 4_000) + ";"),
            ("2,000 rules", extended + Self.repeated(2_000) { index in "r\(index) = a ;\n" }),
            ("unclosed constructor calls", constructors + "r = " + String(repeating: "choice(", count: size / 7 - 5)),
            ("ABNF alternation of 4,000", augmented + "r = " + String(repeating: "a / ", count: 4_000) + "b ;"),
            ("PEG run of operators", expressions + "R <- " + String(repeating: "!&", count: size / 2 - 20) + "a ;"),
            ("PEG sequence of predicates", expressions + "R <- " + String(repeating: "!a &\"b\" ", count: 2_000) + ";"),
        ], seconds: 3)
    }

    /// Railroad expressions nested past 64 levels, by brackets or by postfixes, exceptions and repeats, are refused, and 63
    /// levels are read and laid out, on a thread
    /// with the 512 KiB stack of the threads a reader builds on.
    func testRailroadNestingIsBoundedOnASecondaryThreadsStack() {
        let finished = expectation(description: "the nesting was read")
        let thread = Thread {
            for (opening, closing) in [("(", ")"), ("[", "]"), ("{", "}")] {
                let deep = "railroad-ebnf-beta\nr = " + String(repeating: opening, count: 10_000) + "a" + String(repeating: closing, count: 10_000) + " ;"
                XCTAssertEqual(RailroadReading.readError(deep), .nestingTooDeep(limit: RailroadExpression.maximumNestingDepth))
            }
            let constructors = "railroad-beta\nr = " + String(repeating: "optional(oneOrMore(", count: 2_000) + "terminal(\"a\")" + String(repeating: "))", count: 2_000) + " ;"
            XCTAssertEqual(RailroadReading.readError(constructors), .nestingTooDeep(limit: RailroadExpression.maximumNestingDepth))
            let peg = "railroad-peg-beta\nR <- " + String(repeating: "( ", count: 5_000) + "a" + String(repeating: " )*", count: 5_000) + " ;"
            XCTAssertEqual(RailroadReading.readError(peg), .nestingTooDeep(limit: RailroadExpression.maximumNestingDepth))
            // A tree deepened without brackets: postfixes, exceptions, repeats.
            // (`?*+?` would be a special sequence.)
            for chain in ["railroad-ebnf-beta\nr = a" + String(repeating: "*+", count: 2_000) + " ;",
                          "railroad-ebnf-beta\nr = a" + String(repeating: " - b", count: 12_000) + " ;",
                          "railroad-abnf-beta\nr = " + String(repeating: "2*3( ", count: 5_000) + "a" + String(repeating: " )", count: 5_000) + " ;"] {
                XCTAssertEqual(RailroadReading.readError(chain), .nestingTooDeep(limit: RailroadExpression.maximumNestingDepth))
            }
            // Each bracket an option around a sequence: two levels each, the innermost name one more, 63 in all.
            let deepest = "railroad-ebnf-beta\nr = " + String(repeating: "[ a ", count: 31) + "b" + String(repeating: " ]", count: 31) + " ;"
            XCTAssertTrue(Self.outcome(of: deepest), "Sixty-three levels are read and laid out")
            let tooDeep = "railroad-ebnf-beta\nr = " + String(repeating: "[ a ", count: 32) + "b" + String(repeating: " ]", count: 32) + " ;"
            XCTAssertEqual(RailroadReading.readError(tooDeep), .nestingTooDeep(limit: RailroadExpression.maximumNestingDepth))
            finished.fulfill()
        }
        thread.stackSize = 512 * 1024
        thread.start()
        wait(for: [finished], timeout: 120)
    }

    func testCountsPastTheLimitsAreRefused() {
        var limits = MermaidDiagramLimits.standard
        limits.maximumNodeCount = 10
        XCTAssertEqual(RailroadReading.readError("railroad-ebnf-beta\nr = a b c d e f g h i j k ;", limits: limits), .tooManyNodes(limit: 10))
        XCTAssertEqual(RailroadReading.readError("railroad-ebnf-beta\n" + String(repeating: "r = a ;\n", count: 6), limits: limits), .tooManyNodes(limit: 10))
        XCTAssertNoThrow(try RailroadReading.diagram("railroad-ebnf-beta\nr = a b c d ;", limits: limits))
    }
}
