/**
 * File: BlockStatement.swift
 * --------------------------
 * Layer: Core
 * Description: The statements a block diagram's parser reads, plain values over its bytes kept in one list with each
 *              composite naming its own by their place, and what Pele's database makes of a link's text and a shape's
 *              brackets, read from a String or from bytes alike.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

/// A block as a statement writes it: Pele's `Block` before `setHierarchy`, its texts runs of the parser's bytes.
struct BlockDraft: BitwiseCopyable {
    var identifier: BlockText
    /// The text in its brackets, meaningful when `hasLabel` (there are brackets).
    var label: BlockText
    var hasLabel: Bool
    var kind: BlockKindCode
    var shapeIndex: UInt8
    /// Its arrow's directions, a slice of the parser's texts.
    var directions: BlockSlice
    var widthInColumns: Int
}

/// A link as a statement writes it, before its identifier is counted: its ends' identifiers, its text and the link's
/// own characters with the white space after them.
struct BlockEdgeDraft: BitwiseCopyable {
    let source: BlockText
    let target: BlockText
    let label: BlockText
    let link: BlockText
}

/// The kinds of statement Pele's parser hands to `setHierarchy`.
enum BlockStatementKind: UInt8, BitwiseCopyable {
    case block, edge, columns, space, composite, classDefinition, classAssignment, style
}

/// One statement, as Pele's parser hands it to `setHierarchy`, a link statement already one item per block and edge,
/// as plain values: a block's draft (`block`, and a composite's header when it has one), an edge's, a number (`columns`'
/// count, `space`'s width, the number a composite without a header was named with at its `end`, -1 for none) and two
/// texts (`classDef`'s name and declarations, `class`'s blocks and class, `style`'s blocks and declarations).
struct BlockStatement: BitwiseCopyable {
    var kind: BlockStatementKind
    var draft: BlockDraft
    var edge: BlockEdgeDraft
    var number: Int = -1
    /// `columns` with a count (not `auto`), or a composite with a header.
    var flag = false
    var first = BlockText.empty
    var second = BlockText.empty
    /// A composite's statements, a slice of the parser's list of statement places.
    var children = BlockSlice.empty

    static let noDraft = BlockDraft(identifier: .empty, label: .empty, hasLabel: false, kind: .unshaped, shapeIndex: 0, directions: .empty,
                                    widthInColumns: 1)
    static let noEdge = BlockEdgeDraft(source: .empty, target: .empty, label: .empty, link: .empty)

    static func block(_ draft: BlockDraft) -> BlockStatement { BlockStatement(kind: .block, draft: draft, edge: noEdge) }
    static func edge(_ edge: BlockEdgeDraft) -> BlockStatement { BlockStatement(kind: .edge, draft: noDraft, edge: edge) }
    /// `columns N`, or nil for `columns auto`.
    static func columns(_ count: Int?) -> BlockStatement {
        BlockStatement(kind: .columns, draft: noDraft, edge: noEdge, number: count ?? -1, flag: count != nil)
    }

    /// `space` or `space:N`: one block named `id-<number>`, made `width` cells wide.
    static func space(identifierNumber: Int, width: Int) -> BlockStatement {
        var statement = BlockStatement(kind: .space, draft: noDraft, edge: noEdge, number: identifierNumber)
        statement.draft.widthInColumns = width
        return statement
    }

    /// `block … end` or `block:id … end`: its header (nil for none), the number it was named with at `end` (used
    /// without a header), and its statements. A header that was a link statement leaves both nil: Pele spreads the list
    /// into an object, which keeps none of its blocks, and the hierarchy names it.
    static func composite(header: BlockDraft?, identifierNumber: Int?, children: BlockSlice) -> BlockStatement {
        BlockStatement(kind: .composite, draft: header ?? noDraft, edge: noEdge, number: identifierNumber ?? -1, flag: header != nil, children: children)
    }

    static func texts(_ kind: BlockStatementKind, _ first: BlockText, _ second: BlockText) -> BlockStatement {
        BlockStatement(kind: kind, draft: noDraft, edge: noEdge, first: first, second: second)
    }
}

/// What Pele's database makes of the text the parser reads: a shape from its brackets, marks and lines from a link.
enum BlockSyntaxValues {
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

    /// `kind(brackets:)` of the opening and the closing bracket's bytes, without making their String.
    static func kind(opening: UnsafeBufferPointer<UInt8>, closing: UnsafeBufferPointer<UInt8>) -> (kind: BlockKindCode, shapeIndex: UInt8) {
        let total = opening.count + closing.count
        guard total >= 2, total <= 6 else { return (.unshaped, 0) }
        var packed: UInt64 = 0
        for byte in opening { packed = packed << 8 | UInt64(byte) }
        for byte in closing { packed = packed << 8 | UInt64(byte) }
        packed |= UInt64(total) << 56
        for entry in packedBrackets where entry.packed == packed { return entry.kind }
        return (.unshaped, 0)
    }

    /// The marks, the line and the dots a link's bytes give, as the String functions read them.
    static func linkValues(_ link: UnsafeBufferPointer<UInt8>) -> (source: FlowchartArrowhead, target: FlowchartArrowhead, isThick: Bool, isDotted: Bool) {
        let trimmed = BlockBytes.trimmed(link)
        var source = FlowchartArrowhead.none
        var target = FlowchartArrowhead.none
        if let first = trimmed.first {
            switch first {
            case UInt8(ascii: "x"): source = .cross
            case UInt8(ascii: "o"): source = .circle
            case UInt8(ascii: "<"): source = .arrow
            default: break
            }
        }
        if let last = trimmed.last {
            switch last {
            case UInt8(ascii: "x"): target = .cross
            case UInt8(ascii: "o"): target = .circle
            case UInt8(ascii: ">"): target = .arrow
            default: break
            }
        }
        var isThick = false
        var isDotted = false
        for index in link.indices.dropLast() {
            if link[index] == UInt8(ascii: "="), link[index + 1] == UInt8(ascii: "=") { isThick = true }
            if link[index] == UInt8(ascii: "."), link[index + 1] == UInt8(ascii: "-") { isDotted = true }
        }
        return (source, target, isThick, isDotted)
    }

    /// Each shape's brackets as bytes packed in one number, their count in the top byte.
    private static let packedBrackets: [(packed: UInt64, kind: (kind: BlockKindCode, shapeIndex: UInt8))] = {
        var entries: [(packed: UInt64, kind: (kind: BlockKindCode, shapeIndex: UInt8))] = []
        func pack(_ brackets: String) -> UInt64 {
            var packed: UInt64 = 0
            for byte in brackets.utf8 { packed = packed << 8 | UInt64(byte) }
            return packed | UInt64(brackets.utf8.count) << 56
        }
        entries.append((pack("<[]>"), (.arrow, 0)))
        for (brackets, shape) in shapesByBrackets {
            entries.append((pack(brackets), (.shape, UInt8(BlockModel.shapes.firstIndex(of: shape) ?? 0))))
        }
        return entries
    }()

    private static let shapesByBrackets: [String: FlowchartNodeShape] = [
        "[]": .rectangle, "()": .roundedRectangle, "(())": .circle, ">]": .asymmetric, "{}": .diamond, "{{}}": .hexagon,
        "([])": .stadium, "[[]]": .subroutine, "[()]": .cylinder, "((()))": .doubleCircle, "[//]": .leanRight, "[\\\\]": .leanLeft,
        "[/\\]": .trapezoid, "[\\/]": .invertedTrapezoid,
    ]
}
