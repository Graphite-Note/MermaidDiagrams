/**
 * File: UseCaseGraph.swift
 * ------------------------
 * Layer: Core
 * Description: A read use case diagram as what is drawn, as Pele's buildUsecaseGraph ports Mermaid's getData: every
 *              actor, use case, note, JSON table and boundary as a node with its class styles, and every relationship
 *              and note connector as an edge with its marks.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
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
    /// Mermaid's classes of the node (`default usecase-actor usecase-actor-normal`).
    let classNames: String
    /// The styles of its classes, then its own.
    let styles: [String]
    var actorType: UseCaseActorType?
    var isBusiness = false
    var stereotype: String?
    var parentIdentifier: String?
    var jsonRows: [UseCaseJSONRow]?
    var boundaryType: UseCaseBoundaryType?

    var isGroup: Bool { shape == .systemBoundary }
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
    let classNames: String
    let styles: [String]
    let isAnimated: Bool
    let minimumLength: Int
    /// The dotted line from a note to what it is about.
    var isNoteConnector: Bool { relationshipType == nil }

    /// `include` and `extend`, labelled with their kind.
    var isSemantic: Bool { relationshipType == .include || relationshipType == .extend }
}

/// The nodes in Pele's order (actors, use cases, notes, JSON tables, boundaries) and the edges (relationships, then
/// notes' connectors).
struct UseCaseGraph {
    var nodes: [UseCaseGraphNode] = []
    var edges: [UseCaseGraphEdge] = []

    /// Start and end marks for each arrow, in the order of `UseCaseArrow`.
    private static let arrowMarkers: [(UseCaseMarker, UseCaseMarker)] = [(.none, .point), (.point, .none), (.none, .none), (.none, .circle),
                                                                         (.none, .cross), (.circle, .none), (.cross, .none)]

    init(_ diagram: UseCaseDiagram) {
        let styles = UseCaseClassStyles(diagram.classDefinitions)
        nodes = diagram.actors.map { actor in Self.node(of: actor, styles: styles) }
        for useCase in diagram.useCases { nodes.append(Self.node(of: useCase, styles: styles)) }
        for note in diagram.notes {
            nodes.append(UseCaseGraphNode(identifier: note.identifier, label: note.label, labelType: note.labelType, shape: .note, padding: 10,
                                          classNames: "default usecase-note", styles: styles.compiled([])))
        }
        for json in diagram.jsonNodes {
            var node = UseCaseGraphNode(identifier: json.identifier, label: json.identifier, labelType: .text, shape: .jsonTable, padding: 10,
                                        classNames: Self.classNames("default", "usecase-json-table", nil, nil, json.classes),
                                        styles: styles.compiled(json.classes) + json.styles)
            node.jsonRows = UseCaseJSONRow.rows(of: json.value)
            nodes.append(node)
        }
        for boundary in diagram.systemBoundaries {
            var node = UseCaseGraphNode(identifier: boundary.identifier, label: boundary.label, labelType: boundary.labelType, shape: .systemBoundary,
                                        padding: 20, classNames: Self.classNames("default", "system-boundary", "system-boundary-\(boundary.type.rawValue)",
                                                                                 nil, boundary.classes),
                                        styles: styles.compiled(boundary.classes) + boundary.styles)
            node.boundaryType = boundary.type
            nodes.append(node)
        }
        edges = diagram.relationships.map { relationship in Self.edge(of: relationship, styles: styles) }
        for note in diagram.notes {
            edges.append(UseCaseGraphEdge(identifier: note.identifier + "-edge", start: note.identifier, end: note.target, relationshipType: nil, isDotted: true,
                                          startMarker: .none, endMarker: .none, label: nil, labelType: nil,
                                          classNames: "default relationship relationship-note", styles: styles.compiled([]), isAnimated: false,
                                          minimumLength: 1))
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

    private static func node(of actor: UseCaseActor, styles: UseCaseClassStyles) -> UseCaseGraphNode {
        var node = UseCaseGraphNode(identifier: actor.identifier, label: actor.label, labelType: actor.labelType, shape: shape(of: actor.type), padding: 10,
                                    classNames: classNames("default", "usecase-actor", "usecase-actor-\(actor.type.rawValue)",
                                                           actor.isBusiness ? "usecase-business" : nil, actor.classes),
                                    styles: styles.compiled(actor.classes) + actor.styles)
        node.actorType = actor.type
        node.isBusiness = actor.isBusiness
        node.stereotype = actor.stereotype.flatMap { stereotype in stereotype.isEmpty ? nil : stereotype }
        node.parentIdentifier = actor.parentIdentifier
        return node
    }

    private static func node(of useCase: UseCase, styles: UseCaseClassStyles) -> UseCaseGraphNode {
        let isEllipse = useCase.shape == .ellipse
        var node = UseCaseGraphNode(identifier: useCase.identifier, label: useCase.label, labelType: useCase.labelType,
                                    shape: !isEllipse ? .rectangle : useCase.isBusiness ? .businessEllipse : .ellipse, padding: isEllipse ? 20 : 10,
                                    classNames: classNames("default", "usecase-element", "usecase-\(useCase.shape.rawValue)",
                                                           useCase.isBusiness ? "usecase-business" : nil, useCase.classes),
                                    styles: styles.compiled(useCase.classes) + useCase.styles)
        node.isBusiness = useCase.isBusiness
        node.stereotype = useCase.stereotype.flatMap { stereotype in stereotype.isEmpty ? nil : stereotype }
        node.parentIdentifier = useCase.parentIdentifier
        return node
    }

    private static func edge(of relationship: UseCaseRelationship, styles: UseCaseClassStyles) -> UseCaseGraphEdge {
        let isSemantic = relationship.type == .include || relationship.type == .extend
        let markers: (UseCaseMarker, UseCaseMarker) = switch relationship.type {
        case .generalization: (.none, .hollowTriangle)
        case .association: arrowMarkers[relationship.arrow.rawValue]
        case .include, .extend: arrowMarkers[UseCaseArrow.solidArrow.rawValue]
        }
        let isAnimated = relationship.isAnimated || relationship.animation != nil
        let animationClass = isAnimated ? "edge-animation-" + (relationship.animation ?? .fast).rawValue : nil
        // Include and extend are labelled with their kind, whatever label the relationship carries.
        let label = isSemantic ? relationship.type.rawValue : relationship.type == .association ? relationship.label : nil
        let labelType: UseCaseLabelType? = isSemantic ? .text : relationship.type == .association ? relationship.labelType : nil
        return UseCaseGraphEdge(identifier: relationship.identifier, start: relationship.source, end: relationship.target,
                                relationshipType: relationship.type, isDotted: isSemantic, startMarker: markers.0, endMarker: markers.1,
                                label: label, labelType: labelType,
                                classNames: (["default", "relationship", "relationship-\(relationship.type.rawValue)"] + relationship.classes
                                    + (animationClass.map { [$0] } ?? [])).joined(separator: " "),
                                styles: styles.compiled(relationship.classes) + relationship.styles, isAnimated: relationship.isAnimated,
                                minimumLength: relationship.minimumLength)
    }

    private static func classNames(_ first: String, _ second: String, _ third: String?, _ business: String?, _ classes: [String]) -> String {
        ([first, second] + [third, business].compactMap { name in name } + classes).filter { name in !name.isEmpty }.joined(separator: " ")
    }
}

/// The styles of the class definitions, by class: a later class wins a property but keeps the place the property
/// first took, as Pele's `compiled` gives them; the class `default` applies to everything.
struct UseCaseClassStyles {
    private var stylesByClass: [String: [String]] = [:]

    init(_ definitions: [UseCaseClassDefinition]) {
        for definition in definitions { stylesByClass[definition.identifier] = definition.styles }
    }

    func compiled(_ classes: [String]) -> [String] {
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
