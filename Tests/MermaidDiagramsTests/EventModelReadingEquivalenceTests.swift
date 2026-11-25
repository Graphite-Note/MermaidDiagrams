/**
 * File: EventModelReadingEquivalenceTests.swift
 * ---------------------------------------------
 * Layer: Tests
 * Description: The event model reader gives, to the last field, the diagram 0.7.0's reader gave (ReferenceEventModelParser and
 *              its builder), or the same error, on every corpus, the specification's texts, thousands of texts mutated
 *              from them and random statements; hostile texts stay bounded.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class EventModelReadingEquivalenceTests: XCTestCase {
    private static let keywords: Set<String> = ["eventmodeling"]

    private func agree(_ source: String, limits: MermaidDiagramLimits = .standard) -> Bool? {
        ChartReadingEquivalence.agree(source, keywords: Self.keywords, read: { (cursor, keyword) throws(MermaidDiagramReadError) in
            try EventModelParser.parse(cursor, keyword: keyword, limits: limits)
        }, reference: { (cursor, keyword) throws(MermaidDiagramReadError) in
            try ReferenceEventModelParser.parse(cursor, keyword: keyword, limits: limits)
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
        assertAgree(try ChartReadingEquivalence.corpusSources(keywords: Self.keywords) + Self.specificationTexts, atLeast: 12 + Self.specificationTexts.count - 1)
    }

    func testMutatedTextsAreReadAsZeroSevenReadThem() throws {
        var mutations = ChartTextMutations(seed: 0xE7E_4D0)
        let sources = try ChartReadingEquivalence.corpusSources(keywords: Self.keywords) + Self.specificationTexts
        var mutated: [String] = []
        for source in sources {
            for _ in 0..<80 { mutated.append(mutations.mutated(source)) }
            for _ in 0..<80 { mutated.append(mutations.spliced(source)) }
        }
        assertAgree(mutated, atLeast: 4_000)
    }

    func testRandomStatementsAreReadAsZeroSevenReadThem() {
        var random = EventModelRandomStatements(seed: 0x5EED_E7E)
        let seed = random.seed
        var compared = 0
        var drawn = 0
        for index in 0..<3_000 {
            let source = random.text(statementCount: 1 + index % 40)
            guard let agrees = agree(source) else { continue }
            XCTAssertTrue(agrees, "seed \(seed): \(source)")
            compared += 1
            if case .eventModel = try? MermaidDiagramReader.read(source, limits: .standard) { drawn += 1 }
        }
        XCTAssertEqual(compared, 3_000)
        XCTAssertGreaterThan(drawn, 600, "enough random texts should be read whole, not refused")
    }

    /// The node and edge limits refuse at the same statement as 0.7.0's reader refused.
    func testLimitsRefuseWhereZeroSevenRefused() {
        let limits = MermaidDiagramLimits(maximumSourceBytes: 50_000, maximumNodeCount: 6, maximumEdgeCount: 4, maximumLayoutPointCount: 50)
        let sources = [
            "eventmodeling\n" + (1...9).map { frame in "tf \(frame) evt E\(frame)\n" }.joined(),
            "eventmodeling\ntf 1 ui A\ntf 2 cmd B ->> 1\ntf 3 evt C ->> 1 ->> 2\ntf 4 rmo D ->> 3 ->> 2 ->> 1\n",
            "eventmodeling\ntf 1 ui A\ntf 2 cmd B\ntf 3 evt C\ntf 4 rmo D\ntf 5 ui E\ntf 6 cmd F\n",
        ]
        for source in sources { XCTAssertEqual(agree(source, limits: limits), true, source) }
    }

    /// Hostile texts are read or refused in time that grows with their length, as 0.7.0 read them: frames past the
    /// short lists' lengths, every frame in one lane, many namespaces, sources named again and again.
    func testHostileTextsAgreeAndStayBounded() {
        let cases = [
            "eventmodeling\n" + (1...999).map { frame in "tf \(frame) evt E\(frame)\n" }.joined(),
            "eventmodeling\n" + (1...999).map { frame in "tf \(frame) \(["ui", "cmd", "evt", "rmo"][frame % 4]) N\(frame % 300).E\(frame)\n" }.joined(),
            "eventmodeling\n" + (1...400).map { frame in "tf \(frame) evt E" + String(repeating: " ->> \(max(1, frame - 1))", count: 10) + "\n" }.joined(),
            "eventmodeling\ndata D {\n" + String(repeating: "    \"key\": \"value\",\r\n", count: 2_000) + "}\ntf 1 evt E [[D]]\n",
            "eventmodeling\n" + (1...900).map { frame in "tf \(frame) rf\n" }.joined(),
            "eventmodeling\n" + String(repeating: "tf 01 evt E\n", count: 2),
        ]
        for source in cases {
            let started = Date()
            XCTAssertEqual(agree(source), true, String(source.prefix(80)))
            XCTAssertLessThan(Date().timeIntervalSince(started), 5, String(source.prefix(80)))
        }
    }

    /// The title and accessibility statements' values, found after their keyword on the bytes of an ASCII statement,
    /// are those 0.7.0 found through Foundation's search, for statements of ASCII and beyond, with the keyword written
    /// once, twice, joined to combining marks or not at all.
    func testStatementValuesAreThoseZeroSevenGave() {
        let pieces = ["title", "accTitle", "accDescr", ":", " ", "  ", "\t", "{", "}", "\n", "\r\n", "x", "My title", "é", "e\u{301}",
                      "\u{301}", "\u{3000}", "tit", "le", "%%", "中"]
        var state: UInt64 = 0x57A7_E11E
        func below(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(bound))
        }
        for _ in 0..<20_000 {
            let statement = (0..<below(10)).map { _ in pieces[below(pieces.count)] }.joined()
            XCTAssertEqual(FirstMatchStatementValues.title(of: statement), ReferenceFirstMatchStatementValues.title(of: statement), statement.debugDescription)
            XCTAssertEqual(FirstMatchStatementValues.accessibilityTitle(of: statement), ReferenceFirstMatchStatementValues.accessibilityTitle(of: statement),
                           statement.debugDescription)
            XCTAssertEqual(FirstMatchStatementValues.accessibilityDescription(of: statement),
                           ReferenceFirstMatchStatementValues.accessibilityDescription(of: statement), statement.debugDescription)
        }
    }

    /// A frame's data and a card's rows are cut into lines on their bytes, for ASCII without a semicolon or a carriage
    /// return, as they are scalar by scalar.
    func testDataIsCutIntoLinesAsScalarByScalar() {
        let pieces = ["a", "key: value", "\n", "\n\n", " ", String(repeating: "x", count: 47), String(repeating: "y", count: 49), "&amp;", "#59;",
                      ";", "\r", "\r\n", "é", "中", "\t"]
        var state: UInt64 = 0xDA7A_C07
        func below(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(bound))
        }
        for _ in 0..<10_000 {
            let text = (0..<below(8)).map { _ in pieces[below(pieces.count)] }.joined()
            for columns in [1, 3, 48, 80] {
                XCTAssertEqual(EventModelText.hardWrapped(text, columns: columns), EventModelText.hardWrappedScalarByScalar(text, columns: columns),
                               text.debugDescription)
            }
        }
    }

    /// Mermaid's event modeling documentation and the grammar's corners.
    static let specificationTexts = [
        "eventmodeling\n\ntf 01 ui CartUI\ntf 02 cmd AddItem\ntf 03 evt ItemAdded\n",
        "eventmodeling\ntf 01 ui CartUI\ntf 02 cmd AddItem { description: string }\ntf 03 evt ItemAdded { description: string }\n",
        "eventmodeling\ntf 01 evt Cart.ItemAdded\ntf 02 evt Inventory.Changed\ntf 03 rmo Cart.View ->> 01 ->> 02\nrf 04 evt External.Reset\n",
        "eventmodeling\ndata Item {\n    id: 1,\n      name: \"x\"\n}\ntf 01 evt ItemAdded [[Item]]\ntf 02 cmd Add [[Missing]] `json`{ \"a\": 1 }\n",
        "eventmodeling\ntf 01 evt A `json`{ \"a\": 1 }\ntf 02 evt B \"quoted\"\ntf 03 evt C 'single'\n",
        "eventmodeling\nnote 01 {\n  a note\n}\ngwt 02 given evt A when cmd B then evt C evt D\ntf 01 ui A\ntf 02 cmd B\n",
        "eventmodeling\ntitle The model\naccTitle: Accessible\naccDescr: Described\ntf 1 processor P\ntf 2 command C\ntf 3 event E\ntf 4 readmodel R\n",
        "eventmodeling\naccDescr {\n  long\n  text\n}\nentity evt Ns.Name\ntf 1 pcr Ns.P\ntf 2 ui Other.U ->> 1 ->> 9 ->> 2\n",
        "eventmodeling\ntimeframe 1 ui A\nresetframe 2 evt B\ntf 3 evt A.B.C\ntf 4 evt .x\n",
        "eventmodeling\ntf 1 evt E\ntf 1 evt F\n",
        "eventmodeling\ntf 1 evt E ->> 2\ntf 2 evt F ->> 1 ->> 1 ->> 2\n",
        "eventmodeling\ntf 1 evt E\n%% comment\n// line\n/* block */ tf 2 cmd C\n",
        "eventmodeling\ntf 1 evt E {\r\n  a\r\n}\ntf 2 evt F\n",
        "eventmodeling\ntf 1 nonsense E\n",
        "eventmodeling\ntf x evt E\n",
        "eventmodelingx\ntf 1 evt E\n",
    ]
}

