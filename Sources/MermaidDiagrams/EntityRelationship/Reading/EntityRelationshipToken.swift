/**
 * File: EntityRelationshipToken.swift
 * -----------------------------------
 * Layer: Core
 * Description: The tokens of an entity relationship diagram's statements as Mermaid's lexer reads them outside an
 *              entity's block, names and quoted text as byte ranges, and a name as a statement wrote it.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

/// A piece of an entity relationship diagram's statements, as Mermaid's lexer reads it outside an entity's `{ … }`.
enum EntityRelationshipToken: Equatable, Sendable {
    /// A name of an entity, the alias of one, or a relationship's label, without quotation marks, by its bytes.
    case name(MermaidTextRange, form: EntityRelationshipNameForm)
    /// Quoted text that is no name, without its quotation marks: empty, or holding `%`, `\` or a line break. Only a
    /// relationship's label may be one.
    case quotedText(MermaidTextRange)
    case cardinality(EntityRelationshipCardinality)
    case identification(EntityRelationshipIdentification)
    case keyword(EntityRelationshipKeyword)
    /// `accTitle: …`, with its text.
    case accessibilityTitle(String)
    /// `accDescr: …` or `accDescr { … }`, with its text.
    case accessibilityDescription(String)
    /// `direction TB`, `BT`, `LR` or `RL`, which takes the rest of its line.
    case direction(FlowchartDirection)
    /// `{`, which opens an entity's attributes.
    case openingBrace
    /// `[`, which opens an alias or a group's title.
    case openingBracket
    case closingBracket
    /// `:::`, before the names of an entity's classes.
    case classSeparator
    case colon
    case comma
    /// One or more line breaks.
    case lineBreak
    case endOfText
    /// A character the syntax gives no meaning here.
    case unexpectedCharacter
}

/// How a name was written.
enum EntityRelationshipNameForm: Equatable, Sendable {
    /// A run of letters, digits, `_`, `-`, `*`, `.` and characters beyond ASCII, not starting with a digit.
    case bare
    /// Text between quotation marks, read as Markdown when it is drawn.
    case quoted
    /// Digits, with or without a decimal part (`1`, `12`, `2.5`).
    case number
}

/// The words that start a statement, matched without regard to case.
enum EntityRelationshipKeyword: Equatable, Sendable {
    /// `erDiagram` written again, which no statement takes.
    case diagram
    /// `style`, which styles entities.
    case style
    /// `classDef`, which defines a class of styles.
    case classDefinition
    /// `class`, which gives entities classes.
    case classAssignment
    /// `subgraph`, which opens a group.
    case subgraph
    /// `end`, which closes a group.
    case end
}

/// A name as a statement wrote it: its bytes, which relationships know it by, and how it was written.
struct EntityRelationshipName: Equatable {
    let range: MermaidTextRange
    let form: EntityRelationshipNameForm

    /// The text drawn for it: a quoted name is read as Markdown (its emphasis markers dropped, `<br>` breaking it), a
    /// bare one or a number as it is.
    func label(in bytes: GraphDiagramBytes) -> DiagramLabel {
        // The text's bytes are a String's, so its range's bytes are well formed UTF-8, as the String it was read as.
        DiagramLabelDecoder.label(fromUTF8: UnsafeBufferPointer(rebasing: bytes.buffer[range.lowerBound..<range.upperBound]),
                                  form: form == .quoted ? .markdown : .plain)
    }
}
