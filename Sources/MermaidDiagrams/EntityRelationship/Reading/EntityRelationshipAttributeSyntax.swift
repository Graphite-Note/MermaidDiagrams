/**
 * File: EntityRelationshipAttributeSyntax.swift
 * ---------------------------------------------
 * Layer: Core
 * Description: Reads the attributes inside an entity's block on the text's borrowed bytes as Mermaid does: a type, a
 *              name, keys and a comment, each line of an error counted only when it is reported.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

/// Reads the attributes inside an entity's `{ … }` as Mermaid does: each a type and a name (`string? alias`), then
/// keys joined by commas (`PK, FK`) and a comment in quotation marks, with any whitespace between them, line breaks
/// included. A type or name is a word of letters, digits and `_ - * . [ ] ( ) ,` (starting with a letter, `_` or
/// `*`), a run that holds `~` (to the last `~` of its line), or any text in backticks.
struct EntityRelationshipAttributeSyntax {
    private var words: EntityRelationshipAttributeWords
    /// The entity's name, by its bytes, which an unclosed block is reported with.
    private let entity: MermaidTextRange
    /// Where the block opens, whose line an unclosed block names.
    private let opening: Int

    /// Reads from just after an entity's `{` through its `}`, and leaves the cursor after the `}`.
    /// - Parameter entity: The entity's name, which an unclosed block is reported with.
    static func readBlock(_ cursor: inout GraphDiagramBytes, entity: MermaidTextRange) throws(MermaidDiagramReadError) -> [EntityRelationshipAttribute] {
        var syntax = EntityRelationshipAttributeSyntax(words: EntityRelationshipAttributeWords(cursor: cursor), entity: entity, opening: cursor.position)
        let attributes = try syntax.readAttributes()
        cursor = syntax.words.cursor
        return attributes
    }

    private mutating func readAttributes() throws(MermaidDiagramReadError) -> [EntityRelationshipAttribute] {
        var attributes: [EntityRelationshipAttribute] = []
        // Room for a row in about every `bytesPerRow` bytes before the next `}`, so that most blocks grow no list.
        let cursor = words.cursor
        let blockEnd = UnsafeBufferPointer(rebasing: cursor.buffer[cursor.position...]).firstIndex(of: MermaidByte.closingBrace) ?? 0
        attributes.reserveCapacity(min(blockEnd / Self.bytesPerRow + 1, Self.mostReservedRows))
        var token = try words.next()
        while token != .closingBrace {
            guard case .word(let typeRange) = token else { throw problem(at: token) }
            var type = words.cursor.text(typeRange)
            token = try words.next()
            if token == .questionMark {
                type += "?"
                token = try words.next()
            }
            guard case .word(let nameRange) = token else { throw problem(at: token) }
            let name = words.cursor.text(nameRange)
            token = try words.next()
            let keys = try readKeys(&token)
            var comment: DiagramLabel?
            if case .comment(let text) = token {
                comment = Self.commentLabel(words.cursor.text(text))
                token = try words.next()
            }
            attributes.append(EntityRelationshipAttribute(type: EntityRelationshipGenericType.angleBracketed(type),
                                                          name: EntityRelationshipGenericType.angleBracketed(name), keys: keys, comment: comment))
        }
        return attributes
    }

    /// `PK`, `PK, FK`, or none, starting at `token`; leaves `token` at what follows them.
    private mutating func readKeys(_ token: inout EntityRelationshipAttributeWords.Token) throws(MermaidDiagramReadError) -> [EntityRelationshipAttributeKey] {
        guard case .key(let first) = token else { return [] }
        var keys = [first]
        token = try words.next()
        while token == .comma {
            token = try words.next()
            guard case .key(let key) = token else { throw problem(at: token) }
            keys.append(key)
            token = try words.next()
        }
        return keys
    }

    /// About the bytes a row takes (`string name PK`), and the most rows made room for at once.
    private static let bytesPerRow = 14
    private static let mostReservedRows = 64

    /// A comment drawn as Markdown, as Mermaid draws it: entity codes and `<br>` read, emphasis markers dropped, and
    /// pairs of `~` read as angle brackets, as in a type.
    private static func commentLabel(_ text: String) -> DiagramLabel {
        let label = DiagramLabelDecoder.label(from: text, form: .markdown)
        return DiagramLabel(lines: label.lines.map(EntityRelationshipGenericType.angleBracketed))
    }

    /// The text ending before the `}` is an unclosed block; anything else in the wrong place is no attribute.
    private func problem(at token: EntityRelationshipAttributeWords.Token) -> MermaidDiagramReadError {
        token == .endOfText ? .invalidSyntax(line: words.cursor.line(at: opening), problem: .unclosedAttributeBlock(entity: words.cursor.text(entity)))
                            : .invalidSyntax(line: words.cursor.line(at: words.tokenStart), problem: .expectedAttribute)
    }
}
