/**
 * File: ReferenceBlockStatement.swift
 * -----------------------------------
 * Layer: Tests
 * Description: MermaidDiagrams 0.7.0's BlockStatement, frozen as main 2a0cc65 had it: the reference the block reader is
 *              proven against (BlockReadingEquivalenceTests).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

@testable import MermaidDiagrams
/// A block as a statement writes it: Pele's `Block` before `setHierarchy`.
struct ReferenceBlockDraft: Equatable {
    var identifier: String
    /// The text in its brackets; nil without brackets.
    var label: String?
    var kind: BlockKind
    var directions: [String]
    var widthInColumns: Int
}

/// A link as a statement writes it, before its identifier is counted.
struct ReferenceBlockEdgeDraft: Equatable {
    /// The ends' identifiers joined by `-`, Pele's id before the count.
    let identifier: String
    let sourceIdentifier: String
    let targetIdentifier: String
    let label: String
    let link: String
}

/// One statement, as Pele's parser hands it to `setHierarchy`, a link statement already one item per block and edge.
enum ReferenceBlockStatement: Equatable {
    case block(ReferenceBlockDraft)
    case edge(ReferenceBlockEdgeDraft)
    /// `columns N`, or nil for `columns auto`.
    case columns(Int?)
    /// `space` or `space:N`: one block, made N cells wide.
    case space(identifier: String, width: Int)
    /// `block … end` or `block:id … end`: its header (nil for none), the identifier it was given at `end` (used without
    /// a header), and its statements by their place in the parser's list. A header that was a link statement leaves
    /// both nil: Pele spreads the list into an object, which keeps none of its blocks, and the hierarchy names it.
    case composite(header: ReferenceBlockDraft?, identifier: String?, childIndices: [Int])
    case classDefinition(name: String, declarations: String)
    case classAssignment(identifiers: String, className: String)
    case style(identifiers: String, declarations: String)
}

/// What Pele's database makes of the text the parser reads: a shape from its brackets, marks and lines from a link.
enum ReferenceBlockSyntaxValues {
    /// Pele's `typeStr2Type`: the kind the opening and closing brackets name; `unshaped` for any pair it does not know.
    static func kind(brackets: String?) -> BlockKind {
        guard let brackets else { return .unshaped }
        if brackets == "<[]>" { return .arrow }
        return shapesByBrackets[brackets].map(BlockKind.shape) ?? .unshaped
    }

    /// Pele's `edgeStrToEdgeData`: the mark the link's last character names.
    static func targetArrowhead(link: String) -> FlowchartArrowhead {
        switch link.trimmingCharacters(in: .whitespacesAndNewlines).last {
        case "x": .cross
        case "o": .circle
        case ">": .arrow
        default: .none
        }
    }

    /// Pele's `edgeStrToEdgeStartData`: the mark the link's first character names.
    static func sourceArrowhead(link: String) -> FlowchartArrowhead {
        switch link.trimmingCharacters(in: .whitespacesAndNewlines).first {
        case "x": .cross
        case "o": .circle
        case "<": .arrow
        default: .none
        }
    }

    static func isThick(link: String) -> Bool {
        link.contains("==")
    }

    static func isDotted(link: String) -> Bool {
        link.contains(".-")
    }

    /// A count written in digits, as JavaScript's `parseInt` reads it: past `Int`'s range `Int.max`, and past what a
    /// double holds (JavaScript's `Infinity`) nil.
    static func count(_ digits: String) -> Int? {
        guard let value = Double(digits), value.isFinite else { return nil }
        return value >= Double(Int.max) ? Int.max : Int(value)
    }

    private static let shapesByBrackets: [String: FlowchartNodeShape] = [
        "[]": .rectangle, "()": .roundedRectangle, "(())": .circle, ">]": .asymmetric, "{}": .diamond, "{{}}": .hexagon,
        "([])": .stadium, "[[]]": .subroutine, "[()]": .cylinder, "((()))": .doubleCircle, "[//]": .leanRight, "[\\\\]": .leanLeft,
        "[/\\]": .trapezoid, "[\\/]": .invertedTrapezoid,
    ]
}
