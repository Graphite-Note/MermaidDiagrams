/**
 * File: ClassDiagramRelationSyntax.swift
 * --------------------------------------
 * Layer: Core
 * Description: Reads a class diagram relation's operator on the text's borrowed bytes: the marks at its ends and its
 *              line.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

/// What a relation's operator says: the marks at its ends and its line (`<|--` is an inheritance mark at the source
/// on a solid line).
struct ClassDiagramRelationOperator: Equatable {
    let sourceEnd: ClassDiagramRelationEnd
    let targetEnd: ClassDiagramRelationEnd
    let line: ClassDiagramLineStyle
}

/// Reads a relation's operator: an optional mark, the line (`--` or `..`), an optional mark. A mark is `<|` or `|>`
/// (inheritance), `*` (composition), `o` (aggregation, when no identifier character follows it, so that `-- order`
/// names a class), `<` or `>` (arrow) or `()` (lollipop), on either side, as Mermaid's grammar allows.
enum ClassDiagramRelationSyntax {
    /// Reads an operator at the cursor and moves past it, or returns nil, without moving, when there is none.
    static func readOperator(_ cursor: inout GraphDiagramBytes) -> ClassDiagramRelationOperator? {
        var lookahead = cursor
        let sourceEnd = readEnd(&lookahead)
        lookahead.skipSpaces()
        guard let line = readLine(&lookahead) else { return nil }
        lookahead.skipSpaces()
        let targetEnd = readEnd(&lookahead)
        cursor = lookahead
        return ClassDiagramRelationOperator(sourceEnd: sourceEnd, targetEnd: targetEnd, line: line)
    }

    /// Whether a mark or a line starts at the cursor: what follows a class's name in a relation.
    static func startsOperator(_ cursor: GraphDiagramBytes) -> Bool {
        var lookahead = cursor
        return readEnd(&lookahead) != .none || readLine(&lookahead) != nil
    }

    private static func readLine(_ cursor: inout GraphDiagramBytes) -> ClassDiagramLineStyle? {
        if cursor.isAt(MermaidByte.hyphen, MermaidByte.hyphen) {
            cursor.advance(by: 2)
            return .solid
        }
        if cursor.isAt(MermaidByte.period, MermaidByte.period) {
            cursor.advance(by: 2)
            return .dashed
        }
        return nil
    }

    private static func readEnd(_ cursor: inout GraphDiagramBytes) -> ClassDiagramRelationEnd {
        // The marks written with two characters, tried before the one-character `<`.
        if cursor.isAt(MermaidByte.lessThan, MermaidByte.verticalBar) || cursor.isAt(MermaidByte.verticalBar, MermaidByte.greaterThan) {
            cursor.advance(by: 2)
            return .inheritance
        }
        if cursor.isAt(openingParenthesis, closingParenthesis) {
            cursor.advance(by: 2)
            return .lollipop
        }
        guard let byte = cursor.peek() else { return .none }
        switch byte {
        case MermaidByte.lessThan, MermaidByte.greaterThan:
            cursor.advance()
            return .arrow
        case asterisk:
            cursor.advance()
            return .composition
        case MermaidByte.letterO:
            if let next = cursor.peek(1), MermaidByte.isIdentifierByte(next) { return .none }
            cursor.advance()
            return .aggregation
        default:
            return .none
        }
    }

    private static let asterisk = UInt8(ascii: "*")
    private static let openingParenthesis = UInt8(ascii: "(")
    private static let closingParenthesis = UInt8(ascii: ")")
}
