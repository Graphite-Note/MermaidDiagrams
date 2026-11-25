/**
 * File: EntityRelationshipDiagramBuilder.swift
 * --------------------------------------------
 * Layer: Core
 * Description: Collects an entity relationship diagram as its statements are read, its groups and what they hold.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.3
 * Date: 25/11/2026
 */

/// Collects an entity relationship diagram as its statements are read: entities by name, added when the statement
/// that names them is complete, relationships within the limits, and the groups open at each point.
struct EntityRelationshipDiagramBuilder {
    private(set) var diagram = EntityRelationshipDiagram()
    private let limits: MermaidDiagramLimits
    private var entityIndexByIdentifier: [String: Int] = [:]
    /// The `subgraph` groups open now, outermost first: each one's identifier, title, direction and the names its
    /// statements write.
    private var openSubgraphs: [OpenSubgraph] = []
    /// The names a group that has ended holds: a name belongs to the first group to end that writes it.
    private var claimedNames: Set<String> = []

    private struct OpenSubgraph {
        let identifier: String
        let title: DiagramLabel
        var direction: FlowchartDirection?
        var names: [String] = []
    }

    init(limits: MermaidDiagramLimits) {
        self.limits = limits
    }

    /// The index of the entity `name` names, added with its name as its text the first time it is named.
    mutating func entityIndex(for name: EntityRelationshipName) throws(MermaidDiagramReadError) -> Int {
        if let existing = entityIndexByIdentifier[name.text] { return existing }
        guard diagram.entities.count < limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
        diagram.entities.append(EntityRelationshipEntity(identifier: name.text, label: name.label))
        entityIndexByIdentifier[name.text] = diagram.entities.count - 1
        return diagram.entities.count - 1
    }

    /// Gives the entity an alias, unless an earlier statement gave it one: Mermaid keeps the first.
    mutating func setAlias(_ alias: DiagramLabel, ofEntityAt index: Int) {
        guard !diagram.entities[index].hasAlias else { return }
        diagram.entities[index].label = alias
        diagram.entities[index].hasAlias = true
    }

    /// Adds the rows of one `{ … }` block after those of the entity's earlier blocks.
    mutating func addAttributes(_ attributes: [EntityRelationshipAttribute], toEntityAt index: Int) {
        diagram.entities[index].attributes.append(contentsOf: attributes)
    }

    mutating func addRelationship(_ relationship: EntityRelationship) throws(MermaidDiagramReadError) {
        guard diagram.relationships.count < limits.maximumEdgeCount else { throw .tooManyEdges(limit: limits.maximumEdgeCount) }
        diagram.relationships.append(relationship)
    }

    /// A `direction` inside a group sets the group's direction; outside, the diagram's.
    mutating func setDirection(_ direction: FlowchartDirection) {
        guard !openSubgraphs.isEmpty else {
            diagram.direction = direction
            return
        }
        openSubgraphs[openSubgraphs.count - 1].direction = direction
    }

    mutating func openSubgraph(identifier: String, title: DiagramLabel) {
        openSubgraphs.append(OpenSubgraph(identifier: identifier, title: title))
        diagram.subgraphCount += 1
    }

    /// Records that the innermost open group's statements write `names`.
    /// The two names a relationship writes, noted without a list made for them when no group is open, as most are.
    mutating func noteNamesInOpenSubgraph(_ first: String, _ second: String) {
        guard !openSubgraphs.isEmpty else { return }
        openSubgraphs[openSubgraphs.count - 1].names.append(first)
        openSubgraphs[openSubgraphs.count - 1].names.append(second)
    }

    mutating func noteNamesInOpenSubgraph(_ names: [String]) {
        guard !openSubgraphs.isEmpty else { return }
        openSubgraphs[openSubgraphs.count - 1].names.append(contentsOf: names)
    }

    /// Closes the innermost group, which takes the names it writes that no group ended before it holds, and is a name
    /// written in the group around it; false when none is open.
    mutating func closeSubgraph() -> Bool {
        guard let closed = openSubgraphs.popLast() else { return false }
        var seen: Set<String> = []
        var held: [String] = []
        for name in closed.names where !seen.contains(name) && !claimedNames.contains(name) {
            seen.insert(name)
            held.append(name)
        }
        claimedNames.formUnion(held)
        heldNames.append(held)
        diagram.subgraphs.append(EntityRelationshipSubgraph(identifier: closed.identifier, title: closed.title, direction: closed.direction))
        noteNamesInOpenSubgraph([closed.identifier])
        return true
    }

    /// For each group that has ended, the names it holds, resolved to entities and groups when the diagram is finished.
    private var heldNames: [[String]] = []

    /// The identifier of the innermost group still open, or nil.
    var innermostOpenSubgraphIdentifier: String? {
        openSubgraphs.last?.identifier
    }

    /// The diagram, each group holding the entities and groups its names name.
    func finished() -> EntityRelationshipDiagram {
        var finished = diagram
        var subgraphIndexByIdentifier: [String: Int] = [:]
        for (index, subgraph) in finished.subgraphs.enumerated() where subgraphIndexByIdentifier[subgraph.identifier] == nil {
            subgraphIndexByIdentifier[subgraph.identifier] = index
        }
        for (index, names) in heldNames.enumerated() {
            for name in names {
                if let child = subgraphIndexByIdentifier[name], child != index {
                    finished.subgraphs[index].childSubgraphIndices.append(child)
                } else if let entity = entityIndexByIdentifier[name] {
                    finished.subgraphs[index].entityIndices.append(entity)
                }
            }
        }
        return finished
    }

    mutating func setAccessibilityTitle(_ title: String) {
        diagram.accessibilityTitle = title
    }

    mutating func setAccessibilityDescription(_ description: String) {
        diagram.accessibilityDescription = description
    }

    mutating func countUnappliedStatement() {
        diagram.unappliedStatementCount += 1
    }
}
