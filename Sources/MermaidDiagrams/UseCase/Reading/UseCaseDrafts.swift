/**
 * File: UseCaseDrafts.swift
 * -------------------------
 * Layer: Core
 * Description: What the use case parser read, in source order, before any of it is resolved into a diagram, as Pele's
 *              db.ts drafts hold it: flat records of byte ranges into the text and of interned names, their lists
 *              kept in shared pools.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

/// A stretch of one of the drafts' or the model's pools: where it starts and how many it holds.
struct UseCaseListSpan: Equatable, Sendable {
    var start: Int32
    var count: Int32

    static let empty = UseCaseListSpan(start: 0, count: 0)

    var isEmpty: Bool { count == 0 }
    var range: Range<Int> { Int(start)..<Int(start + count) }
}

/// A metadata property's value: text (an identifier or a string) or `true` and `false`.
struct UseCaseMetadataValue: Equatable {
    enum Kind: UInt8 {
        case text, boolean
    }

    var kind: Kind
    /// The text of a text value.
    var text: MermaidTextRange
    var boolean: Bool
}

/// `key: value` in `@{ … }`, and where its key starts, which an error about it names.
struct UseCaseDraftProperty {
    var key: MermaidTextRange
    var value: UseCaseMetadataValue
    var keyStart: Int32
}

/// What every mention of an id carries: its name, where it is, and whether the id was made from a label
/// (`"Reset password"`).
struct UseCaseDraftName {
    var name: Int32
    var label: UseCaseLabelText
    var start: Int32
    var isGenerated: Bool
}

enum UseCaseElementKind: UInt8 {
    case actor
    case useCase
}

/// A declaration of an actor or a use case: `actor A`, `Login(Sign in)`, or an end of a relationship that says
/// something about it.
struct UseCaseDraftElement {
    var name: UseCaseDraftName
    var kind: UseCaseElementKind
    /// The boundary it is declared in, by its place among the drafts' boundaries, or -1.
    var parent: Int32
    var shape: UseCaseShape?
    /// Its properties in the drafts' pool, when it has metadata.
    var metadata: UseCaseListSpan
    var hasMetadata: Bool
    var stereotype: MermaidTextRange
    var hasStereotype: Bool
    /// Its classes' names in the drafts' pool.
    var classes: UseCaseListSpan
}

struct UseCaseDraftBoundary {
    var name: UseCaseDraftName
    var classes: UseCaseListSpan
}

struct UseCaseDraftJSON {
    var name: Int32
    var start: Int32
    /// Its value, by its place among the drafts' values.
    var value: Int32
    var classes: UseCaseListSpan
}

/// An end of a relationship: whether this mention declares the element, and whether it carries `:::`.
struct UseCaseDraftEndpoint {
    var name: UseCaseDraftName
    var declares: Bool
    var isClassed: Bool
}

struct UseCaseDraftRelationship {
    var source: UseCaseDraftEndpoint
    var target: UseCaseDraftEndpoint
    var start: Int32
    /// Its explicit id's name, or -1, and where the id is written.
    var identifier: Int32
    var identifierStart: Int32
    var type: UseCaseRelationshipType
    var arrow: UseCaseArrow
    var label: UseCaseLabelText
    var hasLabel: Bool
    var minimumLength: Int32
}

struct UseCaseDraftNote {
    var target: Int32
    var start: Int32
    var label: UseCaseLabelText
}

/// `Id@{ … }` for a name.
struct UseCaseDraftMetadata {
    var target: Int32
    var start: Int32
    var properties: UseCaseListSpan
}

/// `class A, B c, d`: its targets and its classes, in the drafts' pools.
struct UseCaseDraftClassAssignment {
    var targets: UseCaseListSpan
    var classes: UseCaseListSpan
}

/// `style A …`.
struct UseCaseDraftStyle {
    var target: Int32
    var start: Int32
    var styles: UseCaseListSpan
}

/// `classDef a, b …`: its names in the drafts' name pool, its styles in their pool.
struct UseCaseDraftClassDefinition {
    var names: UseCaseListSpan
    var styles: UseCaseListSpan
}

/// A `class` statement's target: its name and where it is written.
struct UseCaseDraftTarget {
    var name: Int32
    var start: Int32
}

/// Everything the parser read, in source order, before any of it is resolved (Pele's `Drafts`).
struct UseCaseDrafts {
    var elements: [UseCaseDraftElement] = []
    var boundaries: [UseCaseDraftBoundary] = []
    var jsons: [UseCaseDraftJSON] = []
    var jsonValues: [UseCaseJSONValue] = []
    var relationships: [UseCaseDraftRelationship] = []
    var notes: [UseCaseDraftNote] = []
    var metadata: [UseCaseDraftMetadata] = []
    var classAssignments: [UseCaseDraftClassAssignment] = []
    var styles: [UseCaseDraftStyle] = []
    var classDefinitions: [UseCaseDraftClassDefinition] = []
    /// The pools the records' spans point into: names (classes, class definitions' names), targets of `class`
    /// statements, metadata properties, and styles as written.
    var names: [Int32] = []
    var targets: [UseCaseDraftTarget] = []
    var properties: [UseCaseDraftProperty] = []
    var styleTexts: [MermaidTextRange] = []
    var direction: UseCaseDirection?
    var accessibilityTitle = ""
    var accessibilityDescription = ""

    /// The statements read that make a node: each is at most one node however often its id is mentioned again.
    var nodeStatementCount: Int { elements.count + boundaries.count + jsons.count + notes.count }

    /// `names` added to the name pool, and where.
    mutating func addNames(_ added: [Int32]) -> UseCaseListSpan {
        let start = names.count
        names.append(contentsOf: added)
        return UseCaseListSpan(start: Int32(start), count: Int32(added.count))
    }
}
