/**
 * File: UseCaseGraph.swift
 * ------------------------
 * Layer: Core
 * Description: A read use case diagram as what is drawn, as Pele's buildUsecaseGraph ports Mermaid's getData: every
 *              actor, use case, note, JSON table and boundary as a node with its class styles, and every relationship
 *              and note connector as an edge with its marks; Mermaid's class names made only when read.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 25/11/2026
 */

import CoreGraphics

/// A node's shape, by Mermaid's names of them.
enum UseCaseNodeShape: String {
    case actor = "usecaseActor"
    case hollowActor = "usecaseActorHollow"
    case awesomeActor = "usecaseActorAwesome"
    case iconActor = "usecaseActorIcon"
    case ellipse = "usecaseEllipse"
    case businessEllipse = "usecaseBusiness"
    case rectangle = "rect"
    case note
    case jsonTable = "usecaseJsonTable"
    case systemBoundary = "usecaseSystemBoundary"
}

/// The mark at an end of an edge, by Mermaid's names of them; a generalization's is a hollow triangle (`extension`).
public enum UseCaseMarker: String, Equatable, Sendable {
    case none
    case point = "arrow_point"
    case circle = "arrow_circle"
    case cross = "arrow_cross"
    case hollowTriangle = "extension"
}

struct UseCaseGraphNode {
    let identifier: String
    let label: String
    let labelType: UseCaseLabelType
    let shape: UseCaseNodeShape
    let padding: CGFloat
    /// What Mermaid's classes of the node are made of, which no drawing reads: `classNames` joins them when read.
    let classNameParts: UseCaseNodeClassNames
    /// The styles of its classes, then its own.
    let styles: [String]
    var actorType: UseCaseActorType?
    var isBusiness = false
    var stereotype: String?
    var parentIdentifier: String?
    var jsonRows: [UseCaseJSONRow]?
    var boundaryType: UseCaseBoundaryType?

    var isGroup: Bool { shape == .systemBoundary }

    /// Mermaid's classes of the node (`default usecase-actor usecase-actor-normal`).
    var classNames: String { classNameParts.joined }
}

/// The parts of a node's class names, kept without joining them: the kind (`usecase-actor`), the variant's prefix and
/// name (`usecase-actor-` and `normal`), whether it is a business element, and the classes written.
struct UseCaseNodeClassNames {
    let kind: String
    let variantPrefix: String
    let variant: String?
    let isBusiness: Bool
    let classes: [String]

    /// The names that are not empty, `default` first, a space between each two.
    var joined: String {
        var joined = "default"
        func add(_ name: String) {
            guard !name.isEmpty else { return }
            joined += " "
            joined += name
        }
        add(kind)
        if let variant { add(variantPrefix + variant) }
        if isBusiness { add("usecase-business") }
        for name in classes { add(name) }
        return joined
    }
}

struct UseCaseGraphEdge {
    let identifier: String
    let start: String
    let end: String
    /// The relationship's type, or nil for a note's connector.
    let relationshipType: UseCaseRelationshipType?
    let isDotted: Bool
    let startMarker: UseCaseMarker
    let endMarker: UseCaseMarker
    let label: String?
    let labelType: UseCaseLabelType?
    /// The classes written, and the animation's class (`edge-animation-fast`) for an animated relationship: Mermaid's class
    /// names, which no drawing reads, are made from them when read.
    let classes: [String]
    let animationClass: UseCaseAnimation?
    let styles: [String]
    let isAnimated: Bool
    let minimumLength: Int
    /// The dotted line from a note to what it is about.
    var isNoteConnector: Bool { relationshipType == nil }

    /// `include` and `extend`, labelled with their kind.
    var isSemantic: Bool { relationshipType == .include || relationshipType == .extend }

    /// Mermaid's classes of the edge (`default relationship relationship-include`).
    var classNames: String {
        var joined = "default relationship relationship-" + (relationshipType?.rawValue ?? "note")
        for name in classes {
            joined += " "
            joined += name
        }
        if let animationClass { joined += " edge-animation-" + animationClass.rawValue }
        return joined
    }
}

/// The nodes in Pele's order (actors, use cases, notes, JSON tables, boundaries) and the edges (relationships, then
/// notes' connectors).
struct UseCaseGraph {
    var nodes: [UseCaseGraphNode] = []
    var edges: [UseCaseGraphEdge] = []

