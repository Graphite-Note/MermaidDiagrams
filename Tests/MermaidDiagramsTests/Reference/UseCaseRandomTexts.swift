/**
 * File: UseCaseRandomTexts.swift
 * ------------------------------
 * Layer: Tests
 * Description: Writes use case diagrams at random, the same for the same seed: actors of every type, use cases as ovals
 *              and boxes, system boundaries, notes, JSON tables, relationships of every arrow with labels, include and
 *              extend, loops, styles and classes, directions, spacing options and a title.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

/// Writes use case diagrams at random, the same for the same seed.
struct UseCaseRandomTexts {
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

    private static let names = ["Customer", "Login", "Checkout", "Admin", "Report", "Pay", "A", "B", "Track", "Support"]
    private static let shapes = ["", "", "(\"Place order\")", "[Generate report]", "(\"A longer use case name that wraps past the width\")", "(*Emphasis*)",
                                 "(\"Show #quot;quoted#quot; text\")", "(\"`**Formatted** label`\")", ":::hot", "@{ business: true }", " <<Core>>"]
    private static let actorKinds = ["", "@{ type: hollow }", "@{ type: awesome }", "@{ icon: \"fa:user\" }", "@{ business: true }"]
    private static let arrows = ["-->", "<--", "--", "--o", "o--", "--x", "x--", "--|>", "..>", "---->"]
    private static let labels = ["", "", " -- files R&D report", " -- \"`opens **form**`\"", " -- \"starts checkout\""]

    /// A use case diagram of up to `statementCount` statements: inside a boundary only its nodes, each relationship and
    /// statement outside it.
    mutating func text(statementCount: Int) -> String {
        var lines = [pick(["usecase-beta", "usecase-beta\ndirection LR", "usecase-beta\ndirection RL", "usecase-beta\ndirection BT"])]
        var isInBoundary = false
        var named: [String] = []
        func leaveBoundary() {
            if isInBoundary { lines.append("end") }
            isInBoundary = false
        }
        for _ in 0..<(1 + below(statementCount)) {
            let indent = isInBoundary ? "  " : ""
            switch below(12) {
            case 0, 1:
                let name = pick(Self.names)
                named.append(name)
                lines.append(indent + "actor " + name + pick(["", "(\"The actor\")"]) + pick(Self.actorKinds))
            case 2, 3:
                let name = pick(Self.names)
                named.append(name)
                lines.append(indent + name + pick(Self.shapes))
            case 4, 5, 6:
                leaveBoundary()
                let source = pick(Self.names)
                let target = pick(Self.names)
                named += [source, target]
                let label = pick(Self.labels)
                lines.append(source + (label.isEmpty ? " " + pick(Self.arrows) + " " : label + " --> ") + target)
            case 7:
                leaveBoundary()
                lines.append(pick(Self.names) + " ..> : " + pick(["include", "extend"]) + " " + pick(Self.names))
            case 8 where !isInBoundary:
                lines.append("systemBoundary " + pick(["Storefront", "\"Order system\"", "sb1[\"Payment service\"]@{ type: package }", "Account"]))
                isInBoundary = true
            case 9:
                leaveBoundary()
            case 10:
                leaveBoundary()
                lines.append(pick(["note for " + pick(Self.names) + " \"Starts the workflow\"", "json Payload@{ \"active\": true, \"count\": 3 }",
                                   "json Session@{ \"items\": [{ \"name\": \"Book\" }], \"address\": { \"city\": \"Oslo\" } }"]))
            default:
                leaveBoundary()
                lines.append(pick(["classDef hot stroke:#d33,stroke-width:3px", "%% a comment", "accTitle: T"]))
            }
        }
        leaveBoundary()
        if let styled = named.first, below(3) == 0 {
            lines.append(pick(["style " + styled + " fill:#ccf,stroke:#33c", "style " + styled + " font-size:18px", "classDef hot stroke:#d33",
                               "classDef hot fill:#fee\nclass " + styled + " hot"]))
        }
        if below(6) == 0 { lines.insert("---\nconfig:\n  usecase:\n    nodeSpacing: 60\n    rankSpacing: 50\n---", at: 0) }
        if below(5) == 0 { lines.insert("---\ntitle: Orders\n---", at: 0) }
        return lines.joined(separator: "\n")
    }
}
