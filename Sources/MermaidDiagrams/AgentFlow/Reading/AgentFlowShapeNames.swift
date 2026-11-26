/**
 * File: AgentFlowShapeNames.swift
 * -------------------------------
 * Layer: Core
 * Description: Every shape name an agent flow's node can be given, numbered once for the process and found by its
 *              bytes without making a String, with what each means: its alias resolved, whether Mermaid knows it, the
 *              kind it gives a node and the shape the node is drawn in.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

/// The shape names a node's brackets give, the names its metadata may give once valid (Mermaid's flowchart's, the ones
/// it accepts without documenting them, `constructor`), and those an agent flow's graph draws, numbered from 0. Each
/// number's facts are worked out once from `AgentFlowShapes`, so a node's shape costs a lookup of its bytes.
enum AgentFlowShapeNames {
    static let names: [String] = {
        var names: [String] = []
        var seen: Set<String> = []
        func add(_ name: String) { if seen.insert(name).inserted { names.append(name) } }
        for name in ["square", "doublecircle", "round", "circle", "ellipse", "stadium", "subroutine", "cylinder", "diamond", "hexagon", "odd",
                     "rect", "lean_left", "lean_right", "inv_trapezoid", "trapezoid", "squareRect", "flowGroup", "collapsedGroup", "constructor"] {
            add(name)
        }
        for name in AgentFlowShapes.aliases.keys.sorted() { add(name) }
        for name in AgentFlowShapes.aliases.values.sorted() { add(name) }
        for (_, shapeNames) in FlowchartNodeShape.documentedNames { shapeNames.forEach(add) }
        for name in AgentFlowShapes.undocumentedShapeNames.sorted() { add(name) }
        for name in AgentFlowShapes.allowedShapes.sorted() { add(name) }
        for name in AgentFlowShapes.removedShapes.sorted() { add(name) }
        return names
    }()

    private static let numbersByName: [String: Int16] = Dictionary(uniqueKeysWithValues: names.enumerated().map { ($1, Int16($0)) })

    static func number(_ name: String) -> Int16 {
        numbersByName[name] ?? -1
    }

    static let square = number("square")
    static let squareRect = number("squareRect")
    static let flowGroup = number("flowGroup")
    static let collapsedGroup = number("collapsedGroup")
    static let roundedRect = number(AgentFlowShapes.defaultShape)

    /// The number of the name `bytes` spell, or -1: a probe of a table made once, its slots a power of two long and at
    /// most half full, each name compared by its bytes.
    static func number(of bytes: ArraySlice<UInt8>) -> Int16 {
        let mask = slots.count - 1
        var slot = Int(truncatingIfNeeded: hash(bytes)) & mask
        while case let entry = slots[slot], entry >= 0 {
            if nameBytes[Int(entry)].elementsEqual(bytes) { return entry }
            slot = (slot + 1) & mask
        }
        return -1
    }

    private static let nameBytes: [[UInt8]] = names.map { name in Array(name.utf8) }

    private static let slots: [Int16] = {
        var slotCount = 64
        while slotCount < 2 * names.count { slotCount *= 2 }
        var slots = [Int16](repeating: -1, count: slotCount)
        for (number, name) in nameBytes.enumerated() {
            var slot = Int(truncatingIfNeeded: hash(name[...])) & (slotCount - 1)
            while slots[slot] >= 0 { slot = (slot + 1) & (slotCount - 1) }
            slots[slot] = Int16(number)
        }
        return slots
    }()

    private static func hash(_ bytes: ArraySlice<UInt8>) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in bytes { hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
        return hash ^ (hash >> 29)
    }

    // MARK: - What each name means

    /// Each name with its alias resolved (`task` is `roundedRect`).
    static let resolved: [Int16] = names.map { name in number(AgentFlowShapes.resolvingAlias(name)) }

    /// Whether Mermaid's flowchart knows each name.
    static let isValid: [Bool] = names.map(AgentFlowShapes.isValidShape)

    /// The kind each name gives a node.
    static let kinds: [AgentFlowVertexKind] = names.map { name in AgentFlowShapes.kind(ofType: name) }

    /// The shape a node of each type has in the graph before it is reduced: its alias resolved, a square a `squareRect`
    /// (Pele's `buildAgentGraph`); a node of no type is a `squareRect`.
    static let graphShapes: [Int16] = names.map { name in
        let type = AgentFlowShapes.resolvingAlias(name)
        return number(type == "square" ? "squareRect" : type)
    }

    /// Each shape reduced to one an agent flow draws, and what was wrong with it (Pele's `normalizeShape`).
    static let normalizedShapes: [(shape: Int16, problem: AgentFlowDiagnostic.Identifier?)] = names.map { name in
        let normalized = AgentFlowShapes.normalized(name)
        return (number(normalized.shape), normalized.problem?.identifier)
    }

    /// The flowchart shape each graph shape is drawn in.
    static let drawnShapes: [FlowchartNodeShape] = names.map(AgentFlowShapes.drawnShape)
}
