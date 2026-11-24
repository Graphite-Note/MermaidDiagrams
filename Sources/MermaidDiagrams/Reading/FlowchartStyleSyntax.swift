/**
 * File: FlowchartStyleSyntax.swift
 * --------------------------------
 * Layer: Core
 * Description: Reads the statements that style a flowchart, their declarations included: on bytes when they are
 *              ASCII, through their characters otherwise.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 24/11/2026
 */

/// A statement that styles a flowchart, its declarations read when it is.
enum FlowchartStyleStatement: Equatable {
    /// `classDef name,other fill:#f9f,stroke:#333`: what the classes set.
    case classDefinition(names: [String], declarations: FlowchartStyleDeclarations)
    /// `class A,B name`: the nodes take the class.
    case classAssignment(identifiers: [String], className: String)
    /// `style A fill:#f9f,stroke:#333`: what the node sets for itself.
    case nodeStyle(identifier: String, declarations: FlowchartStyleDeclarations)
    /// `linkStyle 0,2 stroke:#f00` (the edges at those indexes, counted from 0 in the order written) or `linkStyle default stroke:#f00`
    /// (every edge, with `indices` nil).
    case linkStyle(indices: [Int]?, declarations: FlowchartStyleDeclarations)
}

/// What a statement's declarations set (`DiagramElementStyle.reading`), and whether one of them was not applied.
struct FlowchartStyleDeclarations: Equatable {
    let style: DiagramElementStyle
    let hasUnappliedDeclaration: Bool

    /// The declarations of a statement's text.
    init(_ text: String) {
        (style, hasUnappliedDeclaration) = DiagramElementStyle.reading(text)
    }

    /// The declarations of ASCII bytes, read on them.
    init(_ bytes: UnsafeBufferPointer<UInt8>) {
        (style, hasUnappliedDeclaration) = DiagramElementStyle.reading(bytes: bytes)
    }
}

/// Reads the text of the statements that style a flowchart (`classDef`, `class`, `style`, `linkStyle`), after their keyword.
enum FlowchartStyleSyntax {
    /// The statement `text` writes after `keyword`, or nil when it is not written as Mermaid writes it.
    static func statement(keyword: String, text: String) -> FlowchartStyleStatement? {
        let (head, rest) = split(text)
        guard !head.isEmpty else { return nil }
        switch keyword {
        case "classDef":
            let names = commaSeparated(head)
            return names.isEmpty ? nil : .classDefinition(names: names, declarations: FlowchartStyleDeclarations(rest))
        case "class":
            let identifiers = commaSeparated(head)
            let className = split(rest).head
            return identifiers.isEmpty || className.isEmpty ? nil : .classAssignment(identifiers: identifiers, className: className)
        case "style":
            return .nodeStyle(identifier: head, declarations: FlowchartStyleDeclarations(rest))
        case "linkStyle":
            if head == "default" { return .linkStyle(indices: nil, declarations: FlowchartStyleDeclarations(rest)) }
            let indices = commaSeparated(head).compactMap { index in Int(index) }
            return indices.count == commaSeparated(head).count ? .linkStyle(indices: indices, declarations: FlowchartStyleDeclarations(rest)) : nil
        default:
            return nil
        }
    }

    /// The first word of `text`, and what follows it.
    private static func split(_ text: String) -> (head: String, rest: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let space = trimmed.firstIndex(where: { character in character == " " || character == "\t" }) else { return (trimmed, "") }
        return (String(trimmed[..<space]), trimmed[space...].trimmingCharacters(in: .whitespaces))
    }

    private static func commaSeparated(_ text: String) -> [String] {
        text.split(separator: ",").map { part in part.trimmingCharacters(in: .whitespaces) }.filter { part in !part.isEmpty }
    }
}

extension FlowchartStyleSyntax {
    /// The statement the trimmed `range` of `bytes` writes after `keyword`, as `statement(keyword:text:)` reads its text:
    /// on the bytes when they are ASCII, whose characters they are, else through that text.
    static func statement(keyword: FlowchartStyleKeyword, in bytes: FlowchartBytes, range: Range<Int>) -> FlowchartStyleStatement? {
        guard !range.contains(where: { index in bytes.base[index] >= 0x80 }) else {
            return statement(keyword: keyword.text, text: bytes.string(from: range.lowerBound, to: range.upperBound))
        }
        let (head, rest) = split(range, in: bytes)
        guard !head.isEmpty else { return nil }
        func text(_ part: Range<Int>) -> String { bytes.string(from: part.lowerBound, to: part.upperBound) }
        // Read only for the statements that take them, after the head is read, as the statement's text read them.
        func declarations() -> FlowchartStyleDeclarations {
            FlowchartStyleDeclarations(UnsafeBufferPointer(start: bytes.base + rest.lowerBound, count: rest.count))
        }
        switch keyword {
        case .classDefinition:
            let names = commaSeparated(head, in: bytes).map(text)
            return names.isEmpty ? nil : .classDefinition(names: names, declarations: declarations())
        case .classAssignment:
            let identifiers = commaSeparated(head, in: bytes).map(text)
            let className = split(rest, in: bytes).head
            return identifiers.isEmpty || className.isEmpty ? nil : .classAssignment(identifiers: identifiers, className: text(className))
        case .style:
            return .nodeStyle(identifier: text(head), declarations: declarations())
        case .linkStyle:
            if head.count == 7, bytes.hasText("default", at: head.lowerBound) { return .linkStyle(indices: nil, declarations: declarations()) }
            let parts = commaSeparated(head, in: bytes)
            let indices = parts.compactMap { part in Int(text(part)) }
            return indices.count == parts.count ? .linkStyle(indices: indices, declarations: declarations()) : nil
        }
    }

    /// The first word of ASCII `range` (up to a space or a tab), and what follows it without spaces and tabs at its ends.
    private static func split(_ range: Range<Int>, in bytes: FlowchartBytes) -> (head: Range<Int>, rest: Range<Int>) {
        let trimmed = trimmedOfSpaces(range, in: bytes)
        guard let space = trimmed.first(where: { index in MermaidByte.isSpace(bytes.base[index]) }) else { return (trimmed, trimmed.upperBound..<trimmed.upperBound) }
        return (trimmed.lowerBound..<space, trimmedOfSpaces(space..<trimmed.upperBound, in: bytes))
    }

    /// The non-empty pieces of ASCII `range` between its commas, each without spaces and tabs at its ends.
    private static func commaSeparated(_ range: Range<Int>, in bytes: FlowchartBytes) -> [Range<Int>] {
        var pieces: [Range<Int>] = []
        var start = range.lowerBound
        for index in range.lowerBound...range.upperBound where index == range.upperBound || bytes.base[index] == MermaidByte.comma {
            let piece = trimmedOfSpaces(start..<index, in: bytes)
            if !piece.isEmpty { pieces.append(piece) }
            start = index + 1
        }
        return pieces
    }

    /// ASCII `range` without the spaces and tabs at its ends: Foundation's `whitespaces` there.
    private static func trimmedOfSpaces(_ range: Range<Int>, in bytes: FlowchartBytes) -> Range<Int> {
        var start = range.lowerBound
        var end = range.upperBound
        while start < end, MermaidByte.isSpace(bytes.base[start]) { start += 1 }
        while end > start, MermaidByte.isSpace(bytes.base[end - 1]) { end -= 1 }
        return start..<end
    }
}
