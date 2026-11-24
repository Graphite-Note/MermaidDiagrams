/**
 * File: C4ReadingEquivalenceTests.swift
 * -------------------------------------
 * Layer: Tests
 * Description: The C4 reader on ranges of the text's bytes against the 0.7.0 reader kept as the reference: every input
 *              of the corpora and of Pele's compatibility tests, generated diagrams, random C4 texts and mutated ones,
 *              each the same model, field for field, or the same error.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class C4ReadingEquivalenceTests: XCTestCase {
    func testEveryInputOfTheCorporaAndOfPelesCompatibilityTestsIsReadAsTheReferenceReadsIt() throws {
        let sources = try OutputDigest.corpora().flatMap(\.sources) + PeleResults.compatInputs().sorted { $0.key < $1.key }.flatMap(\.value)
        let checked = Self.assertReadAlike(sources)
        XCTAssertGreaterThan(checked, 30)
    }

    func testGeneratedDiagramsAreReadAsTheReferenceReadsThem() {
        var sources: [String] = []
        for shapeCount in [1, 10, 60, 300] {
            for boundaryCount in [0, 3, 20] {
                sources.append(C4Corpus.generated(shapeCount: shapeCount, boundaryCount: boundaryCount, relationCount: shapeCount * 2))
            }
        }
        XCTAssertEqual(Self.assertReadAlike(sources), sources.count)
    }

    func testRandomTextsAreReadAsTheReferenceReadsThem() {
        var generator = C4RandomTexts(seed: 7)
        let sources = (0..<3_000).map { _ in generator.text() }
        XCTAssertGreaterThan(Self.assertReadAlike(sources), 2_000)
    }

    func testMutatedTextsAreReadAsTheReferenceReadsThem() throws {
        var mutations = C4RandomTexts(seed: 11)
        let originals = try C4Corpus.documentationExamples() + (PeleResults.compatInputs().filter { $0.key.hasPrefix("c4/") }.flatMap(\.value))
        var sources: [String] = []
        for round in 0..<4_000 { sources.append(mutations.mutated(originals[round % originals.count])) }
        XCTAssertGreaterThan(Self.assertReadAlike(sources), 2_000)
    }

    func testLimitsRefuseAlike() throws {
        let source = C4Corpus.generated(shapeCount: 80, boundaryCount: 10, relationCount: 160)
        let standard = MermaidDiagramLimits.standard
        func limits(bytes: Int = standard.maximumSourceBytes, nodes: Int, edges: Int) -> MermaidDiagramLimits {
            MermaidDiagramLimits(maximumSourceBytes: bytes, maximumNodeCount: nodes, maximumEdgeCount: edges, maximumLayoutPointCount: standard.maximumLayoutPointCount)
        }
        for limits in [limits(nodes: 5, edges: 500), limits(nodes: 500, edges: 7), limits(bytes: 100, nodes: 500, edges: 500)] {
            XCTAssertEqual(Self.assertReadAlike([source], limits: limits), 1)
        }
    }

    /// Reads each source both ways and fails for each that differs; returns how many the reference read as C4.
    @discardableResult
    static func assertReadAlike(_ sources: [String], limits: MermaidDiagramLimits = .standard, file: StaticString = #filePath, line: UInt = #line) -> Int {
        var checked = 0
        var mismatches = 0
        for source in sources {
            let reference = Result { () throws(MermaidDiagramReadError) in try ReferenceC4Reading.read(source, limits: limits) }
            let package = Result { () throws(MermaidDiagramReadError) in try MermaidDiagramReader.read(source, limits: limits) }
            var difference: String?
            switch (reference, package) {
            case (.success(.otherType), _): continue
            case (.success(.c4(let expected)), .success(.c4(let read))):
                if !expected.matches(read) { difference = "read otherwise: \(read.shapes.count) shapes, \(read.relations.count) relations" }
            case (.failure(let expected), .failure(let error)):
                if expected != error { difference = "error \(error) where the reference throws \(expected)" }
            case (.failure(let expected), .success): difference = "read where the reference throws \(expected)"
            case (.success, .failure(let error)): difference = "throws \(error) where the reference reads"
            case (.success, .success): difference = "read as another type"
            }
            checked += 1
            if let difference {
                mismatches += 1
                if mismatches <= 5 { XCTFail("\(difference):\n\(source.prefix(600))", file: file, line: line) }
            }
        }
        XCTAssertEqual(mismatches, 0, file: file, line: line)
        return checked
    }
}

/// Random C4 texts of the pieces a C4 reader treats apart, and changes made to written ones.
struct C4RandomTexts {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    private mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }

    private mutating func below(_ bound: Int) -> Int {
        bound <= 1 ? 0 : Int(next() % UInt64(bound))
    }

    private mutating func pick(_ choices: [String]) -> String { choices[below(choices.count)] }

    static let levels = ["C4Context", "C4Container", "C4Component", "C4Dynamic", "C4Deployment"]
    static let shapes = ["Person", "Person_Ext", "System", "SystemDb", "SystemQueue", "System_Ext", "SystemDb_Ext", "SystemQueue_Ext", "Container",
                         "ContainerDb", "ContainerQueue", "Container_Ext", "Component", "ComponentDb_Ext", "ComponentQueue_Ext"]
    static let boundaries = ["Enterprise_Boundary", "System_Boundary", "Boundary", "Container_Boundary", "Deployment_Node", "Node", "Node_L", "Node_R"]
    static let relations = ["Rel", "BiRel", "Rel_Up", "Rel_U", "Rel_Down", "Rel_D", "Rel_Left", "Rel_L", "Rel_Right", "Rel_R", "Rel_Back", "RelIndex"]
    /// Aliases, some written in two spellings Swift holds equal (a composed and a decomposed é, the Kelvin sign and K).
    static let aliases = ["a", "b", "c", "user", "db", "K", "\u{212A}", "caf\u{E9}", "cafe\u{301}", "全", "a b", "x1", "global"]
    static let values = ["label", "\"quoted\"", "", " spaced ", "line<br>two", "a\\nb", "&amp;", "<b>bold</b>", "*", "Ünïcödé", "中文", "5px", "-3",
                         "0x1f", "#ff0000", "red", "none", "transparent", "person", "database", "queue", "db,queue", "  rounded ", "1e3"]
    static let keys = ["label", "type", "descr", "techn", "sprite", "tags", "link", "bgColor", "fontColor", "borderColor", "shadowing", "shape", "legendText",
                       "legendSprite", "offsetX", "offsetY", "textColor", "lineColor", "other", "baseShape", "K", "\u{212A}"]

    private mutating func argument() -> String {
        switch below(6) {
        case 0: return "$\(pick(Self.keys))=\"\(pick(Self.values))\""
        case 1: return ""
        case 2: return "\"\(pick(Self.values))\""
        default: return pick(Self.values)
        }
    }

    private mutating func arguments(_ count: Int, firstAlias: Bool) -> String {
        var written: [String] = []
        for index in 0..<count {
            if firstAlias, index < 2, below(8) != 0 { written.append(pick(Self.aliases)) } else { written.append(argument()) }
        }
        return written.joined(separator: below(4) == 0 ? ", " : ",")
    }

    /// A text of up to 30 statements: shapes, boundaries opening and closing, relations, updates, titles and accessibility.
    mutating func text() -> String {
        var lines = [pick(Self.levels)]
        var depth = 0
        for _ in 0..<(1 + below(30)) {
            switch below(14) {
            case 0...3: lines.append("\(pick(Self.shapes))(\(arguments(1 + below(8), firstAlias: true)))")
            case 4, 5:
                lines.append("\(pick(Self.boundaries))(\(arguments(1 + below(7), firstAlias: true)))\(below(3) == 0 ? "\n" : " "){")
                depth += 1
            case 6 where depth > 0:
                lines.append("}")
                depth -= 1
            case 7...9: lines.append("\(pick(Self.relations))(\(arguments(2 + below(8), firstAlias: true)))")
            case 10: lines.append("UpdateElementStyle(\(arguments(1 + below(10), firstAlias: true)))")
            case 11: lines.append("UpdateRelStyle(\(arguments(2 + below(6), firstAlias: true)))")
            case 12: lines.append(pick(["UpdateLayoutConfig($c4ShapeInRow=\"3\", $c4BoundaryInRow=\"1\")", "UpdateLayoutConfig(2, 5)", "UpdateLayoutConfig(\"0\")"]))
            default: lines.append(pick(["title A title", "title", "accTitle: An accessible title", "accDescr: Described", "accDescr {\n  many\n    lines\n}",
                                        "accDescription Another", "%% a comment", "direction LR", ""]))
            }
        }
        for _ in 0..<depth where below(5) != 0 { lines.append("}") }
        return lines.joined(separator: below(10) == 0 ? "\r\n" : "\n")
    }

    static let insertedTokens = ["(", ")", ",", "\"", "$", "=", "{", "}", "\n", "\r\n", " ", "\t", "\u{00A0}", "\u{2028}", "%%", "title ", "accTitle:",
                                 "accDescr {", "direction TB", "Rel(", "Person(", "Boundary(b, \"B\") {", "é", "\u{212A}", "$tags=\"x\"", "\\n", "<br>"]

    /// `source` changed one to three times: a line cut, a piece spliced elsewhere, or a token inserted.
    mutating func mutated(_ source: String) -> String {
        var scalars = Array(source.unicodeScalars)
        for _ in 0...below(3) {
            switch below(3) {
            case 0:
                let lineStarts = [0] + scalars.indices.filter { index in scalars[index] == "\n" }.map { index in index + 1 }
                let start = lineStarts[below(lineStarts.count)]
                let end = scalars[start...].firstIndex(of: "\n").map { index in index + 1 } ?? scalars.count
                scalars.removeSubrange(start..<end)
            case 1 where !scalars.isEmpty:
                let start = below(scalars.count)
                let piece = Array(scalars[start..<min(scalars.count, start + 1 + below(16))])
                scalars.insert(contentsOf: piece, at: below(scalars.count + 1))
            default:
                scalars.insert(contentsOf: Self.insertedTokens[below(Self.insertedTokens.count)].unicodeScalars, at: below(scalars.count + 1))
            }
        }
        var text = String.UnicodeScalarView()
        text.append(contentsOf: scalars)
        return String(text)
    }
}
