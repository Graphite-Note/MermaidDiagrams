/**
 * File: UseCaseDrafts.swift
 * -------------------------
 * Layer: Core
 * Description: What the use case parser read, in source order, before any of it is resolved into a diagram, as Pele's
 *              db.ts drafts hold it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// A label as written: its text (a string's without its quotes), whether it is Markdown, and where its text starts.
struct UseCaseDraftLabel {
    let text: String
    let type: UseCaseLabelType
    let start: Int
}

/// A metadata property's value: text (an identifier or a string) or `true` and `false`.
enum UseCaseMetadataValue: Equatable {
    case text(String)
    case boolean(Bool)

    var text: String? {
        guard case .text(let text) = self else { return nil }
        return text
    }

    var boolean: Bool? {
        guard case .boolean(let value) = self else { return nil }
        return value
    }
}

/// `key: value` in `@{ … }`, and where its key starts, which an error about it names.
struct UseCaseDraftProperty {
    let key: String
    let value: UseCaseMetadataValue
    let keyStart: Int
}

/// What every mention of an id carries: where it is, and whether the id was made from a label (`"Reset password"`).
struct UseCaseDraftName {
    let identifier: String
    let label: UseCaseDraftLabel
    let start: Int
    let isGenerated: Bool
}

enum UseCaseElementKind: String {
    case actor
    case useCase = "usecase"
}

/// A declaration of an actor or a use case: `actor A`, `Login(Sign in)`, or an end of a relationship that says
/// something about it.
struct UseCaseDraftElement {
    let name: UseCaseDraftName
    let kind: UseCaseElementKind
    /// The boundary it is declared in, by its place among the drafts' boundaries.
    let parent: Int?
    let shape: UseCaseShape?
    let metadata: [UseCaseDraftProperty]?
    let stereotype: String?
    let classes: [String]
}

struct UseCaseDraftBoundary {
    let name: UseCaseDraftName
    let classes: [String]
}

struct UseCaseDraftJSON {
    let identifier: String
    let start: Int
    var value: UseCaseJSONValue
    let classes: [String]
}

/// An end of a relationship: whether this mention declares the element, and whether it carries `:::`.
struct UseCaseDraftEndpoint {
    let name: UseCaseDraftName
    let declares: Bool
    let isClassed: Bool
}

struct UseCaseDraftRelationship {
    let source: UseCaseDraftEndpoint
    let target: UseCaseDraftEndpoint
    let start: Int
    let identifier: String?
    let identifierStart: Int?
    let type: UseCaseRelationshipType
    let arrow: UseCaseArrow
    let label: UseCaseDraftLabel?
    let minimumLength: Int
}

/// Everything the parser read, in source order, before any of it is resolved (Pele's `Drafts`).
struct UseCaseDrafts {
    var elements: [UseCaseDraftElement] = []
    var boundaries: [UseCaseDraftBoundary] = []
    var jsons: [UseCaseDraftJSON] = []
    var relationships: [UseCaseDraftRelationship] = []
    var notes: [(target: String, start: Int, label: UseCaseDraftLabel)] = []
    var metadata: [(target: String, start: Int, properties: [UseCaseDraftProperty])] = []
    var classAssignments: [(targets: [(identifier: String, start: Int)], classes: [String])] = []
    var styles: [(target: String, start: Int, styles: [String])] = []
    var classDefinitions: [(identifiers: [String], styles: [String])] = []
    var direction: UseCaseDirection?
    var accessibilityTitle = ""
    var accessibilityDescription = ""

    /// The statements read that make a node: each is at most one node however often its id is mentioned again.
    var nodeStatementCount: Int { elements.count + boundaries.count + jsons.count + notes.count }
}
