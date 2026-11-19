/**
 * File: RailroadExpressionBudget.swift
 * ------------------------------------
 * Layer: Core
 * Description: Bounds what a railroad diagram's rules hold while they are read: rules and parts within the limits' node
 *              count, and no tree, nor bracket, nested deeper than the deepest allowed.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// A part of a rule being read, and how many levels deep its tree is.
struct RailroadPart {
    let expression: RailroadExpression
    let depth: Int
}

/// Bounds what a railroad diagram's rules hold: rules and parts together within the limits' node count, each counted
/// before it is made; no part whose tree is deeper than `RailroadExpression.maximumNestingDepth` (postfixes, repeats and
/// exceptions deepen a tree without brackets), and no bracket opened deeper than that (a group adds no level to the tree
/// but one to its reading). Each part is made through it, so a tree too deep is refused before it is made.
struct RailroadExpressionBudget {
    let limits: MermaidDiagramLimits
    private(set) var countedParts = 0

    init(limits: MermaidDiagramLimits) {
        self.limits = limits
    }

    /// Counts one more rule or part.
    mutating func count() throws(MermaidDiagramReadError) {
        guard countedParts < limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
        countedParts += 1
    }

    /// Refuses a bracket opened at `depth`, counted from 1 at a rule's definition, past the deepest allowed.
    func check(depth: Int) throws(MermaidDiagramReadError) {
        guard depth <= RailroadExpression.maximumNestingDepth else { throw .nestingTooDeep(limit: RailroadExpression.maximumNestingDepth) }
    }

    /// A terminal, a name or a special sequence.
    mutating func leaf(_ expression: RailroadExpression) throws(MermaidDiagramReadError) -> RailroadPart {
        try count()
        return RailroadPart(expression: expression, depth: 1)
    }

    mutating func optional(_ part: RailroadPart) throws(MermaidDiagramReadError) -> RailroadPart {
        try wrapping([part], .optional(part.expression))
    }

    mutating func repetition(_ part: RailroadPart, minimum: Double, maximum: Double) throws(MermaidDiagramReadError) -> RailroadPart {
        try wrapping([part], .repetition(part.expression, minimum: minimum, maximum: maximum))
    }

    /// The parts one after the other, or the only one of them.
    mutating func sequence(of parts: [RailroadPart]) throws(MermaidDiagramReadError) -> RailroadPart {
        guard parts.count != 1 else { return parts[0] }
        return try wrapping(parts, .sequence(parts.map(\.expression)))
    }

    /// A choice between the parts, or the only one of them.
    mutating func choice(of parts: [RailroadPart]) throws(MermaidDiagramReadError) -> RailroadPart {
        guard parts.count != 1 else { return parts[0] }
        return try wrapping(parts, .choice(parts.map(\.expression)))
    }

    /// EBNF's `base - exception`: a sequence of the base, the terminal `-` and the exception.
    mutating func exception(_ base: RailroadPart, _ exception: RailroadPart) throws(MermaidDiagramReadError) -> RailroadPart {
        let minus = try leaf(.terminal("-"))
        return try wrapping([base, minus, exception], .sequence([base.expression, minus.expression, exception.expression]))
    }

    /// `expression`, holding `parts`, counted and one level deeper than the deepest of them.
    private mutating func wrapping(_ parts: [RailroadPart], _ expression: RailroadExpression) throws(MermaidDiagramReadError) -> RailroadPart {
        let depth = (parts.map(\.depth).max() ?? 0) + 1
        try check(depth: depth)
        try count()
        return RailroadPart(expression: expression, depth: depth)
    }
}
