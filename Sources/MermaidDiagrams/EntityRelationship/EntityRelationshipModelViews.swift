/**
 * File: EntityRelationshipModelViews.swift
 * ----------------------------------------
 * Layer: Core
 * Description: An entity relationship diagram's flat records made into the values a host reads (entities with their
 *              attributes, relationships, groups, with their Strings and labels) when it reads them, and a model made
 *              from such values.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

extension EntityRelationshipModel {
    func entity(at index: Int) -> EntityRelationshipEntity {
        let record = entities[index]
        return EntityRelationshipEntity(identifier: string(record.identifier), label: label(record.label), hasAlias: record.hasAlias,
                                        attributes: record.attributeIndices.map(attribute(at:)))
    }

    /// Attribute `index` as the reading made it: written words with their `?` and their pairs of `~` read as angle
    /// brackets, a written comment decoded as Markdown with its lines' pairs of `~` read so too.
    func attribute(at index: Int) -> EntityRelationshipAttribute {
        let record = attributes[index]
        let keys = (0..<Int(record.keyCount)).map { position in key(position, of: record) }
        guard record.isWritten else {
            return EntityRelationshipAttribute(type: string(record.type), name: string(record.name), keys: keys,
                                               comment: record.hasComment ? label(record.comment) : nil)
        }
        return EntityRelationshipAttribute(type: writtenType(of: record), name: EntityRelationshipGenericType.angleBracketed(string(record.name)), keys: keys,
                                           comment: record.hasComment ? EntityRelationshipAttributeSyntax.commentLabel(string(record.comment.range)) : nil)
    }

    /// A written attribute's type as text: its word, `?` added when whitespace stood before it, pairs of `~` read.
    func writtenType(of record: EntityRelationshipAttributeRecord) -> String {
        EntityRelationshipGenericType.angleBracketed(record.appendsQuestionMark ? string(record.type) + "?" : string(record.type))
    }

    func relationship(at index: Int) -> EntityRelationship {
        let record = relationships[index]
        return EntityRelationship(firstEntityIndex: Int(record.firstEntityIndex), secondEntityIndex: Int(record.secondEntityIndex),
                                  firstEntityCardinality: record.firstEntityCardinality, secondEntityCardinality: record.secondEntityCardinality,
                                  identification: record.identification, label: label(record.label))
    }

    func subgraph(at index: Int) -> EntityRelationshipSubgraph {
        let record = groups[index]
        return EntityRelationshipSubgraph(identifier: string(record.identifier), title: labels[Int(record.title)],
                                          entityIndices: record.entityIndices.map { position in Int(members[position]) },
                                          childSubgraphIndices: record.childIndices.map { position in Int(members[position]) }, direction: record.direction)
    }
}

extension EntityRelationshipModel {
    /// The model of values set in code: their Strings written one after the other as its text, their labels kept decoded,
    /// every attribute's texts as they are.
    init(entities: [EntityRelationshipEntity], relationships: [EntityRelationship], subgraphs: [EntityRelationshipSubgraph]) {
        for entity in entities {
            let identifier = written(entity.identifier)
            var record = EntityRelationshipEntityRecord(identifier: identifier, label: decoded(entity.label), hasAlias: entity.hasAlias)
            record.firstAttribute = Int32(attributes.count)
            for attribute in entity.attributes { appendAttribute(attribute) }
            record.attributeCount = Int32(attributes.count) - record.firstAttribute
            self.entities.append(record)
        }
        for relationship in relationships {
            self.relationships.append(EntityRelationshipRelationshipRecord(
                firstEntityIndex: Int32(relationship.firstEntityIndex), secondEntityIndex: Int32(relationship.secondEntityIndex),
                firstEntityCardinality: relationship.firstEntityCardinality, secondEntityCardinality: relationship.secondEntityCardinality,
                identification: relationship.identification, label: decoded(relationship.label)))
        }
        for subgraph in subgraphs {
            var record = EntityRelationshipGroupRecord(identifier: written(subgraph.identifier), title: Int32(labels.count), direction: subgraph.direction,
                                                       firstMember: Int32(members.count))
            labels.append(subgraph.title)
            members += subgraph.entityIndices.map(Int32.init)
            members += subgraph.childSubgraphIndices.map(Int32.init)
            record.entityCount = Int32(subgraph.entityIndices.count)
            record.childCount = Int32(subgraph.childSubgraphIndices.count)
            groups.append(record)
        }
        guard !subgraphs.isEmpty else { return }
        var groupByIdentifier: [String: Int32] = [:]
        for (index, subgraph) in subgraphs.enumerated() where groupByIdentifier[subgraph.identifier] == nil { groupByIdentifier[subgraph.identifier] = Int32(index) }
        representedGroups = entities.map { entity in groupByIdentifier[entity.identifier] ?? -1 }
    }

    private mutating func appendAttribute(_ attribute: EntityRelationshipAttribute) {
        let type = written(attribute.type)
        let name = written(attribute.name)
        var record = EntityRelationshipAttributeRecord(type: type, name: name, comment: .none, hasComment: attribute.comment != nil,
                                                       isWritten: false, appendsQuestionMark: false, keyCount: Int32(attribute.keys.count), keyStart: 0)
        if let comment = attribute.comment { record.comment = decoded(comment) }
        record.keyStart = Self.keyStart(of: attribute.keys, spillingInto: &keys)
        attributes.append(record)
    }

    /// Where keys go in a record: packed when they are few, else appended to `spilled` from the start returned.
    static func keyStart(of keys: some Collection<EntityRelationshipAttributeKey>, spillingInto spilled: inout [EntityRelationshipAttributeKey]) -> Int32 {
        guard keys.count > EntityRelationshipAttributeRecord.packedKeyLimit else {
            var packed: Int32 = 0
            for (position, key) in keys.enumerated() { packed |= packedBits(of: key) << (2 * Int32(position)) }
            return packed
        }
        let start = Int32(spilled.count)
        spilled.append(contentsOf: keys)
        return start
    }

    private mutating func written(_ string: String) -> MermaidTextRange {
        let start = text.count
        text.append(contentsOf: string.utf8)
        return MermaidTextRange(start: start, end: text.count)
    }

    private mutating func decoded(_ label: DiagramLabel) -> EntityRelationshipText {
        labels.append(label)
        return EntityRelationshipText(decodedAt: labels.count - 1)
    }
}
