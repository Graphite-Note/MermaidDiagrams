/**
 * File: RequirementRandomTexts.swift
 * ----------------------------------
 * Layer: Tests
 * Description: Writes requirement diagrams at random, the same for the same seed: requirements of every kind with and
 *              without their fields, elements, relations of every kind both ways, loops, names shared by a requirement
 *              and an element, styles, directions and a title.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

/// Writes requirement diagrams at random, the same for the same seed.
struct RequirementRandomTexts {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    /// SplitMix64.
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

    private mutating func pick(_ choices: [String]) -> String {
        choices[below(choices.count)]
    }

    private static let names = ["test_req", "r2", "power", "sensor", "\"quoted name\"", "e1", "x", "doc"]
    private static let kinds = ["requirement", "functionalRequirement", "interfaceRequirement", "performanceRequirement", "physicalRequirement",
                                "designConstraint"]
    private static let relations = ["contains", "copies", "derives", "satisfies", "verifies", "refines", "traces"]
    private static let texts = ["the test text.", "\"a longer text that wraps past the width of a box, well past it\"", "\"**bold** and *italic*\"",
                                "\"中文\"", "x"]

    /// A requirement diagram of up to `statementCount` statements.
    mutating func text(statementCount: Int) -> String {
        var lines = [pick(["requirementDiagram", "requirementDiagram\ndirection LR", "requirementDiagram\ndirection BT", "requirementDiagram\ndirection RL"])]
        for _ in 0..<(1 + below(statementCount)) {
            switch below(8) {
            case 0, 1:
                var body = pick(Self.kinds) + " " + pick(Self.names) + " {"
                if below(4) > 0 { body += "\n  id: " + pick(["1", "1.2.3", "REQ-7", "\"a long identifier\""]) }
                if below(4) > 0 { body += "\n  text: " + pick(Self.texts) }
                if below(3) > 0 { body += "\n  risk: " + pick(["low", "medium", "high", "Low"]) }
                if below(3) > 0 { body += "\n  verifymethod: " + pick(["analysis", "inspection", "test", "demonstration"]) }
                lines.append(body + "\n}")
            case 2:
                var body = "element " + pick(Self.names) + " {"
                if below(3) > 0 { body += "\n  type: " + pick(["simulation", "\"word doc\"", "\"test suite\""]) }
                if below(3) > 0 { body += "\n  docref: " + pick(["reqs/test_entity", "github.com/x"]) }
                lines.append(body + "\n}")
            case 3, 4, 5:
                let relation = pick(Self.relations)
                lines.append(below(4) == 0 ? pick(Self.names) + " <- " + relation + " - " + pick(Self.names)
                                           : pick(Self.names) + " - " + relation + " -> " + pick(Self.names))
            case 6:
                let name = pick(Self.names)
                lines.append(name + " - " + pick(Self.relations) + " -> " + name)
            default:
                lines.append(pick(["classDef hot fill:#f00", "class test_req hot", "style r2 fill:#0f0,stroke:#00f", "style e1 font-weight:bold",
                                   "power:::hot", "%% a comment", "accTitle: T", "direction TB"]))
            }
        }
        if below(5) == 0 { lines.insert("---\ntitle: " + pick(Self.texts) + "\n---", at: 0) }
        return lines.joined(separator: "\n")
    }
}
