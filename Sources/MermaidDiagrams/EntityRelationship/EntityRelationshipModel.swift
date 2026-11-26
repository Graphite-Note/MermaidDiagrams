/**
 * File: EntityRelationshipModel.swift
 * -----------------------------------
 * Layer: Core
 * Description: An entity relationship diagram as its reading keeps it: flat records of byte ranges into its text (the
 *              entities, their attributes in one list, the relationships, the groups with their members in one list),
 *              each text a range decoded when read, and the few labels decoded already (groups' titles, values set in
 *              code) in one list.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

/// A text of an entity relationship diagram as its model keeps it: a range of the model's text, decoded when it is drawn
/// or read as plain text or as Markdown, or the index of a label decoded already in the model's `labels`.
struct EntityRelationshipText: Sendable {
    enum Kind: UInt8, Sendable {
        case plain, markdown, decoded
    }

    var range: MermaidTextRange
    var kind: Kind

    static let none = EntityRelationshipText(range: .empty, kind: .plain)

    /// A name's text as Mermaid draws it: quoted, Markdown; bare or a number, as it is.
    init(name range: MermaidTextRange, form: EntityRelationshipNameForm) {
        self.init(range: range, kind: form == .quoted ? .markdown : .plain)
    }

    init(range: MermaidTextRange, kind: Kind) {
        self.range = range
        self.kind = kind
    }

    /// The label at `index` of the model's `labels`.
    init(decodedAt index: Int) {
        self.init(range: MermaidTextRange(start: index, end: index), kind: .decoded)
    }

    var decodedIndex: Int { range.lowerBound }
}

/// An entity: its name's range, what its box shows (its name or its first alias), and its attributes, `attributeCount` of
/// the model's `attributes` from `firstAttribute`.
struct EntityRelationshipEntityRecord: Sendable {
    var identifier: MermaidTextRange
    var label: EntityRelationshipText
    var hasAlias = false
    var firstAttribute: Int32 = 0
    var attributeCount: Int32 = 0

    var attributeIndices: Range<Int> { Int(firstAttribute)..<Int(firstAttribute + attributeCount) }
}

/// An attribute row. Read from a text (`isWritten`), its type and name are the words written, the type's `?` within its
/// range unless whitespace stood before it (`appendsQuestionMark`), their pairs of `~` read as angle brackets when they
/// are made text, and its comment a range of Markdown; set in code, they are the texts themselves and the comment a label
/// decoded already. Its keys are packed two bits each, in the order written, when there are four at most, else
/// `keyCount` of the model's `keys` from `keyStart`.
struct EntityRelationshipAttributeRecord: Sendable {
    var type: MermaidTextRange
    var name: MermaidTextRange
    var comment: EntityRelationshipText
    var hasComment: Bool
    var isWritten: Bool
    var appendsQuestionMark: Bool
    var keyCount: Int32
    var keyStart: Int32

    /// The most keys packed in `keyStart`.
    static let packedKeyLimit = 4
}

/// A relationship by its entities' indexes, its cardinalities, its line and its label.
struct EntityRelationshipRelationshipRecord: Sendable {
    var firstEntityIndex: Int32
    var secondEntityIndex: Int32
    var firstEntityCardinality: EntityRelationshipCardinality
    var secondEntityCardinality: EntityRelationshipCardinality
    var identification: EntityRelationshipIdentification
    var label: EntityRelationshipText
}

/// A `subgraph` group: its identifier's range, its title (a label of the model's `labels`), its direction, and what it
/// holds directly, `entityCount` entities' indexes then `childCount` groups' indexes of the model's `members` from
/// `firstMember`.
struct EntityRelationshipGroupRecord: Sendable {
    var identifier: MermaidTextRange
    var title: Int32
    var direction: FlowchartDirection?
    var firstMember: Int32 = 0
    var entityCount: Int32 = 0
    var childCount: Int32 = 0

    var entityIndices: Range<Int> { Int(firstMember)..<Int(firstMember + entityCount) }
    var childIndices: Range<Int> { Int(firstMember + entityCount)..<Int(firstMember + entityCount + childCount) }
}

/// An entity relationship diagram's content as flat records over `text`. A usual diagram is its text, the entities, the
/// attributes and the relationships: no String, no label, no list per entity.
struct EntityRelationshipModel: Sendable {
    var text: [UInt8] = []
    var entities: [EntityRelationshipEntityRecord] = []
    var attributes: [EntityRelationshipAttributeRecord] = []
    /// The keys of the attributes that hold more than `EntityRelationshipAttributeRecord.packedKeyLimit`.
    var keys: [EntityRelationshipAttributeKey] = []
    var relationships: [EntityRelationshipRelationshipRecord] = []
    var groups: [EntityRelationshipGroupRecord] = []
    var members: [Int32] = []
    var labels: [DiagramLabel] = []
    /// For each entity, the first group to end whose identifier is its name, which it stands for, or -1; empty for a
    /// diagram without groups.
    var representedGroups: [Int32] = []

    func string(_ range: MermaidTextRange) -> String {
        precondition(range.start >= 0 && range.start <= range.end && range.upperBound <= text.count, "range outside the diagram's text")
        return text.withUnsafeBufferPointer { bytes in String(decoding: UnsafeBufferPointer(rebasing: bytes[range.lowerBound..<range.upperBound]), as: UTF8.self) }
    }

    /// `text` as a label: decoded from its range in its form, or the label decoded already.
    func label(_ text: EntityRelationshipText) -> DiagramLabel {
        switch text.kind {
        case .decoded: return labels[text.decodedIndex]
        case .plain, .markdown:
            let range = text.range
            precondition(range.start >= 0 && range.start <= range.end && range.upperBound <= self.text.count, "range outside the diagram's text")
            return self.text.withUnsafeBufferPointer { bytes in
                DiagramLabelDecoder.label(fromUTF8: UnsafeBufferPointer(rebasing: bytes[range.lowerBound..<range.upperBound]),
                                          form: text.kind == .markdown ? .markdown : .plain)
            }
        }
    }

    /// Key `index` of `attribute`'s keys, in the order written.
    func key(_ index: Int, of attribute: EntityRelationshipAttributeRecord) -> EntityRelationshipAttributeKey {
        precondition(index >= 0 && index < Int(attribute.keyCount), "key outside its attribute")
        guard Int(attribute.keyCount) > EntityRelationshipAttributeRecord.packedKeyLimit else {
            switch (attribute.keyStart >> (2 * Int32(index))) & 3 {
            case 1: return .foreign
            case 2: return .unique
            default: return .primary
            }
        }
        return keys[Int(attribute.keyStart) + index]
    }

    /// The two bits that name `key` when packed.
    static func packedBits(of key: EntityRelationshipAttributeKey) -> Int32 {
        switch key {
        case .primary: 0
        case .foreign: 1
        case .unique: 2
        }
    }
}
