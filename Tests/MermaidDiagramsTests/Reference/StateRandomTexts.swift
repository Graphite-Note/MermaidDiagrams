/**
 * File: StateRandomTexts.swift
 * ----------------------------
 * Layer: Tests
 * Description: Writes state diagrams at random, the same for the same seed: states and marks, transitions with and
 *              without text, loops, notes on both sides, composite states inside each other with concurrent regions
 *              and directions of their own, and statements the layout does not apply.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

/// Writes state diagrams at random, the same for the same seed.
struct StateRandomTexts {
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

    private static let names = ["A", "B", "C", "D", "Idle", "Moving", "s_1", "é", "中", "Crash", "Still", "K", "x-y"]
    private static let composites = ["Outer", "Inner", "Active", "P"]
    private static let texts = ["go", "a longer text that wraps past the width of a state", "<b>bold</b>", "two<br>lines", "中文", "x", "&amp; more",
                                "\u{00A0}spaced\u{00A0}", "e = 1"]
    private static let directions = ["direction LR", "direction TB", "direction RL", "direction BT"]

    /// A state diagram of up to `statementCount` statements.
    mutating func text(statementCount: Int) -> String {
        var lines = [pick(["stateDiagram-v2", "stateDiagram", "stateDiagram-v2", "stateDiagram-v2\n  direction LR", "stateDiagram\n  direction RL"])]
        var openComposites: [String] = []
        for _ in 0..<(1 + below(statementCount)) {
            let indent = String(repeating: "  ", count: openComposites.count + 1)
            switch below(14) {
            case 0, 1, 2:
                lines.append(indent + endName(isSource: true) + " --> " + endName(isSource: false) + (below(3) == 0 ? " : " + pick(Self.texts) : ""))
            case 3:
                let name = pick(Self.names)
                lines.append(indent + name + " --> " + name + (below(2) == 0 ? " : " + pick(Self.texts) : ""))
            case 4:
                lines.append(indent + pick(Self.names) + " : " + pick(Self.texts))
            case 5:
                lines.append(indent + "state \"" + pick(Self.texts) + "\" as " + pick(Self.names))
            case 6:
                lines.append(indent + "state " + pick(Self.names) + " " + pick(["<<fork>>", "<<join>>", "<<choice>>", "[[fork]]", "<<choice>>"]))
            case 7:
                lines.append(indent + "note " + pick(["left of ", "right of "]) + pick(Self.names + Self.composites) + " : " + pick(Self.texts))
            case 8:
                lines.append(indent + "note " + pick(["left of ", "right of "]) + pick(Self.names) + "\n" + indent + "  " + pick(Self.texts) + "\n" + indent
                             + "  " + pick(Self.texts) + "\n" + indent + "end note")
            case 9 where openComposites.count < 3:
                let name = pick(Self.composites)
                lines.append(indent + "state " + name + " {")
                openComposites.append(name)
            case 10 where !openComposites.isEmpty:
                openComposites.removeLast()
                lines.append(String(repeating: "  ", count: openComposites.count + 1) + "}")
            case 11 where !openComposites.isEmpty:
                lines.append(indent + pick(["--", Self.directions[below(4)]]))
            case 12:
                lines.append(indent + pick(["classDef hot fill:#f00", "class A hot", "style B fill:#0f0", "A:::hot --> B", "accTitle: T", "accDescr: D",
                                            "%% a comment", Self.directions[below(4)]]))
            default:
                lines.append(indent + pick(Self.composites + Self.names) + " --> " + pick(Self.composites + Self.names))
            }
        }
        while !openComposites.isEmpty {
            openComposites.removeLast()
            lines.append(String(repeating: "  ", count: openComposites.count + 1) + "}")
        }
        if below(5) == 0 { lines.insert("---\ntitle: " + pick(Self.texts) + "\n---", at: 0) }
        return lines.joined(separator: "\n")
    }

    private mutating func endName(isSource: Bool) -> String {
        below(5) == 0 ? "[*]" : pick(Self.names)
    }
}
