/**
 * File: EntityRelationshipRandomTexts.swift
 * -----------------------------------------
 * Layer: Tests
 * Description: Writes entity relationship diagrams at random, the same for the same seed: entities with attribute
 *              tables of every column, relationships of every cardinality with and without labels, loops, groups
 *              inside each other, directions and statements the layout does not apply.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

/// Writes entity relationship diagrams at random, the same for the same seed.
struct EntityRelationshipRandomTexts {
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

    private static let names = ["CUSTOMER", "ORDER", "LINE-ITEM", "PRODUCT", "A", "B", "p[\"Person\"]", "é", "DELIVERY_ADDRESS", "K"]
    private static let cardinalities = ["||--o{", "||--|{", "}o--o{", "|o--||", "}|..|{", "||--||", "o{--||", "}o..o|", "|o..o|", "one or more to zero or one"]
    private static let attributes = ["string name", "int id PK", "string email UK \"the address\"", "float price", "int customerId FK", "string `a\nb` PK, FK",
                                     "date when \"a longer comment that wraps past the width of the box, well past it\"", "type-with-dash value", "x y"]
    private static let labels = ["places", "\"contains many\"", "uses", "\"a longer label that wraps past the width\"", "\"\"", "中"]

    /// An entity relationship diagram of up to `statementCount` statements.
    mutating func text(statementCount: Int) -> String {
        var lines = [pick(["erDiagram", "erDiagram\n  direction LR", "erDiagram\n  direction RL", "erDiagram\n  direction BT"])]
        var depth = 0
        for _ in 0..<(1 + below(statementCount)) {
            let indent = String(repeating: "  ", count: depth + 1)
            switch below(10) {
            case 0, 1, 2:
                lines.append(indent + pick(Self.names) + " " + pick(Self.cardinalities) + " " + pick(Self.names) + " : " + pick(Self.labels))
            case 3:
                let name = pick(Self.names)
                lines.append(indent + name + " " + pick(Self.cardinalities) + " " + name + " : " + pick(Self.labels))
            case 4, 5:
                var body = indent + pick(Self.names) + " {"
                for _ in 0..<below(5) { body += "\n" + indent + "  " + pick(Self.attributes) }
                lines.append(body + "\n" + indent + "}")
            case 6 where depth < 3:
                lines.append(indent + "subgraph " + pick(["Sales", "Stock", "g [Two words]", "g"]))
                depth += 1
            case 7 where depth > 0:
                depth -= 1
                lines.append(String(repeating: "  ", count: depth + 1) + "end")
            case 8:
                lines.append(indent + pick(["classDef hot fill:#f00", "class A hot", "style B fill:#0f0", "accTitle: T", "accDescr: D", "%% a comment",
                                            "direction TB"]))
            default:
                lines.append(indent + pick(Self.names))
            }
        }
        while depth > 0 {
            depth -= 1
            lines.append(String(repeating: "  ", count: depth + 1) + "end")
        }
        if below(5) == 0 { lines.insert("---\ntitle: " + pick(Self.labels) + "\n---", at: 0) }
        return lines.joined(separator: "\n")
    }
}
