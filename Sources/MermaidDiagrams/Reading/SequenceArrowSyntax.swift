/**
 * File: SequenceArrowSyntax.swift
 * -------------------------------
 * Layer: Core
 * Description: Reads a sequence message's arrow as Mermaid's lexer spells them, the half arrows and their reverses
 *              included.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

/// Reads a message's arrow, as Mermaid's sequence grammar spells them.
enum SequenceArrowSyntax {
    /// Reads the arrow at the cursor and moves past it: `->`, `-->`, `->>`, `-->>`, `-x`, `--x`, `-)`, `--)`, `<<->>`,
    /// `<<-->>`, Mermaid 12's half arrows (`-|\`, `-|/`, `-\\`, `-//` and their dotted forms) and their reverses (`/|-`,
    /// `\|-`, `//-`, `\\-`, dotted ending `--`). Nil when none starts there.
    static func readArrow(_ cursor: inout MermaidTextCursor) -> SequenceArrow? {
        guard let (found, length) = arrowAt(cursor) else { return nil }
        cursor.advance(by: length)
        return found
    }

    private static func arrowAt(_ cursor: MermaidTextCursor) -> (SequenceArrow, Int)? {
        if cursor.hasPrefix(twoWaySolid) { return (SequenceArrow(stroke: .solid, head: .arrow, pointsBothWays: true), twoWaySolid.count) }
        if cursor.hasPrefix(twoWayDotted) { return (SequenceArrow(stroke: .dotted, head: .arrow, pointsBothWays: true), twoWayDotted.count) }
        guard let first = cursor.peek() else { return nil }
        if first == SequenceTextSyntax.slash || first == SequenceTextSyntax.backslash { return reverseHalfArrow(cursor) }
        guard first == MermaidByte.hyphen else { return nil }
        let isDotted = cursor.peek(1) == MermaidByte.hyphen
        let headOffset = isDotted ? 2 : 1
        let stroke: SequenceLineStroke = isDotted ? .dotted : .solid
        guard let headByte = cursor.peek(headOffset) else { return nil }
        let following = cursor.peek(headOffset + 1)
        switch headByte {
        case MermaidByte.greaterThan:
            if following == MermaidByte.greaterThan { return (SequenceArrow(stroke: stroke, head: .arrow), headOffset + 2) }
            return (SequenceArrow(stroke: stroke, head: .none), headOffset + 1)
        case MermaidByte.letterX, UInt8(ascii: "X"): return (SequenceArrow(stroke: stroke, head: .cross), headOffset + 1)
        case SequenceTextSyntax.closingParenthesis: return (SequenceArrow(stroke: stroke, head: .open), headOffset + 1)
        case MermaidByte.verticalBar where following == SequenceTextSyntax.backslash || following == SequenceTextSyntax.slash:
            let side: SequenceHalfHeadSide = following == SequenceTextSyntax.backslash ? .top : .bottom
            return (SequenceArrow(stroke: stroke, head: .solidHalf, halfHeadSide: side), headOffset + 2)
        case SequenceTextSyntax.backslash where following == SequenceTextSyntax.backslash, SequenceTextSyntax.slash where following == SequenceTextSyntax.slash:
            let side: SequenceHalfHeadSide = headByte == SequenceTextSyntax.backslash ? .top : .bottom
            return (SequenceArrow(stroke: stroke, head: .stickHalf, halfHeadSide: side), headOffset + 2)
        default: return nil
        }
    }

    /// `/|-`, `\|-`, `//-`, `\\-` and their dotted forms ending `--`: a half head at the source. A slash puts it on the
    /// top, a backslash on the bottom; a bar makes it solid, a doubled stroke a stick.
    private static func reverseHalfArrow(_ cursor: MermaidTextCursor) -> (SequenceArrow, Int)? {
        guard let first = cursor.peek(), let second = cursor.peek(1), second == MermaidByte.verticalBar || second == first,
              cursor.peek(2) == MermaidByte.hyphen else { return nil }
        let isDotted = cursor.peek(3) == MermaidByte.hyphen
        let arrow = SequenceArrow(stroke: isDotted ? .dotted : .solid, head: second == MermaidByte.verticalBar ? .solidHalf : .stickHalf,
                                  pointsBackwards: true, halfHeadSide: first == SequenceTextSyntax.slash ? .top : .bottom)
        return (arrow, isDotted ? 4 : 3)
    }

    private static let twoWaySolid = Array("<<->>".utf8)
    private static let twoWayDotted = Array("<<-->>".utf8)
}