    /// Start and end marks for each arrow, in the order of `UseCaseArrow`.
    private static let arrowMarkers: [(UseCaseMarker, UseCaseMarker)] = [(.none, .point), (.point, .none), (.none, .none), (.none, .circle),
                                                                         (.none, .cross), (.circle, .none), (.cross, .none)]

    /// The graph of the diagram's records, its Strings made from their bytes once.
    init(_ diagram: UseCaseDiagram) {
        let styles = UseCaseClassStyles(diagram.classDefinitions)
        nodes.reserveCapacity(diagram.actorRecords.count + diagram.useCaseRecords.count + diagram.noteRecords.count + diagram.jsonRecords.count
            + diagram.boundaryRecords.count)
        for record in diagram.actorRecords { nodes.append(Self.actorNode(record, of: diagram, styles: styles)) }
        for record in diagram.useCaseRecords { nodes.append(Self.useCaseNode(record, of: diagram, styles: styles)) }
        for (place, note) in diagram.noteRecords.enumerated() {
            nodes.append(UseCaseGraphNode(identifier: UseCaseDiagram.noteName(place), label: diagram.text.string(note.label.text), labelType: note.label.type,
                                          shape: .note, padding: 10,
                                          classNameParts: UseCaseNodeClassNames(kind: "usecase-note", variantPrefix: "", variant: nil, isBusiness: false, classes: []),
                                          styles: styles.compiled([])))
        }
        for json in diagram.jsonNodes {
            var node = UseCaseGraphNode(identifier: json.identifier, label: json.identifier, labelType: .text, shape: .jsonTable, padding: 10,
                                        classNameParts: UseCaseNodeClassNames(kind: "usecase-json-table", variantPrefix: "", variant: nil, isBusiness: false,
                                                                              classes: json.classes),
                                        styles: styles.compiled(json.classes) + json.styles)
            node.jsonRows = UseCaseJSONRow.rows(of: json.value)
            nodes.append(node)
        }
        for boundary in diagram.systemBoundaries {
            var node = UseCaseGraphNode(identifier: boundary.identifier, label: boundary.label, labelType: boundary.labelType, shape: .systemBoundary,
                                        padding: 20,
                                        classNameParts: UseCaseNodeClassNames(kind: "system-boundary", variantPrefix: "system-boundary-",
                                                                              variant: boundary.type.rawValue, isBusiness: false, classes: boundary.classes),
                                        styles: styles.compiled(boundary.classes) + boundary.styles)
            node.boundaryType = boundary.type
            nodes.append(node)
        }
        edges.reserveCapacity(diagram.relationshipRecords.count + diagram.noteRecords.count)
        for record in diagram.relationshipRecords { edges.append(Self.edge(of: record, in: diagram, styles: styles)) }
        for (place, note) in diagram.noteRecords.enumerated() {
            let identifier = UseCaseDiagram.noteName(place)
            edges.append(UseCaseGraphEdge(identifier: identifier + "-edge", start: identifier, end: diagram.name(note.target), relationshipType: nil, isDotted: true,
                                          startMarker: .none, endMarker: .none, label: nil, labelType: nil, classes: [], animationClass: nil,
                                          styles: styles.compiled([]), isAnimated: false, minimumLength: 1))
        }
    }

    private static func shape(of type: UseCaseActorType) -> UseCaseNodeShape {
        switch type {
        case .normal: .actor
        case .hollow: .hollowActor
        case .awesome: .awesomeActor
        case .icon: .iconActor
        }
    }

    /// A stereotype that is written and not empty, as a String.
    private static func stereotype(of record: UseCaseElementRecord, in diagram: UseCaseDiagram) -> String? {
        record.hasStereotype && !record.stereotype.isEmpty ? diagram.text.string(record.stereotype) : nil
    }

    private static func actorNode(_ record: UseCaseElementRecord, of diagram: UseCaseDiagram, styles: UseCaseClassStyles) -> UseCaseGraphNode {
        let classes = diagram.names(record.classes)
        var node = UseCaseGraphNode(identifier: diagram.name(record.name), label: diagram.text.string(record.label.text), labelType: record.label.type,
                                    shape: shape(of: record.actorType), padding: 10,
                                    classNameParts: UseCaseNodeClassNames(kind: "usecase-actor", variantPrefix: "usecase-actor-", variant: record.actorType.rawValue,
                                                                          isBusiness: record.isBusiness, classes: classes),
                                    styles: styles.compiled(classes) + diagram.styles(record.styles))
        node.actorType = record.actorType
        node.isBusiness = record.isBusiness
        node.stereotype = stereotype(of: record, in: diagram)
        node.parentIdentifier = diagram.parentName(record.parent)
        return node
    }

