/**
 * File: ReferenceUseCaseDiagram.swift
 * -----------------------------------
 * Layer: Tests
 * Description: A Mermaid use case diagram (`usecase-beta`) as Pele's model holds it once read: its actors, use cases,
 *              system boundaries, relationships, notes, JSON tables and class definitions, in the order first mentioned.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

@testable import MermaidDiagrams

/// A Mermaid use case diagram as Pele's `resolveUsecase` holds it: every actor and use case in the order its id is first
/// mentioned, the system boundaries and JSON tables likewise, the relationships and notes in the order written.
public struct ReferenceUseCaseDiagram: Equatable, Sendable {
    public internal(set) var actors: [UseCaseActor] = []
    public internal(set) var useCases: [UseCase] = []
    public internal(set) var systemBoundaries: [UseCaseSystemBoundary] = []
    public internal(set) var relationships: [UseCaseRelationship] = []
    public internal(set) var notes: [UseCaseNote] = []
    public internal(set) var jsonNodes: [UseCaseJSONNode] = []
    /// `classDef` statements, each name once in the order first defined, its styles those of its last definition.
    public internal(set) var classDefinitions: [UseCaseClassDefinition] = []
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
    public var turnedToRunDown: ReferenceUseCaseDiagram? {
        guard direction == .leftToRight || direction == .rightToLeft else { return nil }
        var turned = self
        turned.direction = .topToBottom
        return turned
    }
}
