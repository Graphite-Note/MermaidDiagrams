/**
 * File: EntityRelationshipDiagramBuilder.swift
 * --------------------------------------------
 * Layer: Core
 * Description: Collects an entity relationship diagram's flat records as its statements are read, its groups and what
 *              they hold, its names interned from the text's bytes, in the thread's reading lists.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.5
 * Date: 26/11/2026
 */

/// Collects an entity relationship diagram as its statements are read: entities by name, added when the statement
/// that names them is complete, their attributes in one list with the entity of each, relationships within the limits,
/// and the groups open at each point. Names are byte ranges of the text, interned (`GraphDiagramNameTable`), so that
/// each is compared as 0.7.0's String keys compared it; the records keep the ranges, and texts are decoded only when
/// read (`EntityRelationshipText`).
struct EntityRelationshipDiagramBuilder {
    private let limits: MermaidDiagramLimits
    let bytes: GraphDiagramBytes
    /// The name table, the records and the groups' names (`EntityRelationshipReadingLists`).
    var lists = EntityRelationshipReadingLists()
    private var direction = FlowchartDirection.topToBottom
    private var subgraphCount = 0
    private var accessibilityTitle: String?
    private var accessibilityDescription: String?
    private var unappliedStatementCount = 0

    /// A builder with empty lists, which the reading swaps for its thread's (`EntityRelationshipReadingScratch`) before it
    /// reads, so that they are moved and never copied.
    init(limits: MermaidDiagramLimits, bytes: GraphDiagramBytes) {
        self.limits = limits
        self.bytes = bytes
    }

    /// Room for about as many names as the text writes.
    mutating func reserveNames() {
        let nameCount = min((bytes.buffer.count - bytes.position) / Self.bytesPerName + 4, Self.mostReserved)
        lists.names.reserveCapacity(nameCount)
        lists.namedByNumber.reserveCapacity(nameCount)
        lists.entities.reserveCapacity(min(nameCount, limits.maximumNodeCount))
        lists.relationships.reserveCapacity(min(nameCount, limits.maximumEdgeCount))
    }

    /// About the bytes an entity's name takes with what is written around it.
    private static let bytesPerName = 24
    /// The most names made room for at once; a longer text's lists grow.
    private static let mostReserved = 2_048

    /// The number of the name `range` spells.
    private mutating func number(of range: MermaidTextRange) -> Int {
        let (number, isNew) = lists.names.intern(bytes.buffer, range)
        if isNew { lists.namedByNumber.append(EntityRelationshipNamed()) }
        return number
    }

    /// The index of the entity `name` names, added with its name as its text the first time it is named.
    mutating func entityIndex(for name: EntityRelationshipName) throws(MermaidDiagramReadError) -> Int {
        let number = number(of: name.range)
        let existing = lists.namedByNumber[number].entityIndex
        if existing >= 0 { return Int(existing) }
        guard lists.entities.count < limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
        lists.entities.append(EntityRelationshipEntityRecord(identifier: name.range, label: EntityRelationshipText(name: name.range, form: name.form)))
        lists.namedByNumber[number].entityIndex = Int32(lists.entities.count - 1)
        return lists.entities.count - 1
    }

    /// Gives the entity an alias, unless an earlier statement gave it one: Mermaid keeps the first.
    mutating func setAlias(_ alias: EntityRelationshipName, ofEntityAt index: Int) {
        guard !lists.entities[index].hasAlias else { return }
        lists.entities[index].label = EntityRelationshipText(name: alias.range, form: alias.form)
        lists.entities[index].hasAlias = true
    }

    /// Where the next attribute read goes in the attributes' list.
    var attributeCount: Int { lists.attributes.count }

    /// The attributes read from `first` on, one `{ … }` block's, belong to the entity at `index`, after those of its
    /// earlier blocks.
    mutating func giveAttributes(from first: Int, toEntityAt index: Int) {
        let count = lists.attributes.count - first
        guard count > 0 else { return }
        lists.attributeOwners.append(contentsOf: repeatElement(Int32(index), count: count))
        lists.entities[index].attributeCount += Int32(count)
    }

    mutating func addRelationship(_ relationship: EntityRelationshipRelationshipRecord) throws(MermaidDiagramReadError) {
        guard lists.relationships.count < limits.maximumEdgeCount else { throw .tooManyEdges(limit: limits.maximumEdgeCount) }
        lists.relationships.append(relationship)
    }

    /// A `direction` inside a group sets the group's direction; outside, the diagram's.
    mutating func setDirection(_ direction: FlowchartDirection) {
        guard !lists.openGroups.isEmpty else {
            self.direction = direction
            return
        }
        lists.openGroups[lists.openGroups.count - 1].direction = direction
    }

    mutating func openSubgraph(identifier: MermaidTextRange, title: DiagramLabel) {
        lists.labels.append(title)
        lists.openGroups.append(EntityRelationshipOpenGroup(identifier: identifier, title: Int32(lists.labels.count - 1),
                                                            firstWrittenName: lists.writtenNames.count))
        subgraphCount += 1
    }

    /// Records that the innermost open group's statements write the two names a relationship writes; nothing when no
    /// group is open, as in most diagrams.
    mutating func noteNamesInOpenSubgraph(_ first: MermaidTextRange, _ second: MermaidTextRange) {
        guard !lists.openGroups.isEmpty else { return }
        lists.writtenNames.append(Int32(number(of: first)))
        lists.writtenNames.append(Int32(number(of: second)))
    }

    /// Records that the innermost open group's statements write `name`.
    mutating func noteNameInOpenSubgraph(_ name: MermaidTextRange) {
        guard !lists.openGroups.isEmpty else { return }
        lists.writtenNames.append(Int32(number(of: name)))
    }

