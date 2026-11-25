/**
 * File: ReferenceUseCaseDrafts.swift
 * ----------------------------------
 * Layer: Tests
 * Description: What the use case parser read, in source order, before any of it is resolved into a diagram, as Pele's
 *              db.ts drafts hold it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

@testable import MermaidDiagrams

/// A label as written: its text (a string's without its quotes), whether it is Markdown, and where its text starts.
struct ReferenceUseCaseDraftLabel {
    let text: String
    let type: UseCaseLabelType
    let start: Int
}

/// A metadata property's value: text (an identifier or a string) or `true` and `false`.
enum ReferenceUseCaseMetadataValue: Equatable {
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
struct ReferenceUseCaseDraftProperty {
    let key: String
    let value: ReferenceUseCaseMetadataValue
    let keyStart: Int
}

/// What every mention of an id carries: where it is, and whether the id was made from a label (`"Reset password"`).
struct ReferenceUseCaseDraftName {
    let identifier: String
    let label: ReferenceUseCaseDraftLabel
    let start: Int
    let isGenerated: Bool
}

enum ReferenceUseCaseElementKind: String {
    case actor
    case useCase = "usecase"
}

/// A declaration of an actor or a use case: `actor A`, `Login(Sign in)`, or an end of a relationship that says
/// something about it.
struct ReferenceUseCaseDraftElement {
    let name: ReferenceUseCaseDraftName
    let kind: ReferenceUseCaseElementKind
    /// The boundary it is declared in, by its place among the drafts' boundaries.
    let parent: Int?
    let shape: UseCaseShape?
    let metadata: [ReferenceUseCaseDraftProperty]?
    let stereotype: String?
    let classes: [String]
}

struct ReferenceUseCaseDraftBoundary {
    let name: ReferenceUseCaseDraftName
    let classes: [String]
}

struct ReferenceUseCaseDraftJSON {
    let identifier: String
    let start: Int
    var value: UseCaseJSONValue
    let classes: [String]
}

/// An end of a relationship: whether this mention declares the element, and whether it carries `:::`.
struct ReferenceUseCaseDraftEndpoint {
    let name: ReferenceUseCaseDraftName
    let declares: Bool
    let isClassed: Bool
}

struct ReferenceUseCaseDraftRelationship {
    let source: ReferenceUseCaseDraftEndpoint
    let target: ReferenceUseCaseDraftEndpoint
    let start: Int
    let identifier: String?
    let identifierStart: Int?
    let type: UseCaseRelationshipType
    let arrow: UseCaseArrow
    let label: ReferenceUseCaseDraftLabel?
    let minimumLength: Int
}

/// Everything the parser read, in source order, before any of it is resolved (Pele's `Drafts`).
struct ReferenceUseCaseDrafts {
    var elements: [ReferenceUseCaseDraftElement] = []
    var boundaries: [ReferenceUseCaseDraftBoundary] = []
    var jsons: [ReferenceUseCaseDraftJSON] = []
    var relationships: [ReferenceUseCaseDraftRelationship] = []
    var notes: [(target: String, start: Int, label: ReferenceUseCaseDraftLabel)] = []
    var metadata: [(target: String, start: Int, properties: [ReferenceUseCaseDraftProperty])] = []
    var classAssignments: [(targets: [(identifier: String, start: Int)], classes: [String])] = []
    var styles: [(target: String, start: Int, styles: [String])] = []
    var classDefinitions: [(identifiers: [String], styles: [String])] = []
    var direction: UseCaseDirection?
    var accessibilityTitle = ""
    var accessibilityDescription = ""

    /// The statements read that make a node: each is at most one node however often its id is mentioned again.
    var nodeStatementCount: Int { elements.count + boundaries.count + jsons.count + notes.count }
}
