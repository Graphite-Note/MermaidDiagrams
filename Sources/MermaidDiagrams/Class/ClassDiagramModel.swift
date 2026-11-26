/**
 * File: ClassDiagramModel.swift
 * -----------------------------
 * Layer: Core
 * Description: A class diagram as flat records over its text: each class a few numbers whose identifier, generic type
 *              and label are ranges of the source, its members runs of one list of shown bytes, its relations and
 *              notes records whose texts are ranges or labels, kept behind one reference once read; the public classes,
 *              relations and notes made from them when asked.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

/// A text of a class diagram: a range of the source the label decoder reads as written (one line, trimmed), a label
/// decoded when it was read or made by a caller, or none.
struct ClassDiagramText: Equatable, Sendable {
    let start: Int32
    let end: Int32
    /// Index into `ClassDiagramModel.labels`, `sourceRange`, or `absent`.
    let labelIndex: Int32

    static let sourceRange: Int32 = -1
    static let absent: Int32 = -2
    static let none = ClassDiagramText(start: 0, end: 0, labelIndex: absent)

    init(start: Int32, end: Int32, labelIndex: Int32) {
        self.start = start
        self.end = end
        self.labelIndex = labelIndex
    }

    init(range: MermaidTextRange) {
        self.init(start: range.start, end: range.end, labelIndex: Self.sourceRange)
    }

    var isNone: Bool { labelIndex == Self.absent }
    var isSourceRange: Bool { labelIndex == Self.sourceRange }
    var range: MermaidTextRange { MermaidTextRange(start: Int(start), end: Int(end)) }
}

/// A class: its identifier and generic type, ranges of the text or written strings; its label, none when it is its
/// identifier as written; its annotations and members, runs of the model's lists.
struct ClassDiagramClassRecord: Equatable, Sendable {
    var identifier: MermaidTextRange
    /// Index into `ClassDiagramModel.strings` of an identifier not in the text (made by a caller), -1 for a range.
    var writtenIdentifierIndex: Int32 = -1
    /// `ClassDiagramText.none` while the class is labelled by its identifier.
    var label = ClassDiagramText.none
    /// The generic type's range (`Name~T~`), or -1 as its start for none; `writtenGenericIndex` for one made by a caller.
    var genericStart: Int32 = -1
    var genericEnd: Int32 = -1
    var writtenGenericIndex: Int32 = -1
    var firstAnnotation: Int32 = 0
    var annotationCount: Int32 = 0
    /// The attributes, then the methods, from `firstMember`.
    var firstMember: Int32 = 0
    var attributeCount: Int32 = 0
    var methodCount: Int32 = 0

    var hasGenericType: Bool { genericStart >= 0 || writtenGenericIndex >= 0 }
    var annotationIndices: Range<Int> { Int(firstAnnotation)..<Int(firstAnnotation + annotationCount) }
    var memberIndices: Range<Int> { Int(firstMember)..<Int(firstMember + attributeCount + methodCount) }
}

/// A member as shown: a range of the model's shown bytes, and its classifier.
struct ClassDiagramMemberRecord: Equatable, Sendable {
    let start: Int32
    let end: Int32
    let classifier: ClassDiagramMemberClassifier
    let isMethod: Bool
}

/// A relation between two classes, or a class and an interface of its own (`interfaceIndex(_:)` as an end).
struct ClassDiagramRelationRecord: Equatable, Sendable {
    let source: Int32
    let target: Int32
    let sourceEnd: ClassDiagramRelationEnd
    let targetEnd: ClassDiagramRelationEnd
    let line: ClassDiagramLineStyle
    let sourceCardinality: String?
    let targetCardinality: String?
    let label: ClassDiagramText

    /// An end that is the interface at `index` of the model's interfaces.
    static func interfaceEnd(_ index: Int) -> Int32 { -1 - Int32(index) }
    static func interfaceIndex(of end: Int32) -> Int? { end < 0 ? Int(-1 - end) : nil }
}

struct ClassDiagramNoteRecord: Equatable, Sendable {
    let text: ClassDiagramText
    var classIndex: Int32 = -1
}

/// The records of a class diagram over its text, which they index, as the reader writes them.
struct ClassDiagramRecords: Sendable {
    var text: MermaidSourceText
    var classes: [ClassDiagramClassRecord] = []
    /// Every class's annotations, each class's in a run.
    var annotations: [String] = []
    /// Every class's members, each class's attributes then methods in a run.
    var members: [ClassDiagramMemberRecord] = []
    /// The members' shown texts, one after another.
    var memberBytes: [UInt8] = []
    var relations: [ClassDiagramRelationRecord] = []
    /// The interfaces of lollipop ends: each the range of the name its end writes, or a label made by a caller.
    var interfaces: [ClassDiagramText] = []
    var notes: [ClassDiagramNoteRecord] = []
    /// The texts decoded when read, which `ClassDiagramText.labelIndex` indexes.
    var labels: [DiagramLabel] = []
    /// Identifiers and generic types made by a caller.
    var strings: [String] = []

    init(text: MermaidSourceText) {
        self.text = text
    }

    mutating func written(_ label: DiagramLabel) -> ClassDiagramText {
        labels.append(label)
        return ClassDiagramText(start: 0, end: 0, labelIndex: Int32(labels.count - 1))
    }

}

/// The records of a class diagram once read, behind one reference, so that a diagram, a layout or a measuring that holds
/// them retains one object rather than each of their lists; none changes once made.
final class ClassDiagramModel: Sendable {
    let text: MermaidSourceText
    let classes: [ClassDiagramClassRecord]
    let annotations: [String]
    let members: [ClassDiagramMemberRecord]
    let memberBytes: [UInt8]
    let relations: [ClassDiagramRelationRecord]
    let interfaces: [ClassDiagramText]
    let notes: [ClassDiagramNoteRecord]
    let labels: [DiagramLabel]
    let strings: [String]

    init(_ records: consuming ClassDiagramRecords) {
        text = records.text
        classes = records.classes
        annotations = records.annotations
        members = records.members
        memberBytes = records.memberBytes
        relations = records.relations
        interfaces = records.interfaces
        notes = records.notes
        labels = records.labels
        strings = records.strings
    }

    /// The identifier of the class at `index`.
    func identifier(ofClassAt index: Int) -> String {
        let record = classes[index]
        if record.writtenIdentifierIndex >= 0 { return strings[Int(record.writtenIdentifierIndex)] }
        return text.string(record.identifier)
    }

    func genericType(ofClassAt index: Int) -> String? {
        let record = classes[index]
        if record.writtenGenericIndex >= 0 { return strings[Int(record.writtenGenericIndex)] }
        return record.genericStart < 0 ? nil : text.string(MermaidTextRange(start: Int(record.genericStart), end: Int(record.genericEnd)))
    }

    /// `text` as the label 0.7.0 read: decoded from its range, which reads as one line trimmed, or the label kept.
    func label(_ text: ClassDiagramText) -> DiagramLabel {
        guard text.isSourceRange else { return labels[Int(text.labelIndex)] }
        return self.text.withBytes { bytes in
            DiagramLabelDecoder.label(fromUTF8: UnsafeBufferPointer(rebasing: bytes[Int(text.start)..<Int(text.end)]), form: .plain)
        }
    }

    /// The label of the class at `index`: the label written for it, else its identifier as written.
    func label(ofClassAt index: Int) -> DiagramLabel {
        let record = classes[index]
        return record.label.isNone ? DiagramLabel(identifier(ofClassAt: index)) : label(record.label)
    }

    func memberText(at index: Int) -> String {
        let member = members[index]
        return memberBytes.withUnsafeBufferPointer { bytes in
            String(decoding: UnsafeBufferPointer(rebasing: bytes[Int(member.start)..<Int(member.end)]), as: UTF8.self)
        }
    }

    /// The interface at `index` as its end names it.
    func interfaceLabel(at index: Int) -> DiagramLabel {
        let interface = interfaces[index]
        return interface.isSourceRange ? DiagramLabel(text.string(interface.range)) : labels[Int(interface.labelIndex)]
    }
}
