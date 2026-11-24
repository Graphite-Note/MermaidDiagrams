/**
 * File: FlowchartRandomTexts.swift
 * --------------------------------
 * Layer: Tests
 * Description: Flowcharts written at random from a small pool of names and statements, so that the equivalence tests
 *              meet what the corpora rarely hold: a name in a group and the group around it, groups ended again under
 *              one identifier, groups named as nodes, loops of groups, styles before and after their nodes.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

/// Writes flowcharts at random, the same for the same seed.
struct FlowchartRandomTexts {
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

    /// Names compared by their bytes and by their characters alike: no two are canonically equivalent (`K` and the Kelvin
    /// sign are, and are two nodes for Pele and the redesigned reader, one for 0.7.0's).
    private static let names = ["A", "B", "C", "D", "g1", "g2", "subGraph0", "subGraph1", "x-y", "é", "K", "n_1", "default", "v"]
    private static let shapes = ["", "", "", "[t]", "(r)", "{d}", "[\"q\"]", "((c))", "[/l/]", "[\"a\"b]", "[ <b>m</b> ]", "@{ shape: circle }",
                                 "@{ label: \"L\", icon: \"fa:x\" }", "@{ view: collapsed }", "@{ shape: lin-cyl, w: 40 }", ":::k",
                                 "[\u{3000}w\u{00A0}]", "[\u{2028}y]", "[中文]", "[\"\u{3000}q\"]", "[ \u{0085}z ]", "@{ label: \"中\" }"]
    private static let links = ["-->", "---", "-.->", "==>", "--o", "<-->", "~~~", "-- t -->", "-->|e|", "-. u .->", "e1@-->", "== w ==>", "-- 中 -->", "-- \"\u{00A0}s\" -->"]

    /// A flowchart of up to `statementCount` statements.
    mutating func text(statementCount: Int) -> String {
        var lines = [pick(["flowchart TD", "graph LR", "flowchart", "flowchart RL"])]
        var depth = 0
        for _ in 0..<(1 + below(statementCount)) {
            let indent = String(repeating: "  ", count: depth)
            switch below(10) {
            case 0, 1:
                lines.append(indent + pick(["subgraph ", "subgraph ", "subgraph"]) + pick(Self.names + ["\"T t\"", "two words", "中 文", "\"`m`\"", "\u{00A0}u", "s[Title]", "g1 [\"x\"]", ""]))
                depth += 1
            case 2 where depth > 0:
                lines.append(indent + "end")
                depth -= 1
            case 3:
                lines.append(indent + pick(["direction LR", "direction TB", "direction XX", "style A fill:#f9f", "class B,C k", "classDef k stroke:#000",
                                            "linkStyle 0 stroke:#f00", "linkStyle default stroke-width:2px", "style g1 fill:#eee", "click A f",
                                            "accTitle: T", "style Q fill:#0f0"]))
            case 4: lines.append(indent + pick(Self.names) + pick(Self.shapes))
            default:
                var chain = pick(Self.names) + pick(Self.shapes)
                for _ in 0...below(3) {
                    chain += " " + pick(Self.links) + " " + pick(Self.names) + pick(Self.shapes)
                    if below(4) == 0 { chain += " & " + pick(Self.names) }
                }
                lines.append(indent + chain)
            }
        }
        if below(3) > 0 { lines.append(contentsOf: repeatElement("end", count: depth)) }
        return lines.joined(separator: below(8) == 0 ? ";" : "\n")
    }
}
