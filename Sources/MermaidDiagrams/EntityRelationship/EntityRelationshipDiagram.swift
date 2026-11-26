/**
 * File: EntityRelationshipDiagram.swift
 * -------------------------------------
 * Layer: Core
 * Description: A Mermaid entity relationship diagram as its text describes it, its groups included, over the flat
 *              records its reading made, made into values when a host reads them.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.3
 * Date: 26/11/2026
 */

/// A Mermaid entity relationship diagram (`erDiagram`) as its text describes it: the entities in the order Mermaid
/// adds them, the relationships between them in the order they are written, and what is read but not drawn.
///
/// The diagram keeps the flat records its reading made (`EntityRelationshipModel`): `entities`, `relationships` and
/// `subgraphs` are made from them each time they are read (their setters, internal, make a model of the values), so a
/// loop over a diagram's entities reads `entityCount` and `entity(at:)` instead.
public struct EntityRelationshipDiagram: Equatable, Sendable {
    /// `direction TB`, `BT`, `LR` or `RL`: the way the entities' ranks follow each other, top to bottom by default.
    /// The four directions are the flowchart's, and are laid out the same way.
    public internal(set) var direction: FlowchartDirection
    /// The entities, relationships and groups, as the reading made them.
    private(set) var model: EntityRelationshipModel
    /// How many `subgraph … end` groups the diagram has.
    public internal(set) var subgraphCount: Int
    /// The diagram's title, from `title:` in the front matter, or nil.
    public internal(set) var title: String?
    /// `accTitle: …`, the short name a screen reader gives the diagram, or nil.
    public internal(set) var accessibilityTitle: String?
    /// `accDescr: …` or `accDescr { … }`, the longer description a screen reader reads, or nil.
    public internal(set) var accessibilityDescription: String?
    /// Statements that change only how the diagram looks (`style`, `classDef`, `class`, `:::`). They are read and not
    /// applied yet.
    public internal(set) var unappliedStatementCount: Int

    init(direction: FlowchartDirection = .topToBottom, model: EntityRelationshipModel = EntityRelationshipModel(), subgraphCount: Int = 0,
         title: String? = nil, accessibilityTitle: String? = nil, accessibilityDescription: String? = nil, unappliedStatementCount: Int = 0) {
        self.direction = direction
        self.model = model
        self.subgraphCount = subgraphCount
        self.title = title
        self.accessibilityTitle = accessibilityTitle
        self.accessibilityDescription = accessibilityDescription
        self.unappliedStatementCount = unappliedStatementCount
    }

    init(direction: FlowchartDirection = .topToBottom, entities: [EntityRelationshipEntity], relationships: [EntityRelationship] = [],
         subgraphs: [EntityRelationshipSubgraph] = [], subgraphCount: Int = 0, title: String? = nil, accessibilityTitle: String? = nil,
         accessibilityDescription: String? = nil, unappliedStatementCount: Int = 0) {
        self.init(direction: direction, model: EntityRelationshipModel(entities: entities, relationships: relationships, subgraphs: subgraphs),
                  subgraphCount: subgraphCount, title: title, accessibilityTitle: accessibilityTitle, accessibilityDescription: accessibilityDescription,
                  unappliedStatementCount: unappliedStatementCount)
    }

    /// The entities in the order Mermaid adds them, made from the model on each read.
    public internal(set) var entities: [EntityRelationshipEntity] {
        get { (0..<entityCount).map(model.entity(at:)) }
        set { model = EntityRelationshipModel(entities: newValue, relationships: relationships, subgraphs: subgraphs) }
    }

    /// The relationships in the order they are written, those of an entity with itself included, made from the model on
    /// each read.
    public internal(set) var relationships: [EntityRelationship] {
        get { (0..<relationshipCount).map(model.relationship(at:)) }
        set { model = EntityRelationshipModel(entities: entities, relationships: newValue, subgraphs: subgraphs) }
    }

    /// The `subgraph … end` groups in the order they end, as Mermaid's database lists them (a group inside another
    /// before it), drawn as boxes around what they hold; made from the model on each read.
    public internal(set) var subgraphs: [EntityRelationshipSubgraph] {
        get { model.groups.indices.map(model.subgraph(at:)) }
        set { model = EntityRelationshipModel(entities: entities, relationships: relationships, subgraphs: newValue) }
    }

    public var entityCount: Int { model.entities.count }
    public var relationshipCount: Int { model.relationships.count }

    public func entity(at index: Int) -> EntityRelationshipEntity { model.entity(at: index) }
    public func relationship(at index: Int) -> EntityRelationship { model.relationship(at: index) }
    public func subgraph(at index: Int) -> EntityRelationshipSubgraph { model.subgraph(at: index) }

    /// Diagrams are equal when they read the same: the same entities, relationships, groups, direction, texts and counts,
    /// whatever text their models index.
    public static func == (left: EntityRelationshipDiagram, right: EntityRelationshipDiagram) -> Bool {
        left.direction == right.direction && left.subgraphCount == right.subgraphCount && left.title == right.title
            && left.accessibilityTitle == right.accessibilityTitle && left.accessibilityDescription == right.accessibilityDescription
            && left.unappliedStatementCount == right.unappliedStatementCount && left.entityCount == right.entityCount
            && left.relationshipCount == right.relationshipCount && left.model.groups.count == right.model.groups.count
            && left.entities == right.entities && left.relationships == right.relationships && left.subgraphs == right.subgraphs
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