    private static func useCaseNode(_ record: UseCaseElementRecord, of diagram: UseCaseDiagram, styles: UseCaseClassStyles) -> UseCaseGraphNode {
        let isEllipse = record.shape == .ellipse
        let classes = diagram.names(record.classes)
        var node = UseCaseGraphNode(identifier: diagram.name(record.name), label: diagram.text.string(record.label.text), labelType: record.label.type,
                                    shape: !isEllipse ? .rectangle : record.isBusiness ? .businessEllipse : .ellipse, padding: isEllipse ? 20 : 10,
                                    classNameParts: UseCaseNodeClassNames(kind: "usecase-element", variantPrefix: "usecase-", variant: record.shape.rawValue,
                                                                          isBusiness: record.isBusiness, classes: classes),
                                    styles: styles.compiled(classes) + diagram.styles(record.styles))
        node.isBusiness = record.isBusiness
        node.stereotype = stereotype(of: record, in: diagram)
        node.parentIdentifier = diagram.parentName(record.parent)
        return node
    }

    private static func edge(of record: UseCaseRelationshipRecord, in diagram: UseCaseDiagram, styles: UseCaseClassStyles) -> UseCaseGraphEdge {
        let classes = diagram.names(record.classes)
        let relationship = (type: record.type, arrow: record.arrow, isAnimated: record.isAnimated, animation: record.animation,
                            label: record.hasLabel ? diagram.text.string(record.label.text) : nil, labelType: record.hasLabel ? record.label.type : nil)
        let isSemantic = relationship.type == .include || relationship.type == .extend
        let markers: (UseCaseMarker, UseCaseMarker) = switch relationship.type {
        case .generalization: (.none, .hollowTriangle)
        case .association: arrowMarkers[relationship.arrow.rawValue]
        case .include, .extend: arrowMarkers[UseCaseArrow.solidArrow.rawValue]
        }
        let isAnimated = relationship.isAnimated || relationship.animation != nil
        // Include and extend are labelled with their kind, whatever label the relationship carries.
        let label = isSemantic ? relationship.type.rawValue : relationship.type == .association ? relationship.label : nil
        let labelType: UseCaseLabelType? = isSemantic ? .text : relationship.type == .association ? relationship.labelType : nil
        return UseCaseGraphEdge(identifier: diagram.relationshipName(record), start: diagram.name(record.source), end: diagram.name(record.target),
                                relationshipType: relationship.type, isDotted: isSemantic, startMarker: markers.0, endMarker: markers.1,
                                label: label, labelType: labelType, classes: classes,
                                animationClass: isAnimated ? relationship.animation ?? .fast : nil,
                                styles: styles.compiled(classes) + diagram.styles(record.styles), isAnimated: relationship.isAnimated,
                                minimumLength: Int(record.minimumLength))
    }
}

/// The styles of the class definitions, by class: a later class wins a property but keeps the place the property
/// first took, as Pele's `compiled` gives them; the class `default` applies to everything.
struct UseCaseClassStyles {
    private var stylesByClass: [String: [String]] = [:]
    /// The styles of an element without classes, those of `default`: most elements', compiled once.
    private var stylesWithoutClasses: [String] = []

    init(_ definitions: [UseCaseClassDefinition]) {
        for definition in definitions { stylesByClass[definition.identifier] = definition.styles }
        stylesWithoutClasses = compiling([])
    }

    func compiled(_ classes: [String]) -> [String] {
        classes.isEmpty ? stylesWithoutClasses : compiling(classes)
    }

    private func compiling(_ classes: [String]) -> [String] {
        // With no class defined, no class has a style: nothing to look up.
        guard !stylesByClass.isEmpty else { return [] }
        var properties: [String] = []
        var declarations: [String: String] = [:]
        for name in ["default"] + classes {
            for written in stylesByClass[name] ?? [] {
                let style = UseCaseCharacters.trimmed(written)
                let property = UseCaseCharacters.trimmed(style.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? "")
                guard !property.isEmpty else { continue }
                if declarations[property] == nil { properties.append(property) }
                declarations[property] = style
            }
        }
        return properties.compactMap { property in declarations[property] }
    }
}
