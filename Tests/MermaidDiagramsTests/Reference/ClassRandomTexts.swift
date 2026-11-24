/**
 * File: ClassRandomTexts.swift
 * ----------------------------
 * Layer: Tests
 * Description: Writes class diagrams at random, the same for the same seed: classes with members and annotations,
 *              relations of every kind with texts and cardinalities, lollipop interfaces, loops, notes, namespaces
 *              inside each other, directions and statements the layout does not apply.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

/// Writes class diagrams at random, the same for the same seed.
struct ClassRandomTexts {
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

    private static let names = ["Animal", "Duck", "Fish", "Zebra", "A", "B", "C", "Shape~T~", "é", "List~int~", "Order", "K"]
    private static let relations = ["<|--", "*--", "o--", "-->", "--", "..>", "..|>", "..", "<|..", "--*", "--o", "<-->", "()--", "--()", "*--*"]
    private static let members = ["+int age", "-String name", "#List~int~ items", "+isMammal() bool", "+mate()$", "someMethod()*", "~package int x",
                                  "+a very long member name that is wider than most boxes", "中文 member", "+swim(int depth) void"]
    private static let texts = ["has", "a longer label that wraps past the width", "1..*", "<b>bold</b>", "中", "uses"]
    private static let cardinalities = ["\"1\"", "\"*\"", "\"0..1\"", "\"many\"", ""]

    /// A class diagram of up to `statementCount` statements.
    mutating func text(statementCount: Int) -> String {
        var lines = [pick(["classDiagram", "classDiagram-v2", "classDiagram\n  direction LR", "classDiagram\n  direction RL", "classDiagram\n  direction BT"])]
        var depth = 0
        for _ in 0..<(1 + below(statementCount)) {
            let indent = String(repeating: "  ", count: depth + 1)
            switch below(13) {
            case 0, 1, 2:
                let source = pick(Self.names)
                let target = pick(Self.names)
                let sourceCardinality = pick(Self.cardinalities)
                let targetCardinality = pick(Self.cardinalities)
                lines.append(indent + source + (sourceCardinality.isEmpty ? "" : " " + sourceCardinality) + " " + pick(Self.relations) + " "
                             + (targetCardinality.isEmpty ? "" : targetCardinality + " ") + target + (below(3) == 0 ? " : " + pick(Self.texts) : ""))
            case 3:
                let name = pick(Self.names)
                lines.append(indent + name + " " + pick(Self.relations) + " " + name)
            case 4, 5:
                var body = indent + "class " + pick(Self.names) + " {"
                for _ in 0..<below(5) { body += "\n" + indent + "  " + pick(Self.members) }
                lines.append(body + "\n" + indent + "}")
            case 6:
                lines.append(indent + pick(Self.names) + " : " + pick(Self.members))
            case 7:
                lines.append(indent + pick(["<<interface>> ", "<<abstract>> ", "<<Service>> "]) + pick(Self.names))
            case 8:
                lines.append(indent + pick(["note for " + pick(Self.names) + " \"" + pick(Self.texts) + "\"", "note \"" + pick(Self.texts) + "\""]))
            case 9 where depth < 3:
                lines.append(indent + "namespace " + pick(["Shapes", "Animals", "N.M", "Core"]) + " {")
                depth += 1
            case 10 where depth > 0:
                depth -= 1
                lines.append(String(repeating: "  ", count: depth + 1) + "}")
            case 11:
                lines.append(indent + pick(["classDef hot fill:#f00", "cssClass \"A\" hot", "style B fill:#0f0", "class C:::hot", "accTitle: T", "accDescr: D",
                                            "%% a comment", "direction TB", "link A \"https://example.com\"", "callback B \"f\""]))
            default:
                lines.append(indent + "class " + pick(Self.names) + pick(["", "[\"Label\"]", "~T~", ":::hot"]))
            }
        }
        while depth > 0 {
            depth -= 1
            lines.append(String(repeating: "  ", count: depth + 1) + "}")
        }
        if below(6) == 0 { lines.insert("---\nconfig:\n  class:\n    hideEmptyMembersBox: true\n---", at: 0) }
        if below(5) == 0 { lines.insert("---\ntitle: " + pick(Self.texts) + "\n---", at: 0) }
        return lines.joined(separator: "\n")
    }
}
