/**
 * File: ReferenceUseCaseGraph.swift
 * ---------------------------------
 * Layer: Tests
 * Description: The 0.7.0 (de81532) use case layout kept as the reference the flat one is checked against. A read use
 *              case diagram as what is drawn, as Pele's buildUsecaseGraph ports Mermaid's getData: every actor, use
 *              case, note, JSON table and boundary as a node with its class styles, and every relationship and note
 *              connector as an edge with its marks.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

struct ReferenceUseCaseGraphNode {
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

struct ReferenceUseCaseGraphEdge {
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
struct ReferenceUseCaseGraph {
    var nodes: [ReferenceUseCaseGraphNode] = []
    var edges: [ReferenceUseCaseGraphEdge] = []

    /// Start and end marks for each arrow, in the order of `UseCaseArrow`.
    private static let arrowMarkers: [(UseCaseMarker, UseCaseMarker)] = [(.none, .point), (.point, .none), (.none, .none), (.none, .circle),
                                                                         (.none, .cross), (.circle, .none), (.cross, .none)]

    init(_ diagram: UseCaseDiagram) {
        let styles = ReferenceUseCaseClassStyles(diagram.classDefinitions)
        nodes.reserveCapacity(diagram.actors.count + diagram.useCases.count + diagram.notes.count + diagram.jsonNodes.count + diagram.systemBoundaries.count)
        for actor in diagram.actors { nodes.append(Self.node(of: actor, styles: styles)) }
        for useCase in diagram.useCases { nodes.append(Self.node(of: useCase, styles: styles)) }
        for note in diagram.notes {
            nodes.append(ReferenceUseCaseGraphNode(identifier: note.identifier, label: note.label, labelType: note.labelType, shape: .note, padding: 10,
                                          classNames: "default usecase-note", styles: styles.compiled([])))
        }
        for json in diagram.jsonNodes {
            var node = ReferenceUseCaseGraphNode(identifier: json.identifier, label: json.identifier, labelType: .text, shape: .jsonTable, padding: 10,
                                        classNames: Self.classNames("default", "usecase-json-table", nil, nil, json.classes),
                                        styles: styles.compiled(json.classes) + json.styles)
            node.jsonRows = UseCaseJSONRow.rows(of: json.value)
            nodes.append(node)
        }
        for boundary in diagram.systemBoundaries {
            var node = ReferenceUseCaseGraphNode(identifier: boundary.identifier, label: boundary.label, labelType: boundary.labelType, shape: .systemBoundary,
                                        padding: 20, classNames: Self.classNames("default", "system-boundary", "system-boundary-\(boundary.type.rawValue)",
                                                                                 nil, boundary.classes),
                                        styles: styles.compiled(boundary.classes) + boundary.styles)
            node.boundaryType = boundary.type
            nodes.append(node)
        }
        edges.reserveCapacity(diagram.relationships.count + diagram.notes.count)
        for relationship in diagram.relationships { edges.append(Self.edge(of: relationship, styles: styles)) }
        for note in diagram.notes {
            edges.append(ReferenceUseCaseGraphEdge(identifier: note.identifier + "-edge", start: note.identifier, end: note.target, relationshipType: nil, isDotted: true,
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

    private static func node(of actor: UseCaseActor, styles: ReferenceUseCaseClassStyles) -> ReferenceUseCaseGraphNode {
        var node = ReferenceUseCaseGraphNode(identifier: actor.identifier, label: actor.label, labelType: actor.labelType, shape: shape(of: actor.type), padding: 10,
                                    classNames: classNames("default", "usecase-actor", "usecase-actor-\(actor.type.rawValue)",
                                                           actor.isBusiness ? "usecase-business" : nil, actor.classes),
                                    styles: styles.compiled(actor.classes) + actor.styles)
        node.actorType = actor.type
        node.isBusiness = actor.isBusiness
        node.stereotype = actor.stereotype.flatMap { stereotype in stereotype.isEmpty ? nil : stereotype }
        node.parentIdentifier = actor.parentIdentifier
        return node
    }

    private static func node(of useCase: UseCase, styles: ReferenceUseCaseClassStyles) -> ReferenceUseCaseGraphNode {
        let isEllipse = useCase.shape == .ellipse
        var node = ReferenceUseCaseGraphNode(identifier: useCase.identifier, label: useCase.label, labelType: useCase.labelType,
                                    shape: !isEllipse ? .rectangle : useCase.isBusiness ? .businessEllipse : .ellipse, padding: isEllipse ? 20 : 10,
                                    classNames: classNames("default", "usecase-element", "usecase-\(useCase.shape.rawValue)",
                                                           useCase.isBusiness ? "usecase-business" : nil, useCase.classes),
                                    styles: styles.compiled(useCase.classes) + useCase.styles)
        node.isBusiness = useCase.isBusiness
        node.stereotype = useCase.stereotype.flatMap { stereotype in stereotype.isEmpty ? nil : stereotype }
        node.parentIdentifier = useCase.parentIdentifier
        return node
    }

    private static func edge(of relationship: UseCaseRelationship, styles: ReferenceUseCaseClassStyles) -> ReferenceUseCaseGraphEdge {
        let isSemantic = relationship.type == .include || relationship.type == .extend
        let markers: (UseCaseMarker, UseCaseMarker) = switch relationship.type {
        case .generalization: (.none, .hollowTriangle)
        case .association: arrowMarkers[relationship.arrow.rawValue]
        case .include, .extend: arrowMarkers[UseCaseArrow.solidArrow.rawValue]
        }
        let isAnimated = relationship.isAnimated || relationship.animation != nil
        var classNames = "default relationship relationship-" + relationship.type.rawValue
        for name in relationship.classes {
            classNames += " "
            classNames += name
        }
        if isAnimated { classNames += " edge-animation-" + (relationship.animation ?? .fast).rawValue }
        // Include and extend are labelled with their kind, whatever label the relationship carries.
        let label = isSemantic ? relationship.type.rawValue : relationship.type == .association ? relationship.label : nil
        let labelType: UseCaseLabelType? = isSemantic ? .text : relationship.type == .association ? relationship.labelType : nil
        return ReferenceUseCaseGraphEdge(identifier: relationship.identifier, start: relationship.source, end: relationship.target,
                                relationshipType: relationship.type, isDotted: isSemantic, startMarker: markers.0, endMarker: markers.1,
                                label: label, labelType: labelType,
                                classNames: classNames,
                                styles: styles.compiled(relationship.classes) + relationship.styles, isAnimated: relationship.isAnimated,
                                minimumLength: relationship.minimumLength)
    }

    /// The names that are not empty, a space between each two.
    private static func classNames(_ first: String, _ second: String, _ third: String?, _ business: String?, _ classes: [String]) -> String {
        var joined = ""
        func add(_ name: String) {
            guard !name.isEmpty else { return }
            if !joined.isEmpty { joined += " " }
            joined += name
        }
        add(first)
        add(second)
        if let third { add(third) }
        if let business { add(business) }
        for name in classes { add(name) }
        return joined
    }
}

/// The styles of the class definitions, by class: a later class wins a property but keeps the place the property
/// first took, as Pele's `compiled` gives them; the class `default` applies to everything.
struct ReferenceUseCaseClassStyles {
    private var stylesByClass: [String: [String]] = [:]

    init(_ definitions: [UseCaseClassDefinition]) {
        for definition in definitions { stylesByClass[definition.identifier] = definition.styles }
    }

    func compiled(_ classes: [String]) -> [String] {
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

/// A node measured: its texts, the size of what is drawn (the layout's box is larger when it carries loops), a JSON
/// table's rows, and a boundary's room around what it holds.
struct ReferenceUseCaseNodeView {
    let node: ReferenceUseCaseGraphNode
    var form = UseCaseNodeForm.box
    let look: UseCaseLook
    var label: DiagramTextBlock
    var stereotype: DiagramTextBlock
    var size = CGSize.zero
    var rows: [(key: DiagramTextBlock, value: DiagramTextBlock, height: CGFloat)] = []
    var keyColumnWidth: CGFloat = 0
    var headHeight: CGFloat = 0
    var loopCount = 0
    var clusterPadding = LayeredClusterPadding.none
    var clusterMinimumWidth: CGFloat = 0
}
