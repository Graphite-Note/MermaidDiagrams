/**
 * File: UseCaseDiagramViews.swift
 * -------------------------------
 * Layer: Core
 * Description: A use case diagram's actors, use cases, system boundaries, relationships, notes, JSON tables and class
 *              definitions made as values from its flat records each time they are read, and the Strings of its names
 *              and texts made from their bytes.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

extension UseCaseDiagram {
    /// Every actor, in the order its id is first mentioned. Made from the records each time it is read.
    public var actors: [UseCaseActor] {
        actorRecords.map { record in
            UseCaseActor(identifier: name(record.name), label: text.string(record.label.text), labelType: record.label.type, type: record.actorType,
                         icon: record.hasIcon ? text.string(record.icon) : nil, isBusiness: record.isBusiness,
                         stereotype: record.hasStereotype ? text.string(record.stereotype) : nil, parentIdentifier: parentName(record.parent),
                         classes: names(record.classes), styles: styles(record.styles))
        }
    }

    /// Every use case, in the order its id is first mentioned.
    public var useCases: [UseCase] {
        useCaseRecords.map { record in
            UseCase(identifier: name(record.name), label: text.string(record.label.text), labelType: record.label.type, shape: record.shape,
                    isBusiness: record.isBusiness, stereotype: record.hasStereotype ? text.string(record.stereotype) : nil,
                    parentIdentifier: parentName(record.parent), classes: names(record.classes), styles: styles(record.styles))
        }
    }

    /// Every system boundary, in the order its id is first mentioned.
    public var systemBoundaries: [UseCaseSystemBoundary] {
        boundaryRecords.map { record in
            UseCaseSystemBoundary(identifier: name(record.name), label: text.string(record.label.text), labelType: record.label.type, type: record.type,
                                  members: names(record.members), classes: names(record.classes), styles: styles(record.styles))
        }
    }

    /// Every relationship, in the order written.
    public var relationships: [UseCaseRelationship] {
        relationshipRecords.map { record in
            UseCaseRelationship(identifier: relationshipName(record), hasExplicitIdentifier: record.name >= 0, source: name(record.source),
                                target: name(record.target), type: record.type, arrow: record.arrow,
                                label: record.hasLabel ? text.string(record.label.text) : nil, labelType: record.hasLabel ? record.label.type : nil,
                                minimumLength: Int(record.minimumLength), classes: names(record.classes), styles: styles(record.styles),
                                isAnimated: record.isAnimated, animation: record.animation)
        }
    }

    /// Every note, in the order written.
    public var notes: [UseCaseNote] {
        noteRecords.enumerated().map { place, record in
            UseCaseNote(identifier: Self.noteName(place), target: name(record.target), label: text.string(record.label.text), labelType: record.label.type)
        }
    }

    /// Every JSON table, in the order its id is first mentioned.
    public var jsonNodes: [UseCaseJSONNode] {
        jsonRecords.map { record in
            UseCaseJSONNode(identifier: name(record.name), value: jsonValues[Int(record.value)], classes: names(record.classes), styles: styles(record.styles))
        }
    }

    /// `classDef` statements, each name once in the order first defined, its styles those of its last definition.
    public var classDefinitions: [UseCaseClassDefinition] {
        classDefinitionRecords.map { record in UseCaseClassDefinition(identifier: name(record.name), styles: styles(record.styles)) }
    }

    /// The String of the name numbered `number`.
    func name(_ number: Int32) -> String { text.string(nameRanges[Int(number)]) }

    func parentName(_ number: Int32) -> String? { number >= 0 ? name(number) : nil }

    /// A relationship's id: its explicit one, else `edge-` and its number among those without one.
    func relationshipName(_ record: UseCaseRelationshipRecord) -> String {
        record.name >= 0 ? name(record.name) : "edge-\(record.anonymousNumber)"
    }

    /// A note's id: `note-` and its place among the notes.
    static func noteName(_ place: Int) -> String { "note-\(place)" }

    /// The Strings of the names in `span` of the name pool.
    func names(_ span: UseCaseListSpan) -> [String] {
        span.isEmpty ? [] : namePool[span.range].map { number in name(number) }
    }

    /// The Strings of the styles in `span` of the style pool, as written.
    func styles(_ span: UseCaseListSpan) -> [String] {
        span.isEmpty ? [] : stylePool[span.range].map { range in text.string(range) }
    }
}
