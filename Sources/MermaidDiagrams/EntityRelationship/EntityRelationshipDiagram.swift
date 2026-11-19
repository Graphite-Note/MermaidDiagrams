/**
 * File: EntityRelationshipDiagram.swift
 * -------------------------------------
 * Layer: Core
 * Description: A Mermaid entity relationship diagram as its text describes it, its groups included.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

/// A Mermaid entity relationship diagram (`erDiagram`) as its text describes it: the entities in the order Mermaid
/// adds them, the relationships between them in the order they are written, and what is read but not drawn.
public struct EntityRelationshipDiagram: Equatable, Sendable {
    /// `direction TB`, `BT`, `LR` or `RL`: the way the entities' ranks follow each other, top to bottom by default.
    /// The four directions are the flowchart's, and are laid out the same way.
    public internal(set) var direction: FlowchartDirection
    public internal(set) var entities: [EntityRelationshipEntity]
    public internal(set) var relationships: [EntityRelationship]
    /// How many `subgraph … end` groups the diagram has.
    public internal(set) var subgraphCount: Int
    /// The `subgraph … end` groups in the order they end, as Mermaid's database lists them (a group inside another
    /// before it), drawn as boxes around what they hold.
    public internal(set) var subgraphs: [EntityRelationshipSubgraph] = []
    /// The diagram's title, from `title:` in the front matter, or nil.
    public internal(set) var title: String?
    /// `accTitle: …`, the short name a screen reader gives the diagram, or nil.
    public internal(set) var accessibilityTitle: String?
    /// `accDescr: …` or `accDescr { … }`, the longer description a screen reader reads, or nil.
    public internal(set) var accessibilityDescription: String?
    /// Statements that change only how the diagram looks (`style`, `classDef`, `class`, `:::`). They are read and not
    /// applied yet.
    public internal(set) var unappliedStatementCount: Int

    init(direction: FlowchartDirection = .topToBottom, entities: [EntityRelationshipEntity] = [], relationships: [EntityRelationship] = [],
         subgraphCount: Int = 0, title: String? = nil, accessibilityTitle: String? = nil, accessibilityDescription: String? = nil,
         unappliedStatementCount: Int = 0) {
        self.direction = direction
        self.entities = entities
        self.relationships = relationships
        self.subgraphCount = subgraphCount
        self.title = title
        self.accessibilityTitle = accessibilityTitle
        self.accessibilityDescription = accessibilityDescription
        self.unappliedStatementCount = unappliedStatementCount
    }
}

/// A `subgraph id [title] … end` group of an entity relationship diagram, as Mermaid's database keeps it: what it holds is
/// each name its statements write, entities and the groups that end inside it, that no group ending before it holds.
/// A name that is also a group's identifier stands for that group: a relationship to it meets the group's box.
public struct EntityRelationshipSubgraph: Equatable, Sendable {
    public let identifier: String
    /// The words between brackets, or the identifier.
    public let title: DiagramLabel
    /// Indexes into `EntityRelationshipDiagram.entities` of the entities directly inside the group, in the order written.
    public internal(set) var entityIndices: [Int]
    /// Indexes into `EntityRelationshipDiagram.subgraphs` of the groups directly inside this one.
    public internal(set) var childSubgraphIndices: [Int]
    /// `direction …` inside the group, or nil when it runs as the box around it does.
    public internal(set) var direction: FlowchartDirection?

    init(identifier: String, title: DiagramLabel, entityIndices: [Int] = [], childSubgraphIndices: [Int] = [], direction: FlowchartDirection? = nil) {
        self.identifier = identifier
        self.title = title
        self.entityIndices = entityIndices
        self.childSubgraphIndices = childSubgraphIndices
        self.direction = direction
    }
}
