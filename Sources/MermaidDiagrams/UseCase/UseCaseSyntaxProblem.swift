/**
 * File: UseCaseSyntaxProblem.swift
 * --------------------------------
 * Layer: Core
 * Description: Why a use case diagram's text was not read: a character its lexer reads no token from, a token its
 *              grammar does not take, JSON that is not JSON, or statements that contradict each other.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// What broke a use case diagram, as Pele's lexer, parser and `resolveUsecase` find it. The line is the error's.
public enum UseCaseSyntaxProblem: Equatable, Sendable {
    /// A character no token starts with: a plain string unclosed on its line, or `<<` at the end of a line.
    case unexpectedCharacter
    /// A token the grammar does not take where it stands, by its text, and what the grammar expected there.
    case unexpectedToken(found: String, expected: UseCaseExpectedSyntax)
    /// A `json` statement's object is not JSON: the column of the first character that is not.
    case invalidJSON(column: Int)
    /// A `json` statement's value is not an object.
    case jsonRootNotObject
    /// Statements the grammar accepts that contradict each other or name what they cannot.
    case contradiction(UseCaseContradiction)
}

/// What the grammar expected where a use case diagram's syntax broke.
public enum UseCaseExpectedSyntax: Equatable, Sendable {
    /// A statement: a declaration, a relationship, a boundary, a note, JSON, a class, a style, a direction or an
    /// accessibility line.
    case statement
    /// A line break, or the end of the text.
    case lineEnd
    /// The end of the text, after the statements.
    case end
    /// A label: a string, or unquoted text.
    case label
    /// An identifier or a string, which names an element.
    case name
    /// A metadata property's key, or its value (an identifier, a string, `true` or `false`).
    case metadataKey
    case metadataValue
    /// `include` or `extend` after `..> :`.
    case includeOrExtend
    /// `TB`, `TD`, `BT`, `LR` or `RL`.
    case direction
    /// A relationship's operator.
    case relationshipOperator
    /// The operator that closes a label after `--`: `-->`, `--`, `--o` or `--x`.
    case labelClosingOperator
    /// A style's property, or the value after its colon.
    case styleProperty
    case styleValue
    /// One token, by Mermaid's name of it (`RPAREN`).
    case token(String)
}

/// The kinds of things an id names in a use case diagram.
public enum UseCaseSymbolKind: String, Equatable, Sendable {
    case actor
    case useCase = "usecase"
    case boundary
    case json
    case edge
}

/// Statements that contradict each other or name what they cannot, as Mermaid's `UsecaseModelBuilder` refuses them.
public enum UseCaseContradiction: Equatable, Sendable {
    /// One id declared as two kinds of things.
    case declaredAsTwoKinds(identifier: String, first: UseCaseSymbolKind, second: UseCaseSymbolKind)
    /// An id made from a label (`"Reset password"`) that another declaration also makes or writes.
    case generatedIdentifierCollision(identifier: String)
    /// A JSON table's or a relationship's id written a second time.
    case declaredMoreThanOnce(identifier: String, first: UseCaseSymbolKind, second: UseCaseSymbolKind)
    /// Two declarations of an actor that give one metadata key different values.
    case conflictingActorMetadata(actor: String, key: String)
    case conflictingBusinessMetadata(useCase: String)
    /// A metadata key the target does not take, or a value of the wrong kind.
    case invalidMetadataProperty(target: String, key: String, kind: UseCaseSymbolKind)
    case conflictingLabels(identifier: String)
    case conflictingShapes(useCase: String)
    case inMoreThanOneBoundary(identifier: String)
    case conflictingStereotypes(identifier: String)
    case conflictingBoundaryTitles(boundary: String)
    /// A relationship's end with `:::` that does not declare its element.
    case classedEndpointNotDeclared(identifier: String)
    /// A `class` or `style` statement whose target is not an element, a boundary, a JSON table or a relationship.
    case unresolvedStyleTarget(identifier: String)
    /// A relationship whose source or target is a boundary or an explicit relationship id.
    case relationshipEndpointKind(identifier: String, isSource: Bool, kind: UseCaseSymbolKind)
    /// `include` or `extend` between ends that are not both use cases.
    case relationshipNeedsUseCases(UseCaseRelationshipType)
    /// A generalization that is not actor to actor or use case to use case.
    case generalizationEndpoints
    /// A relationship to or from JSON with a circle or a cross.
    case jsonRelationshipMarks(source: String, target: String)
    /// A metadata statement for an id nothing declares, and the kind its keys imply, if one.
    case unresolvedMetadataTarget(identifier: String, impliedKind: UseCaseSymbolKind?)
    case iconWithActorType(actor: String, type: UseCaseActorType)
    /// A business actor drawn with an icon or as `awesome`.
    case businessActorGeometry(actor: String)
    case rectangularBusinessUseCase(identifier: String)
    case unresolvedNoteTarget(identifier: String)
    /// A note for something other than an actor or a use case.
    case noteTargetKind(identifier: String, kind: UseCaseSymbolKind)
}
