/**
 * File: UserJourneyReadingEquivalenceTests.swift
 * ----------------------------------------------
 * Layer: Tests
 * Description: The user journey reader gives, to the last field, the diagram 0.7.0's reader gave (ReferenceUserJourneyParser),
 *              its actors interned as the model works them out from its tasks, or the same error, on every corpus, the
 *              specification's texts, thousands of texts mutated from them and random statements; hostile texts stay bounded.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class UserJourneyReadingEquivalenceTests: XCTestCase {
    private static let keywords: Set<String> = ["journey"]

    private func agree(_ source: String, limits: MermaidDiagramLimits = .standard) -> Bool? {
        ChartReadingEquivalence.agree(source, keywords: Self.keywords, read: { (cursor, _) throws(MermaidDiagramReadError) in
            try UserJourneyParser.parse(cursor, limits: limits)
        }, reference: { (cursor, _) throws(MermaidDiagramReadError) in
            try ReferenceUserJourneyParser.parse(cursor, limits: limits)
        })
    }

    private func assertAgree(_ sources: [String], atLeast count: Int, file: StaticString = #filePath, line: UInt = #line) {
        var compared = 0
        for source in sources {
            guard let agrees = agree(source) else { continue }
            XCTAssertTrue(agrees, "\(source.prefix(300))", file: file, line: line)
            compared += 1
        }
        XCTAssertGreaterThanOrEqual(compared, count, file: file, line: line)
    }

    func testEveryCorpusIsReadAsZeroSevenReadIt() throws {
        assertAgree(try ChartReadingEquivalence.corpusSources(keywords: Self.keywords) + Self.specificationTexts, atLeast: Self.specificationTexts.count)
    }

    func testMutatedTextsAreReadAsZeroSevenReadThem() throws {
        var mutations = ChartTextMutations(seed: 0x10_0E1_2A)
        let sources = try ChartReadingEquivalence.corpusSources(keywords: Self.keywords) + Self.specificationTexts
        var mutated: [String] = []
        for source in sources {
            for _ in 0..<150 { mutated.append(mutations.mutated(source)) }
            for _ in 0..<150 { mutated.append(mutations.spliced(source)) }
        }
        assertAgree(mutated, atLeast: 5_000)
    }

    func testRandomStatementsAreReadAsZeroSevenReadThem() {
        var random = UserJourneyRandomStatements(seed: 0x5EED_10E1)
        let seed = random.seed
        var compared = 0
        for index in 0..<3_000 {
            let source = random.text(statementCount: 1 + index % 25)
            guard let agrees = agree(source) else { continue }
            XCTAssertTrue(agrees, "seed \(seed): \(source)")
            compared += 1
        }
        XCTAssertEqual(compared, 3_000)
    }

    /// The node and edge limits refuse at the same statement as 0.7.0's reader refused.
    func testLimitsRefuseWhereZeroSevenRefused() {
        let limits = MermaidDiagramLimits(maximumSourceBytes: 50_000, maximumNodeCount: 6, maximumEdgeCount: 5, maximumLayoutPointCount: 50)
        let sources = [
            "journey\nsection A\n" + String(repeating: "t: 5: Me\n", count: 8),
            "journey\nt: 1: a, b, c\nu: 2: d, e, f\n",
            "journey\nt: 1: a, b, c, d, e\nu: 2:\n",
            "journey\nt: 1: é, b, c\nu: 2: d, e, f\n",
        ]
        for source in sources { XCTAssertEqual(agree(source, limits: limits), true, source) }
    }

    /// Hostile texts are read or refused in time that grows with their length, as 0.7.0 read them, and many actors who
    /// share most of their name stay one table entry each.
    func testHostileTextsAgreeAndStayBounded() {
        let manyActors = (0..<4_900).map { index in "actor\(index)" }.joined(separator: ",")
        let cases = [
            "journey\n" + String(repeating: "t: 5: Me, Cat, , Dog\n", count: 1_200),
            "journey\nt: 5: " + manyActors + "\n",
            "journey\n" + (0..<4_000).map { index in "t\(index): \(index % 7): a\(index % 900), b\(index)" }.joined(separator: "\n"),
            "journey\nsection " + String(repeating: "x", count: 40_000) + "\nt: 1: Me\n",
            "journey\nt: " + String(repeating: "9", count: 30_000) + ": Me\n",
            "journey\nt: 1: " + String(repeating: "é ,", count: 4_000) + "\n",
            "journey\n" + String(repeating: "t: 1:::::\n", count: 3_000),
        ]
        for source in cases {
            let started = Date()
            XCTAssertEqual(agree(source), true, String(source.prefix(80)))
            XCTAssertLessThan(Date().timeIntervalSince(started), 5, String(source.prefix(80)))
        }
    }

    /// Scores as JavaScript's `Number` reads them, read on the bytes where they are whole numbers of at most fifteen
    /// digits, and the actors' names interned and sorted by their UTF-16 code units.
    func testScoresAndActorsAreReadAsTheModelWorksThemOut() throws {
        let source = "journey\na: 7: Zoë, Ana\nb:  010 :Ana,,Zoë, ana\nc: 999999999999999: x\nd: 9999999999999999: x\ne: 0x1F: x\nf: -3: x\n"
            + "g:   : x\nh: 2.5e1: x\ni: Infinity\nj: 5\u{3000}: x\nk: \u{FEFF}5: x\n"
        guard case .userJourney(let diagram) = try MermaidDiagramReader.read(source, limits: .standard) else { return XCTFail("not a journey") }
        XCTAssertEqual(diagram.tasks.map(\.score), [7, 10, 999_999_999_999_999, 10_000_000_000_000_000, 31, -3, 0, 25, .infinity, 5, 5])
        XCTAssertEqual(diagram.actorNames, ["Ana", "Zoë", "ana", "x"])
        XCTAssertEqual(Array(diagram.actorIndices(ofTask: 1)), [0, -1, 1, 2])
        XCTAssertEqual(diagram, UserJourneyDiagram(title: diagram.title, sections: diagram.sections, tasks: diagram.tasks))
    }

    /// Mermaid's user journey documentation and the grammar's corners.
    static let specificationTexts = [
        "journey\n  title My working day\n  section Go to work\n    Make tea: 5: Me\n    Go upstairs: 3: Me\n    Do work: 1: Me, Cat\n  section Go home\n    Go downstairs: 5: Me\n    Sit down: 5: Me\n",
        "journey\ntitle\nNext line title\nsection\nNext line section\nTask: 3: A\n",
        "journey\n  accTitle: The title\n  accDescr: The description\n  t: 1: Me\n",
        "journey\n  accDescr {\n    long\n    description\n  }\n  t: 2: Me\n",
        "journey\n  %% a comment\n  t: 3: Me # a comment\n  u: 4: Me; v: 5: You\n",
        "journey\r\n  t: 3: Me\r\n  u: 4: You\r\n",
        "journey\n  t: x: Me\n  u: : Me\n  v: 5:\n  w: 5: , ,\n",
        "journey\n  t: 5: Me: extra: more\n",
        "journey\n  t<br>two lines: 5: Me\n  &amp; entity: 4: Me\n  <b>tag</b>: 3: Me\n",
        "journey\n  section A\n  t: 1: Me\n  section A\n  u: 2: Me\n  section B\n  section A\n  v: 3: Me\n",
        "journey\n  t: 5: Me\u{301}, Cat\n  u: 4:\u{301} Me\n  v: 3: \u{00A0}Me\u{00A0}, \u{2028}Cat\n",
        "journey\n  t: 0b101: Me\n  u: 0o17: Me\n  v: .5: Me\n  w: 5.: Me\n  x: 1e400: Me\n  y: +2: Me\n",
        "journey\n  : 5: Me\n",
        "journey\n  t 5 Me\n",
        "journey\n  journey\n",
        "journey\n  title  \n  t: 1: Me\n",
        "---\ntitle: Front matter\n---\njourney\n  t: 1: Me\n",
        "journey\n  t: 5: Me\t,\u{0B}Cat\u{0C}, \u{85}Dog\n",
    ]
}

/// Random user journey statements from a seeded generator: titles, sections, accessibility text, comments and tasks with
/// scores of every form JavaScript reads and actors of every spacing, some of them nameless, beyond ASCII or broken.
struct UserJourneyRandomStatements {
    private(set) var seed: UInt64
    private var state: UInt64

    init(seed: UInt64) {
        self.seed = seed
        state = seed
    }

    private mutating func next(below bound: Int) -> Int {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return Int(state % UInt64(max(bound, 1)))
    }

    private mutating func pick(_ choices: [String]) -> String { choices[next(below: choices.count)] }

    private static let scores = ["5", "1", "3", " 4 ", "05", "0", "x", "", " ", "2.5", "-1", "+3", "0x1F", "0b11", "0o7", "1e1", ".5", "5.", "Infinity",
                                 "-Infinity", "999999999999999", "1234567890123456", "\u{3000}4", "4\u{A0}", "1_0", "١"]
    private static let names = ["Me", "Cat", "me", "Zoë", "", " ", "Ana Lee", "\tDad", "Mum ", "é", "e\u{301}", "\u{3000}Kim", "Bo\u{301}", "x#y", "a&amp;b", "A1", "A2", "A3", "A4", "A5", "A6", "A7", "A8", "A9"]

    private mutating func actors() -> String {
        (0..<next(below: 5)).map { _ in
            let spacing = pick(["", " ", "  ", "\t", "\u{0B}"])
            return spacing + pick(Self.names) + pick(["", " ", "\u{0C}"])
        }.joined(separator: ",")
    }

    private mutating func statement() -> String {
        switch next(below: 12) {
        case 0: return "title " + pick(["My day", "  spaced  ", "é", ""])
        case 1: return "section " + pick(["Go to work", "Go home", "A", "A", "é", "a<br>b"])
        case 2: return "accTitle: " + pick(["t", "é"])
        case 3: return "accDescr: d"
        case 4: return "%% comment"
        case 5: return pick(["t", "Task one", "a<br>b", "é", "&amp;"]) + ":" + pick(Self.scores)
        case 6: return pick(["t", "u"]) + ": " + pick(Self.scores) + ":" + actors() + pick(["", ":rest", "::"])
        case 7: return pick(["t", "u"]) + ":" + pick(Self.scores) + ":" + actors() + pick(["", " # c", "; v: 2: Me"])
        case 8: return pick(["", "  ", "\t"]) + "w: " + pick(Self.scores) + ": " + actors()
        case 9: return pick([":", ";", "journey", "t", "t 5 Me", "#c"])
        case 10: return "x\u{301}:" + pick(Self.scores) + ":\u{301}" + actors()
        default: return "v: " + pick(Self.scores) + ": " + actors() + "\r"
        }
    }

    mutating func text(statementCount: Int) -> String {
        "journey\n" + (0..<statementCount).map { _ in statement() }.joined(separator: "\n") + pick(["", "\n"])
    }
}
