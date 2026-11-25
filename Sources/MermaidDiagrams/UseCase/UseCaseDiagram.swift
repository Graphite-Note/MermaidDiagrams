/**
 * File: UseCaseDiagram.swift
 * --------------------------
 * Layer: Core
 * Description: A Mermaid use case diagram (`usecase-beta`) as Pele's model holds it once read, kept flat: records of
 *              byte ranges into its text and of interned names, their lists in shared pools, in the order Pele puts
 *              them; its actors, use cases and the rest are made as values only when read.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

/// A Mermaid use case diagram as Pele's `resolveUsecase` holds it: every actor and use case in the order its id is first
/// mentioned, the system boundaries and JSON tables likewise, the relationships and notes in the order written. It
/// holds its text's bytes and records of ranges into them; `actors`, `useCases` and the other lists are made from the
/// records each time they are read, so a reader that only lays the diagram out makes none of them. Two diagrams are
/// equal when what they give to read is.
public struct UseCaseDiagram: Equatable, Sendable {
    /// The text read and the bytes the reading made, which the records' ranges index.
    var text = UseCaseBytes(text: [], removedLineBreaks: [])
    /// Where each interned name's bytes are, by its number.
    var nameRanges: [MermaidTextRange] = []
    var actorRecords: [UseCaseElementRecord] = []
    var useCaseRecords: [UseCaseElementRecord] = []
    var boundaryRecords: [UseCaseBoundaryRecord] = []
    var relationshipRecords: [UseCaseRelationshipRecord] = []
    var noteRecords: [UseCaseNoteRecord] = []
    var jsonRecords: [UseCaseJSONRecord] = []
    var classDefinitionRecords: [UseCaseClassDefinitionRecord] = []
    var jsonValues: [UseCaseJSONValue] = []
    /// The pools the records' spans point into: names (classes, a boundary's members), and styles as written.
    var namePool: [Int32] = []
    var stylePool: [MermaidTextRange] = []

    /// `direction …`, left to right unless written.
    public internal(set) var direction: UseCaseDirection = .leftToRight
    /// The front matter's `title:`; a use case diagram has no title statement.
    public var title: String?
    /// `accTitle: …`, empty unless written.
    public internal(set) var accessibilityTitle = ""
    /// `accDescr: …` or `accDescr { … }`, the indentation of its lines dropped, empty unless written.
    public internal(set) var accessibilityDescription = ""
    /// The options `usecase.nodeSpacing` and `usecase.rankSpacing` of the front matter or a directive, when numbers above
    /// zero (cut to 2,000): the gap between nodes of a rank and between ranks.
    public internal(set) var nodeSpacing: Double?
    public internal(set) var rankSpacing: Double?

    /// The diagram turned to run down, when it runs across (left to right or right to left), as Pele draws it for a
    /// narrow column; nil when it runs down already.
    public var turnedToRunDown: UseCaseDiagram? {
        guard direction == .leftToRight || direction == .rightToLeft else { return nil }
        var turned = self
        turned.direction = .topToBottom
        return turned
    }

    /// Whether it has no actor, use case, JSON table or boundary: nothing a reader would see drawn.
    public var isEmpty: Bool { actorRecords.isEmpty && useCaseRecords.isEmpty && jsonRecords.isEmpty && boundaryRecords.isEmpty }

    public static func == (first: UseCaseDiagram, second: UseCaseDiagram) -> Bool {
        first.direction == second.direction && first.title == second.title && first.accessibilityTitle == second.accessibilityTitle
            && first.accessibilityDescription == second.accessibilityDescription && first.nodeSpacing == second.nodeSpacing
            && first.rankSpacing == second.rankSpacing && first.actors == second.actors && first.useCases == second.useCases
            && first.systemBoundaries == second.systemBoundaries && first.relationships == second.relationships && first.notes == second.notes
            && first.jsonNodes == second.jsonNodes && first.classDefinitions == second.classDefinitions
    }
}

/// A label of the model: where its text is, and how it is read.
struct UseCaseLabelText: Equatable, Sendable {
    var text: MermaidTextRange
    var type: UseCaseLabelType
}

/// An actor or a use case.
struct UseCaseElementRecord: Equatable, Sendable {
    var name: Int32
    var label: UseCaseLabelText
    /// An actor's type (`icon` when it has an icon); a use case's is `normal`.
    var actorType: UseCaseActorType
    /// A use case's outline; an actor's is `ellipse`.
    var shape: UseCaseShape
    var icon: MermaidTextRange
    var hasIcon: Bool
    var isBusiness: Bool
    var stereotype: MermaidTextRange
    var hasStereotype: Bool
    /// The name of the boundary it is declared in, or -1.
    var parent: Int32
    /// Its classes' names in the name pool, and its styles in the style pool.
    var classes: UseCaseListSpan
    var styles: UseCaseListSpan
}

struct UseCaseBoundaryRecord: Equatable, Sendable {
    var name: Int32
    var label: UseCaseLabelText
    var type: UseCaseBoundaryType
    /// The names of the actors and use cases declared in it, in the name pool, in the order written.
    var members: UseCaseListSpan
    var classes: UseCaseListSpan
    var styles: UseCaseListSpan
}

struct UseCaseRelationshipRecord: Equatable, Sendable {
    /// Its explicit id's name, or -1 for one written without, which is `edge-` and `anonymousNumber`.
    var name: Int32
    var anonymousNumber: Int32
    var source: Int32
    var target: Int32
    var type: UseCaseRelationshipType
    var arrow: UseCaseArrow
    var label: UseCaseLabelText
    var hasLabel: Bool
    var minimumLength: Int32
    var classes: UseCaseListSpan
    var styles: UseCaseListSpan
    var isAnimated: Bool
    var animation: UseCaseAnimation?
}

/// `note for Target text`, its id `note-` and its place among the notes.
struct UseCaseNoteRecord: Equatable, Sendable {
    var target: Int32
    var label: UseCaseLabelText
}

struct UseCaseJSONRecord: Equatable, Sendable {
    var name: Int32
    /// Its value, by its place among the diagram's JSON values.
    var value: Int32
    var classes: UseCaseListSpan
    var styles: UseCaseListSpan
}

struct UseCaseClassDefinitionRecord: Equatable, Sendable {
    var name: Int32
    var styles: UseCaseListSpan
}
