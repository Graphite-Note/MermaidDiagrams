/**
 * File: EntityRelationshipAttributeSyntax.swift
 * ---------------------------------------------
 * Layer: Core
 * Description: Reads the attributes inside an entity's block on the text's borrowed bytes as Mermaid does: a type, a
 *              name, keys and a comment, each line of an error counted only when it is reported.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.3
 * Date: 26/11/2026
 */

/// Reads the attributes inside an entity's `{ … }` as Mermaid does: each a type and a name (`string? alias`), then
/// keys joined by commas (`PK, FK`) and a comment in quotation marks, with any whitespace between them, line breaks
/// included. A type or name is a word of letters, digits and `_ - * . [ ] ( ) ,` (starting with a letter, `_` or
/// `*`), a run that holds `~` (to the last `~` of its line), or any text in backticks. Each row is kept as the ranges of
/// what it writes (`EntityRelationshipAttributeRecord`).
struct EntityRelationshipAttributeSyntax {
    private var words: EntityRelationshipAttributeWords
    /// The entity's name, by its bytes, which an unclosed block is reported with.
    private let entity: MermaidTextRange
    /// Where the block opens, whose line an unclosed block names.
    private let opening: Int

    /// Reads from just after an entity's `{` through its `}`, appending its rows to `lists.attributes`, and leaves the
    /// cursor after the `}`.
    /// - Parameter entity: The entity's name, which an unclosed block is reported with.
    static func readBlock(_ cursor: inout GraphDiagramBytes, entity: MermaidTextRange,
                          into lists: inout EntityRelationshipReadingLists) throws(MermaidDiagramReadError) {
        var syntax = EntityRelationshipAttributeSyntax(words: EntityRelationshipAttributeWords(cursor: cursor), entity: entity, opening: cursor.position)
        try syntax.readAttributes(into: &lists)
        cursor = syntax.words.cursor
    }

    private mutating func readAttributes(into lists: inout EntityRelationshipReadingLists) throws(MermaidDiagramReadError) {
        // Room for a row in about every `bytesPerRow` bytes before the next `}`, so that most blocks grow no list.
        let cursor = words.cursor
        let blockEnd = UnsafeBufferPointer(rebasing: cursor.buffer[cursor.position...]).firstIndex(of: MermaidByte.closingBrace) ?? 0
        lists.attributes.reserveCapacity(lists.attributes.count + min(blockEnd / Self.bytesPerRow + 1, Self.mostReservedRows))
        var token = try words.next()
        while token != .closingBrace {
            guard case .word(var type) = token else { throw problem(at: token) }
            token = try words.next()
            var appendsQuestionMark = false
            if token == .questionMark {
                // A `?` written right after its type is a byte of the type's range; after whitespace, it is added to it.
                if words.tokenStart == type.upperBound { type = MermaidTextRange(start: type.lowerBound, end: type.upperBound + 1) } else {
                    appendsQuestionMark = true
                }
                token = try words.next()
            }
            guard case .word(let name) = token else { throw problem(at: token) }
            token = try words.next()
            lists.attributeKeys.removeAll(keepingCapacity: true)
            try readKeys(&token, into: &lists.attributeKeys)
            var comment = EntityRelationshipText.none
            var hasComment = false
            if case .comment(let text) = token {
                comment = EntityRelationshipText(range: text, kind: .markdown)
                hasComment = true
                token = try words.next()
            }
            let keyStart = EntityRelationshipModel.keyStart(of: lists.attributeKeys, spillingInto: &lists.keys)
            lists.attributes.append(EntityRelationshipAttributeRecord(type: type, name: name, comment: comment, hasComment: hasComment, isWritten: true,
                                                                      appendsQuestionMark: appendsQuestionMark, keyCount: Int32(lists.attributeKeys.count),
                                                                      keyStart: keyStart))
        }
    }

    /// `PK`, `PK, FK`, or none, starting at `token`, appended to `keys`; leaves `token` at what follows them.
    private mutating func readKeys(_ token: inout EntityRelationshipAttributeWords.Token,
                                   into keys: inout [EntityRelationshipAttributeKey]) throws(MermaidDiagramReadError) {
        guard case .key(let first) = token else { return }
        keys.append(first)
        token = try words.next()
        while token == .comma {
            token = try words.next()
            guard case .key(let key) = token else { throw problem(at: token) }
            keys.append(key)
            token = try words.next()
        }
    }

    /// About the bytes a row takes (`string name PK`), and the most rows made room for at once.
    private static let bytesPerRow = 14
    private static let mostReservedRows = 64

    /// A comment drawn as Markdown, as Mermaid draws it: entity codes and `<br>` read, emphasis markers dropped, and
    /// pairs of `~` read as angle brackets, as in a type.
    static func commentLabel(_ text: String) -> DiagramLabel {
        let label = DiagramLabelDecoder.label(from: text, form: .markdown)
        return DiagramLabel(lines: label.lines.map(EntityRelationshipGenericType.angleBracketed))
    }

    /// The text ending before the `}` is an unclosed block; anything else in the wrong place is no attribute.
    private func problem(at token: EntityRelationshipAttributeWords.Token) -> MermaidDiagramReadError {
        token == .endOfText ? .invalidSyntax(line: words.cursor.line(at: opening), problem: .unclosedAttributeBlock(entity: words.cursor.text(entity)))
                            : .invalidSyntax(line: words.cursor.line(at: words.tokenStart), problem: .expectedAttribute)
    }
}
