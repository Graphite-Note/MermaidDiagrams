/**
 * File: BlockReadingEquivalenceTests.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: The block reader gives, to the last field, the diagram 0.7.0's reader gave (ReferenceBlockParser), or
 *              the same error, on every corpus, the specification's texts, thousands of texts mutated from them and
 *              random statements; hostile texts stay bounded.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class BlockReadingEquivalenceTests: XCTestCase {
    private static let keywords: Set<String> = ["block", "block-beta"]

    private func agree(_ source: String) -> Bool? {
        ChartReadingEquivalence.agree(source, keywords: Self.keywords, read: { (cursor, keyword) throws(MermaidDiagramReadError) in
            try BlockParser.parse(cursor, keyword: keyword, limits: .standard)
        }, reference: { (cursor, keyword) throws(MermaidDiagramReadError) in
            try ReferenceBlockParser.parse(cursor, keyword: keyword, limits: .standard)
        })
    }

    private func assertAgree(_ sources: [String], atLeast count: Int, file: StaticString = #filePath, line: UInt = #line) {
        var compared = 0
        for source in sources {
            guard let agrees = agree(source) else { continue }
            XCTAssertTrue(agrees, "\(source.prefix(200))", file: file, line: line)
            compared += 1
        }
        XCTAssertGreaterThanOrEqual(compared, count, file: file, line: line)
    }

    func testEveryCorpusIsReadAsZeroSevenReadIt() throws {
        assertAgree(try ChartReadingEquivalence.corpusSources(keywords: Self.keywords) + Self.specificationTexts, atLeast: 40)
    }

    func testMutatedTextsAreReadAsZeroSevenReadThem() throws {
        var mutations = ChartTextMutations(seed: 0xB10C_2A)
        let sources = try ChartReadingEquivalence.corpusSources(keywords: Self.keywords) + Self.specificationTexts
        var mutated: [String] = []
        for source in sources {
            for _ in 0..<60 { mutated.append(mutations.mutated(source)) }
            for _ in 0..<60 { mutated.append(mutations.spliced(source)) }
        }
        assertAgree(mutated, atLeast: 4_000)
    }

    func testRandomStatementsAreReadAsZeroSevenReadThem() {
        var random = BlockRandomStatements(seed: 0x5EED_B10C)
        let seed = random.seed
        var sources: [String] = []
        for index in 0..<1_500 { sources.append(random.text(statementCount: 1 + index % 30)) }
        var compared = 0
        for source in sources {
            guard let agrees = agree(source) else { continue }
            XCTAssertTrue(agrees, "seed \(seed): \(source)")
            compared += 1
        }
        XCTAssertEqual(compared, sources.count)
    }

    /// Hostile texts are read or refused in time that grows with their length, as 0.7.0 read them.
    func testHostileTextsAgreeAndStayBounded() {
        let cases = [
            "block\n" + String(repeating: "a b:3 c[\"x\"] ", count: 6_000),
            "block\n" + String(repeating: "block\n", count: 3_000) + "a\n" + String(repeating: "end\n", count: 3_000),
            "block\n" + String(repeating: "a --> b -- \"t\" --> c ", count: 3_000),
            "block\nA\nclass " + String(repeating: "A,", count: 20_000) + "A hot\nclassDef hot fill:#f96",
            "block\n" + String(repeating: "space:9 ", count: 5_000),
            "block\nA<[\"x\"]>(" + String(repeating: "up, down , x,y ", count: 3_000) + ")",
            "block\n" + String(repeating: "(([[{{", count: 8_000),
        ]
        for source in cases {
            let started = Date()
            XCTAssertEqual(agree(source), true, String(source.prefix(80)))
            XCTAssertLessThan(Date().timeIntervalSince(started), 5, String(source.prefix(80)))
        }
    }

    /// Mermaid's block diagram documentation and the grammar's corners.
    static let specificationTexts = [
        "block-beta\ncolumns 3\na b c\nd:2 e\n",
        "block\n  columns auto\n  a b\n",
        "block\n  block:outer:2\n    columns 2\n    block:inner\n      x y\n    end\n    z\n  end\n  w\n",
        "block\n  A-- \"label\" -->B\n  B==>C\n  C-.->D\n  D<-->E\n  Ex--xF\n  Fo--oG\n",
        "block\n  a[\"`**bold**`\"] b(\"&amp; and <br> breaks\")\n",
        "block\n  arrow<[\"go\"]>(right, down)\n  other<[\" \"]>(x)\n",
        "block\n  classDef hot fill:#f96,stroke:#333;\n  class a,b hot\n  style c fill:#bbf;stroke-width:4px\n  a b c\n",
        "block\n  space space:3 a\n",
        "block\n  accTitle: The title\n  accDescr: The description\n  a\n",
        "block\n  accDescr {\n    long\n    description\n  }\n  a\n",
        "block\n  a\n  %% a comment\n  b\n",
        "block\r\n  a\r\n  b\r\n",
        "---\ntitle: Titled\nconfig:\n  block:\n    padding: 30\n---\nblock\n  a\n",
        "block\n  end\n",
        "block\n  block\n    a\n",
        "block\n  a:\n",
        "block\n  a[\"unclosed\n",
        "block\n  columns 0\n  a\n",
        "block\n  a --> \n",
        "block\n  block:a --> b\n    c\n  end\n",
    ]
}

/// Random block statements from a seeded generator: blocks of every shape, arrows, spaces, links, composites, columns,
/// classes and styles, some of them broken.
struct BlockRandomStatements {
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

    private static let shapes = [("[", "]"), ("(", ")"), ("((", "))"), (">", "]"), ("{", "}"), ("{{", "}}"), ("([", "])"), ("[[", "]]"),
                                 ("[(", ")]"), ("(((", ")))"), ("[/", "/]"), ("[\\", "\\]"), ("[/", "\\]"), ("[\\", "/]")]
    private static let links = ["-->", "---", "==>", "-.->", "<-->", "x--x", "o--o", "--", "-- \"t\" -->", "== \"u\" ==>"]
    private static let directions = ["right", "left", "up", "down", "x", "y"]

    private mutating func identifier() -> String {
        ["a", "b", "c", "id1", "id2", "Ab_9", "é", "x"][next(below: 8)]
    }

    private mutating func block() -> String {
        let name = identifier()
        switch next(below: 6) {
        case 0: return name
        case 1: return name + ":" + String(next(below: 5))
        case 2:
            let shape = Self.shapes[next(below: Self.shapes.count)]
            return name + shape.0 + "\"text \(next(below: 9))\"" + shape.1
        case 3: return name + "<[\"go\"]>(" + Self.directions[next(below: 6)] + (next(below: 2) == 0 ? ", " + Self.directions[next(below: 6)] : "") + ")"
        case 4: return name + "[\"`*md*`\"]"
        default: return name + "[\"&nbsp;<br>&amp;\"]"
        }
    }

    mutating func text(statementCount: Int) -> String {
        var lines = [next(below: 4) == 0 ? "block-beta" : "block"]
        var depth = 0
        for _ in 0..<statementCount {
            switch next(below: 12) {
            case 0, 1, 2: lines.append((0...next(below: 3)).map { _ in block() }.joined(separator: " "))
            case 3: lines.append(block() + " " + Self.links[next(below: Self.links.count)] + " " + block())
            case 4: lines.append("columns " + (next(below: 3) == 0 ? "auto" : String(next(below: 6))))
            case 5: lines.append(next(below: 2) == 0 ? "space" : "space:" + String(next(below: 4)))
            case 6:
                lines.append(next(below: 2) == 0 ? "block" : "block:" + identifier() + (next(below: 2) == 0 ? ":2" : ""))
                depth += 1
            case 7:
                if depth > 0 || next(below: 5) == 0 {
                    lines.append("end")
                    depth -= 1
                }
            case 8: lines.append("classDef c\(next(below: 3)) fill:#f96,stroke:#333" + (next(below: 2) == 0 ? ";" : ""))
            case 9: lines.append("class " + identifier() + "," + identifier() + " c\(next(below: 3))")
            case 10: lines.append("style " + identifier() + " fill:#bbf,stroke-width:\(next(below: 5))px")
            default: lines.append(next(below: 2) == 0 ? "%% comment" : "  ")
            }
        }
        for _ in 0..<max(depth, 0) where next(below: 4) != 0 { lines.append("end") }
        return lines.joined(separator: "\n")
    }
}
