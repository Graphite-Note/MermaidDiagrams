/**
 * File: EntityRelationshipDiagramBuilder.swift
 * --------------------------------------------
 * Layer: Core
 * Description: Collects an entity relationship diagram as its statements are read, its groups and what they hold, its
 *              names interned from the text's bytes.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.4
 * Date: 25/11/2026
 */

/// Collects an entity relationship diagram as its statements are read: entities by name, added when the statement
/// that names them is complete, relationships within the limits, and the groups open at each point. Names are byte
/// ranges of the text, interned (`GraphDiagramNameTable`), so that each is compared as 0.7.0's String keys compared it.
struct EntityRelationshipDiagramBuilder {
    private(set) var diagram = EntityRelationshipDiagram()
    private let limits: MermaidDiagramLimits
    private let bytes: GraphDiagramBytes
    private var names: GraphDiagramNameTable
    /// What each name number names, by the number.
    private var namedByNumber: [Named] = []
    /// The `subgraph` groups open now, outermost first: each one's identifier, title, direction and where the names its
    /// statements write start in `writtenNames`.
    private var openSubgraphs: [OpenSubgraph] = []
    /// The names the open groups' statements write, by number, each group's after those of the groups around it.
    private var writtenNames: [Int32] = []
    /// For each group that has ended, in that order, the names it holds, by number: `heldNames` from `heldNameStarts`.
    private var heldNames: [Int32] = []
    private var heldNameStarts: [Int32] = []

    /// What a name names: the entity of that name, the first group to end with it as its identifier, each -1 for none,
    /// whether a group that has ended holds it, and the last group closing that saw it, so that a group takes a name once.
    private struct Named {
        var entityIndex: Int32 = -1
        var subgraphIndex: Int32 = -1
        var isClaimed = false
        var lastClosingThatSawIt: Int32 = -1
    }

    private struct OpenSubgraph {
        let identifier: MermaidTextRange
        let title: DiagramLabel
        var direction: FlowchartDirection?
        let firstWrittenName: Int
    }

    init(limits: MermaidDiagramLimits, bytes: GraphDiagramBytes) {
        self.limits = limits
        self.bytes = bytes
        names = GraphDiagramNameTable(isASCII: bytes.isASCII)
        let nameCount = min((bytes.buffer.count - bytes.position) / Self.bytesPerName + 4, Self.mostReserved)
        names.reserveCapacity(nameCount)
        namedByNumber.reserveCapacity(nameCount)
        diagram.entities.reserveCapacity(min(nameCount, limits.maximumNodeCount))
        diagram.relationships.reserveCapacity(min(nameCount, limits.maximumEdgeCount))
    }

    /// About the bytes an entity's name takes with what is written around it.
    private static let bytesPerName = 24
    /// The most names made room for at once; a longer text's lists grow.
    private static let mostReserved = 2_048

    /// The number of the name `range` spells.
    private mutating func number(of range: MermaidTextRange) -> Int {
        let (number, isNew) = names.intern(bytes.buffer, range)
        if isNew { namedByNumber.append(Named()) }
        return number
    }

    /// The index of the entity `name` names, added with its name as its text the first time it is named.
    mutating func entityIndex(for name: EntityRelationshipName) throws(MermaidDiagramReadError) -> Int {
        let number = number(of: name.range)
        let existing = namedByNumber[number].entityIndex
        if existing >= 0 { return Int(existing) }
        guard diagram.entities.count < limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
        diagram.entities.append(EntityRelationshipEntity(identifier: bytes.text(name.range), label: name.label(in: bytes)))
        namedByNumber[number].entityIndex = Int32(diagram.entities.count - 1)
        return diagram.entities.count - 1
    }

    /// Gives the entity an alias, unless an earlier statement gave it one: Mermaid keeps the first.
    mutating func setAlias(_ alias: EntityRelationshipName, ofEntityAt index: Int) {
        guard !diagram.entities[index].hasAlias else { return }
        diagram.entities[index].label = alias.label(in: bytes)
        diagram.entities[index].hasAlias = true
    }

    /// Adds the rows of one `{ … }` block after those of the entity's earlier blocks.
    mutating func addAttributes(_ attributes: [EntityRelationshipAttribute], toEntityAt index: Int) {
        guard !attributes.isEmpty else { return }
        if diagram.entities[index].attributes.isEmpty {
            diagram.entities[index].attributes = attributes
        } else {
            diagram.entities[index].attributes.append(contentsOf: attributes)
        }
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

    mutating func openSubgraph(identifier: MermaidTextRange, title: DiagramLabel) {
        openSubgraphs.append(OpenSubgraph(identifier: identifier, title: title, firstWrittenName: writtenNames.count))
        diagram.subgraphCount += 1
    }

    /// Records that the innermost open group's statements write the two names a relationship writes; nothing when no
    /// group is open, as in most diagrams.
    mutating func noteNamesInOpenSubgraph(_ first: MermaidTextRange, _ second: MermaidTextRange) {
        guard !openSubgraphs.isEmpty else { return }
        writtenNames.append(Int32(number(of: first)))
        writtenNames.append(Int32(number(of: second)))
    }

    /// Records that the innermost open group's statements write `name`.
    mutating func noteNameInOpenSubgraph(_ name: MermaidTextRange) {
        guard !openSubgraphs.isEmpty else { return }
        writtenNames.append(Int32(number(of: name)))
    }

    /// Closes the innermost group, which takes the names it writes that no group ended before it holds, and is a name
    /// written in the group around it; false when none is open.
    mutating func closeSubgraph() -> Bool {
        guard let closed = openSubgraphs.popLast() else { return false }
        let closing = Int32(diagram.subgraphs.count)
        heldNameStarts.append(Int32(heldNames.count))
        for name in writtenNames[closed.firstWrittenName...] {
            let index = Int(name)
            guard namedByNumber[index].lastClosingThatSawIt != closing, !namedByNumber[index].isClaimed else { continue }
            namedByNumber[index].lastClosingThatSawIt = closing
            heldNames.append(name)
        }
        for name in heldNames[Int(heldNameStarts[heldNameStarts.count - 1])...] { namedByNumber[Int(name)].isClaimed = true }
        writtenNames.removeSubrange(closed.firstWrittenName...)
        let identifierNumber = number(of: closed.identifier)
        if namedByNumber[identifierNumber].subgraphIndex < 0 { namedByNumber[identifierNumber].subgraphIndex = closing }
        diagram.subgraphs.append(EntityRelationshipSubgraph(identifier: bytes.text(closed.identifier), title: closed.title, direction: closed.direction))
        noteNameInOpenSubgraph(closed.identifier)
        return true
    }

    /// The identifier of the innermost group still open, or nil.
    var innermostOpenSubgraphIdentifier: String? {
        openSubgraphs.last.map { open in bytes.text(open.identifier) }
    }

    /// The diagram, each group holding the entities and groups its names name.
    func finished() -> EntityRelationshipDiagram {
        guard !heldNameStarts.isEmpty else { return diagram }
        var finished = diagram
        for index in heldNameStarts.indices {
            let end = index + 1 < heldNameStarts.count ? Int(heldNameStarts[index + 1]) : heldNames.count
            for name in heldNames[Int(heldNameStarts[index])..<end] {
                let named = namedByNumber[Int(name)]
                if named.subgraphIndex >= 0, Int(named.subgraphIndex) != index {
                    finished.subgraphs[index].childSubgraphIndices.append(Int(named.subgraphIndex))
                } else if named.entityIndex >= 0 {
                    finished.subgraphs[index].entityIndices.append(Int(named.entityIndex))
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
