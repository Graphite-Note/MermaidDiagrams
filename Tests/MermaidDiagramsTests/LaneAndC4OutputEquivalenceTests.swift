/**
 * File: LaneAndC4OutputEquivalenceTests.swift
 * -------------------------------------------
 * Layer: Tests
 * Description: What preparing random and changed C4, agent flow and swimlane texts gives (the SVG, the narrow scenes'
 *              SVGs, what a screen reader says, or why a text is refused), digested as the output digest digests the
 *              corpora, against the digest 0.7.0 and main e817618 give for the same texts: the C4 layout, the agent flow
 *              graph and the lane layout read their new records and spans on texts no corpus holds.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class LaneAndC4OutputEquivalenceTests: XCTestCase {
    /// The digest of every text's line, made by main 2f134c3 (whose C4, agent flow and swimlane code is e817618's).
    static let expectedDigest = "a2b494ad9245b013"

    func testRandomAndChangedTextsArePreparedAsBefore() throws {
        let sources = try Self.sources()
        var everyLine = FowlerNollVoDigest()
        var drawnCountByKind: [String: Int] = [:]
        for (index, source) in sources.enumerated() {
            let outcome = OutputDigest.Outcome(source: source, typography: DiagramSceneSamples.typography,
                                               narrowColumnWidths: OutputDigest.narrowColumnWidths)
            everyLine.add("\(index) \(outcome.summaryLine)\n")
            if let kind = outcome.summaryLine.split(separator: " ").first, kind != "refused" { drawnCountByKind[String(kind), default: 0] += 1 }
        }
        XCTAssertEqual(everyLine.hexadecimal, Self.expectedDigest, "drawn: \(drawnCountByKind.sorted { $0.key < $1.key })")
        XCTAssertGreaterThan(drawnCountByKind["c4", default: 0], 400)
        XCTAssertGreaterThan(drawnCountByKind["agentflow", default: 0], 150)
        XCTAssertGreaterThan(drawnCountByKind["swimlane", default: 0], 600)
    }

    /// Random C4 texts (most of which C4 refuses, for a relation to an alias not written or an argument it cannot read),
    /// the documentation examples and compatibility inputs of the three types changed one to three times, generated
    /// swimlanes and C4 diagrams written to be drawn: 473 C4 diagrams, 192 agent flows and 844 swimlanes drawn, the rest
    /// refused.
    static func sources() throws -> [String] {
        var generator = C4RandomTexts(seed: 21)
        var sources = (0..<3_000).map { _ in generator.text() }
        for prefix in ["c4", "agentflow", "swimlane"] {
            let originals = try PeleResults.sources(ofCorpus: "\(prefix)-docs")
                + PeleResults.compatInputs().filter { $0.key.hasPrefix("\(prefix)/") }.sorted { $0.key < $1.key }.flatMap(\.value)
            for round in 0..<800 { sources.append(generator.mutated(originals[round % originals.count])) }
        }
        var swimlanes = RandomSwimlaneTexts(seed: 5)
        for _ in 0..<600 { sources.append(swimlanes.text()) }
        var c4Diagrams = RandomC4Diagrams(seed: 9)
        for _ in 0..<400 { sources.append(c4Diagrams.text()) }
        return sources
    }
}

/// Swimlanes of up to four lanes of up to four steps, some in a group inside the lane, and random handoffs.
struct RandomSwimlaneTexts {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    private mutating func below(_ bound: Int) -> Int {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Int((state >> 33) % UInt64(max(bound, 1)))
    }

    private static let directions = ["", " LR", " TB", " RL", " BT"]
    private static let labels = ["Step", "A longer label that wraps over a few words", "Pay", "中文", "a<br>b", "\"quoted\""]
    private static let arrows = ["-->", "-.->", "==>", "-->|yes|", "---", "--o"]

    mutating func text() -> String {
        var lines = ["swimlane-beta" + Self.directions[below(Self.directions.count)]]
        var steps: [String] = []
        for lane in 0..<(1 + below(4)) {
            lines.append("  subgraph lane\(lane)[Lane \(lane)]")
            for _ in 0..<(1 + below(4)) {
                let step = "s\(steps.count)"
                steps.append(step)
                lines.append("    \(step)[\(Self.labels[below(Self.labels.count)])]")
                if below(6) == 0 {
                    let inner = "s\(steps.count)"
                    steps.append(inner)
                    lines.append("    subgraph group\(steps.count)\n      \(inner)[Inside]\n    end")
                }
            }
            lines.append("  end")
        }
        for _ in 0..<below(2 * steps.count + 1) {
            lines.append("  \(steps[below(steps.count)]) \(Self.arrows[below(Self.arrows.count)]) \(steps[below(steps.count)])")
        }
        return lines.joined(separator: "\n")
    }
}

/// C4 diagrams written to be drawn: up to 24 shapes, some in boundaries inside each other, and up to 40 relations of
/// every kind between them, so that lines are routed around shapes and their labels placed among others.
struct RandomC4Diagrams {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    private mutating func below(_ bound: Int) -> Int {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Int((state >> 33) % UInt64(max(bound, 1)))
    }

    private mutating func pick(_ choices: [String]) -> String { choices[below(choices.count)] }

    private static let shapes = ["Person", "Person_Ext", "System", "SystemDb", "SystemQueue", "System_Ext", "Container", "ContainerDb", "Component",
                                 "ComponentQueue_Ext"]
    private static let boundaries = ["Enterprise_Boundary", "System_Boundary", "Container_Boundary", "Boundary", "Deployment_Node", "Node_L"]
    /// Every relation but `RelIndex`, whose first argument is an index.
    private static let relations = C4RandomTexts.relations.filter { relation in relation != "RelIndex" }
    private static let labels = ["Customer", "Internet banking system with a long name", "中文", "API", "line<br>two", "Reads & writes", "Uses"]
    private static let details = ["", ", \"Java, Spring\"", ", \"A description that wraps over several words\"", ", $techn=\"HTTPS\"",
                                  ", $tags=\"v1\"", ", $descr=\"Stores\""]

    mutating func text() -> String {
        var lines = [pick(C4RandomTexts.levels)]
        if below(3) == 0 { lines.append("title \(pick(Self.labels))") }
        var aliases: [String] = []
        var depth = 0
        for _ in 0..<(2 + below(23)) {
            if below(5) == 0 {
                lines.append("\(pick(Self.boundaries))(b\(aliases.count), \"\(pick(Self.labels))\") {")
                depth += 1
            }
            if depth > 0, below(4) == 0 {
                lines.append("}")
                depth -= 1
            }
            let alias = "e\(aliases.count)"
            aliases.append(alias)
            lines.append("\(pick(Self.shapes))(\(alias), \"\(pick(Self.labels))\"\(pick(Self.details)))")
        }
        lines += Array(repeating: "}", count: depth)
        for _ in 0..<below(41) {
            lines.append("\(pick(Self.relations))(\(pick(aliases)), \(pick(aliases)), \"\(pick(Self.labels))\"\(pick(Self.details)))")
        }
        if below(3) == 0 { lines.append("UpdateRelStyle(\(pick(aliases)), \(pick(aliases)), $textColor=\"red\", $offsetY=\"-10\")") }
        if below(3) == 0 { lines.append("UpdateLayoutConfig($c4ShapeInRow=\"\(1 + below(5))\", $c4BoundaryInRow=\"\(1 + below(3))\")") }
        return lines.joined(separator: "\n")
    }
}