/// Random event model statements from a seeded generator: frames of every kind, numbered again or out of order, in
/// namespaces, fed by named sources, with data written in braces, quotes or a data block, and notes, specifications,
/// entities, titles and comments, some of them broken.
struct EventModelRandomStatements {
    private(set) var seed: UInt64
    private var state: UInt64
    /// The frames numbered so far in the text being made, so that most numbers are new and most sources earlier.
    private var frameCount = 0

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

    private static let kinds = ["ui", "cmd", "command", "evt", "event", "rmo", "readmodel", "pcr", "processor"]

    private mutating func number() -> String {
        next(below: 8) == 0 ? pick(["1", "2", "01", "02", "999", "0"]) : String(1 + next(below: frameCount + 2))
    }

    /// A frame's own number: the next one, or now and then one already used or written with a zero in front.
    private mutating func frameNumber() -> String {
        frameCount += 1
        switch next(below: 40) {
        case 0: return number()
        case 1: return "0" + String(frameCount)
        default: return String(frameCount)
        }
    }

    private mutating func entity() -> String {
        pick(["", "", "Cart.", "Inventory.", "Ns.Sub.", "N\(next(below: 12))."]) + pick(["Add", "Item", "A_b", "x9", "View"])
    }

    private mutating func data() -> String {
        switch next(below: 6) {
        case 0: return ""
        case 1: return " `json`{ \"a\": \(next(below: 9)) }"
        case 2: return " \"quoted \(next(below: 9))\""
        case 3: return " [[" + pick(["D", "E", "Missing"]) + "]]"
        case 4: return " [[D]] 'inline'"
        case 5: return " {" + pick([" a: 1, b: 2 ", "\t\tx  ", " } {", ""]) + "}"
        default: return next(below: 10) == 0 ? " {\n  a: 1\n}" : ""
        }
    }

