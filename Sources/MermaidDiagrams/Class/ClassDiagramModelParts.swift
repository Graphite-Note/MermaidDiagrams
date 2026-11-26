/**
 * File: ClassDiagramModelParts.swift
 * ----------------------------------
 * Layer: Core
 * Description: A class diagram's records made into the public classes, relations and notes a host reads, and made from
 *              them for a diagram built by a caller rather than read, every text of which is then written.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

extension ClassDiagramRecords {
    /// A model of classes, relations and notes made by a caller: every identifier, generic type and member written,
    /// every text a label.
    init(classes: [ClassDiagramClass], relations: [ClassDiagramRelation], notes: [ClassDiagramNote]) {
        self.init(text: MermaidSourceText(bytes: []))
        for declared in classes {
            var record = ClassDiagramClassRecord(identifier: .empty, writtenIdentifierIndex: Int32(strings.count))
            strings.append(declared.identifier)
            record.label = written(declared.label)
            if let genericType = declared.genericType {
                record.writtenGenericIndex = Int32(strings.count)
                strings.append(genericType)
            }
            record.firstAnnotation = Int32(annotations.count)
            record.annotationCount = Int32(declared.annotations.count)
            annotations += declared.annotations
            record.firstMember = Int32(members.count)
            record.attributeCount = Int32(declared.attributes.count)
            record.methodCount = Int32(declared.methods.count)
            for member in declared.attributes { appendWritten(member, isMethod: false) }
            for member in declared.methods { appendWritten(member, isMethod: true) }
            self.classes.append(record)
        }
        for relation in relations {
            self.relations.append(ClassDiagramRelationRecord(source: end(relation.source), target: end(relation.target), sourceEnd: relation.sourceEnd,
                                                             targetEnd: relation.targetEnd, line: relation.line, sourceCardinality: relation.sourceCardinality,
                                                             targetCardinality: relation.targetCardinality,
                                                             label: relation.label.map { label in written(label) } ?? .none))
        }
        for note in notes { self.notes.append(ClassDiagramNoteRecord(text: written(note.text), classIndex: note.classIndex.map(Int32.init) ?? -1)) }
    }

    private mutating func appendWritten(_ member: ClassDiagramMember, isMethod: Bool) {
        let start = memberBytes.count
        memberBytes.append(contentsOf: member.text.utf8)
        members.append(ClassDiagramMemberRecord(start: Int32(start), end: Int32(memberBytes.count), classifier: member.classifier, isMethod: isMethod))
    }

    private mutating func end(_ endpoint: ClassDiagramRelationEndpoint) -> Int32 {
        switch endpoint {
        case .classIndex(let index): return Int32(index)
        case .interface(let label):
            interfaces.append(written(label))
            return ClassDiagramRelationRecord.interfaceEnd(interfaces.count - 1)
        }
    }

}

extension ClassDiagramModel {
    // MARK: The public parts

    func materializedClass(at index: Int) -> ClassDiagramClass {
        let record = classes[index]
        var attributes: [ClassDiagramMember] = []
        var methods: [ClassDiagramMember] = []
        for memberIndex in record.memberIndices {
            let member = ClassDiagramMember(text: memberText(at: memberIndex), classifier: members[memberIndex].classifier)
            if members[memberIndex].isMethod { methods.append(member) } else { attributes.append(member) }
        }
        return ClassDiagramClass(identifier: identifier(ofClassAt: index), label: label(ofClassAt: index), genericType: genericType(ofClassAt: index),
                                 annotations: Array(annotations[record.annotationIndices]), attributes: attributes, methods: methods)
    }

    func materializedRelation(at index: Int) -> ClassDiagramRelation {
        let record = relations[index]
        return ClassDiagramRelation(source: endpoint(record.source), target: endpoint(record.target), sourceEnd: record.sourceEnd, targetEnd: record.targetEnd,
                                    line: record.line, sourceCardinality: record.sourceCardinality, targetCardinality: record.targetCardinality,
                                    label: record.label.isNone ? nil : label(record.label))
    }

    private func endpoint(_ end: Int32) -> ClassDiagramRelationEndpoint {
        ClassDiagramRelationRecord.interfaceIndex(of: end).map { interface in .interface(interfaceLabel(at: interface)) } ?? .classIndex(Int(end))
    }

    func materializedNote(at index: Int) -> ClassDiagramNote {
        let record = notes[index]
        return ClassDiagramNote(text: label(record.text), classIndex: record.classIndex < 0 ? nil : Int(record.classIndex))
    }
}