    /// Closes the innermost group, which takes the names it writes that no group ended before it holds, and is a name
    /// written in the group around it; false when none is open.
    mutating func closeSubgraph() -> Bool {
        guard let closed = lists.openGroups.popLast() else { return false }
        let closing = Int32(lists.groups.count)
        lists.heldNameStarts.append(Int32(lists.heldNames.count))
        for position in closed.firstWrittenName..<lists.writtenNames.count {
            let name = lists.writtenNames[position]
            let index = Int(name)
            guard lists.namedByNumber[index].lastClosingThatSawIt != closing, !lists.namedByNumber[index].isClaimed else { continue }
            lists.namedByNumber[index].lastClosingThatSawIt = closing
            lists.heldNames.append(name)
        }
        for position in Int(lists.heldNameStarts[lists.heldNameStarts.count - 1])..<lists.heldNames.count {
            lists.namedByNumber[Int(lists.heldNames[position])].isClaimed = true
        }
        lists.writtenNames.removeSubrange(closed.firstWrittenName...)
        let identifierNumber = number(of: closed.identifier)
        if lists.namedByNumber[identifierNumber].subgraphIndex < 0 { lists.namedByNumber[identifierNumber].subgraphIndex = closing }
        lists.groups.append(EntityRelationshipGroupRecord(identifier: closed.identifier, title: closed.title, direction: closed.direction))
        noteNameInOpenSubgraph(closed.identifier)
        return true
    }

    /// The identifier of the innermost group still open, or nil.
    var innermostOpenSubgraphIdentifier: String? {
        lists.openGroups.last.map { open in bytes.text(open.identifier) }
    }

    mutating func setAccessibilityTitle(_ title: String) {
        accessibilityTitle = title
    }

    mutating func setAccessibilityDescription(_ description: String) {
        accessibilityDescription = description
    }

    mutating func countUnappliedStatement() {
        unappliedStatementCount += 1
    }

    /// The diagram over `text`, the bytes the builder read, which the model keeps.
    func finished(text: [UInt8]) -> EntityRelationshipDiagram {
        var model = EntityRelationshipModel()
        model.text = text
        model.entities = Self.exactCopy(lists.entities)
        model.relationships = Self.exactCopy(lists.relationships)
        if !lists.attributes.isEmpty { gatherAttributes(into: &model) }
        if !lists.groups.isEmpty { gatherGroups(into: &model) }
        return EntityRelationshipDiagram(direction: direction, model: model, subgraphCount: subgraphCount, accessibilityTitle: accessibilityTitle,
                                         accessibilityDescription: accessibilityDescription, unappliedStatementCount: unappliedStatementCount)
    }

    /// Each entity's attributes, in the order read, as one run of `attributes`: counted, then placed, each entity's
    /// count counting the attributes placed so far while they are placed.
    private func gatherAttributes(into model: inout EntityRelationshipModel) {
        var start: Int32 = 0
        for index in model.entities.indices {
            model.entities[index].firstAttribute = start
            start += model.entities[index].attributeCount
            model.entities[index].attributeCount = 0
        }
        let attributes = lists.attributes
        let owners = lists.attributeOwners
        model.attributes = [EntityRelationshipAttributeRecord](unsafeUninitializedCapacity: attributes.count) { buffer, count in
            model.entities.withUnsafeMutableBufferPointer { entities in
                for position in attributes.indices {
                    let owner = Int(owners[position])
                    buffer.initializeElement(at: Int(entities[owner].firstAttribute + entities[owner].attributeCount), to: attributes[position])
                    entities[owner].attributeCount += 1
                }
            }
            count = attributes.count
        }
        model.keys = Self.exactCopy(lists.keys)
    }

    /// Each group holding the entities and groups its names name, the entities then the groups in one run of `members`,
    /// the groups' titles, and the group each entity stands for: the first to end with its name as identifier.
    private func gatherGroups(into model: inout EntityRelationshipModel) {
        model.groups = Self.exactCopy(lists.groups)
        model.labels = lists.labels
        model.representedGroups = [Int32](repeating: -1, count: model.entities.count)
        for named in lists.namedByNumber where named.entityIndex >= 0 && named.subgraphIndex >= 0 {
            model.representedGroups[Int(named.entityIndex)] = named.subgraphIndex
        }
        for index in lists.heldNameStarts.indices {
            let end = index + 1 < lists.heldNameStarts.count ? Int(lists.heldNameStarts[index + 1]) : lists.heldNames.count
            let held = Int(lists.heldNameStarts[index])..<end
            model.groups[index].firstMember = Int32(model.members.count)
            for position in held {
                let named = lists.namedByNumber[Int(lists.heldNames[position])]
                if !(named.subgraphIndex >= 0 && Int(named.subgraphIndex) != index), named.entityIndex >= 0 { model.members.append(named.entityIndex) }
            }
            model.groups[index].entityCount = Int32(model.members.count) - model.groups[index].firstMember
            for position in held {
                let named = lists.namedByNumber[Int(lists.heldNames[position])]
                if named.subgraphIndex >= 0, Int(named.subgraphIndex) != index { model.members.append(named.subgraphIndex) }
            }
            model.groups[index].childCount = Int32(model.members.count) - model.groups[index].firstMember - model.groups[index].entityCount
        }
    }

    /// A list of exactly `list`'s elements, made for the model to keep: an empty list makes nothing.
    @inline(__always)
    static func exactCopy<Element>(_ list: [Element]) -> [Element] {
        guard !list.isEmpty else { return [] }
        return [Element](unsafeUninitializedCapacity: list.count) { buffer, initializedCount in
            _ = buffer.initialize(from: list)
            initializedCount = list.count
        }
    }
}