    /// A statement, now and then a broken one, which refuses the whole text.
    private mutating func statement() -> String {
        if next(below: 80) == 0 { return pick(["tf", "tf 1", "tf 1 bad X", "->>", "[[", "`json`", "data", "note 1", "gwt 1 given"]) }
        switch next(below: 11) {
        case 0, 1, 2, 3:
            let sources = (0..<next(below: 4)).map { _ in " ->> " + number() }.joined()
            return pick(["tf", "tf", "rf", "timeframe", "resetframe"]) + " " + frameNumber() + " " + pick(Self.kinds) + " " + entity() + sources + data()
        case 4: return "data " + pick(["D", "E"]) + pick(["", " `json`"]) + " {\n  " + pick(["k: v", "\"q\": 1", "é"]) + "\n}"
        case 5: return "note " + number() + " {\n  " + pick(["text", "two\n  lines", ""]) + "\n}"
        case 6: return "gwt " + number() + " given evt A" + pick(["", " when cmd B"]) + " then evt C" + pick(["", " rmo D"])
        case 7: return "entity " + entity()
        case 8: return pick(["title T", "title  spaced  out", "accTitle: a", "accDescr: d", "accDescr {\n x\n}"])
        case 9: return pick(["%% c", "// c", "/* c */"])
        default: return "tf " + frameNumber() + " " + pick(Self.kinds) + " " + entity() + " ->> " + number() + " ->> " + number()
        }
    }

    mutating func text(statementCount: Int) -> String {
        frameCount = 0
        return "eventmodeling\n" + (0..<statementCount).map { _ in statement() }.joined(separator: "\n") + "\n"
    }
}
