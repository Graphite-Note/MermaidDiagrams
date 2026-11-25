/**
 * File: ReferenceUseCaseDiagramPublishing.swift
 * ---------------------------------------------
 * Layer: Tests
 * Description: The last steps of resolving a use case diagram, as Pele's resolveUsecase takes them: each element
 *              checked and published in the order first mentioned, the boundaries' members, the notes, and the class
 *              definitions, classes and styles given to their targets.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

@testable import MermaidDiagrams

extension ReferenceUseCaseDiagramBuilder {
    /// Each element checked in the order it was added, then the actors and use cases in the order first mentioned,
    /// and the boundaries with their members.
    mutating func publishElements() throws(ReferenceUseCaseBuildFailure) {
        for identifier in elementOrder {
            guard let state = elements[identifier] else { continue }
            try checkGeometry(of: state)
        }
        for identifier in inMentionOrder(elementOrder) {
            guard let state = elements[identifier] else { continue }
            let parent = namedParent(state.parent).map { parent in drafts.boundaries[parent].name.identifier }
            if state.kind == .actor {
                diagram.actors.append(UseCaseActor(identifier: identifier, label: state.name.label.text, labelType: state.name.label.type,
                                                   type: state.icon != nil ? .icon : state.actorType ?? .normal, icon: state.icon,
                                                   isBusiness: state.isBusiness ?? false, stereotype: state.stereotype, parentIdentifier: parent,
                                                   classes: state.classes, styles: []))
            } else {
                diagram.useCases.append(UseCase(identifier: identifier, label: state.name.label.text, labelType: state.name.label.type,
                                                shape: state.shape ?? .ellipse, isBusiness: state.isBusiness ?? false, stereotype: state.stereotype,
                                                parentIdentifier: parent, classes: state.classes, styles: []))
            }
        }
        publishBoundaries()
    }

    /// An icon goes with a plain figure only, and a business element with a figure or an oval.
    private func checkGeometry(of state: ReferenceUseCaseElementState) throws(ReferenceUseCaseBuildFailure) {
        let identifier = state.name.identifier
        guard state.kind == .actor else {
            if state.shape == .rectangle, state.isBusiness == true { throw contradiction(.rectangularBusinessUseCase(identifier: identifier), at: state.name.start) }
            return
        }
        if state.icon != nil, let type = state.actorType, type != .normal {
            throw contradiction(.iconWithActorType(actor: identifier, type: type), at: state.name.start)
        }
        if state.isBusiness == true, state.icon != nil || state.actorType == .awesome {
            throw contradiction(.businessActorGeometry(actor: identifier), at: state.name.start)
        }
    }

    /// Each boundary with the elements declared in it, in the order written, and its type.
    private mutating func publishBoundaries() {
        // Without boundaries no element has a parent, and there is nothing to publish.
        guard !drafts.boundaries.isEmpty else { return }
        let declarations = drafts.elements.enumerated().sorted { first, second in
            first.element.name.start != second.element.name.start ? first.element.name.start < second.element.name.start : first.offset < second.offset
        }
        var placed: Set<Membership> = []
        for (_, draft) in declarations {
            guard let parent = namedParent(draft.parent) else { continue }
            let boundary = drafts.boundaries[parent].name.identifier
            if placed.insert(Membership(boundary: boundary, element: draft.name.identifier)).inserted {
                boundaries[boundary]?.members.append(draft.name.identifier)
            }
        }
        diagram.systemBoundaries = inMentionOrder(boundaryOrder).compactMap { identifier in
            boundaries[identifier].map { state in
                UseCaseSystemBoundary(identifier: identifier, label: state.name.label.text, labelType: state.name.label.type, type: state.type ?? .rectangle,
                                      members: state.members, classes: state.classes, styles: [])
            }
        }
    }

    /// The notes, each for an actor or a use case.
    mutating func resolveNotes() throws(ReferenceUseCaseBuildFailure) {
        for (place, note) in drafts.notes.enumerated() {
            guard let origin = symbols[note.target] else { throw contradiction(.unresolvedNoteTarget(identifier: note.target), at: note.start) }
            guard origin.kind == .actor || origin.kind == .useCase else {
                throw contradiction(.noteTargetKind(identifier: note.target, kind: origin.kind), at: note.start)
            }
            diagram.notes.append(UseCaseNote(identifier: "note-\(place)", target: note.target, label: note.label.text, labelType: note.label.type))
        }
    }

    /// The class definitions, each name in its first place with its last styles, then `class` and `style` statements.
    mutating func applyClassesAndStyles() throws(ReferenceUseCaseBuildFailure) {
        var definitionPlaces: [String: Int] = [:]
        for definition in drafts.classDefinitions {
            for identifier in definition.identifiers {
                if let place = definitionPlaces[identifier] {
                    diagram.classDefinitions[place].styles = definition.styles
                } else {
                    definitionPlaces[identifier] = diagram.classDefinitions.count
                    diagram.classDefinitions.append(UseCaseClassDefinition(identifier: identifier, styles: definition.styles))
                }
            }
        }
        // Only `class` and `style` statements look anything up.
        guard !drafts.classAssignments.isEmpty || !drafts.styles.isEmpty else { return }
        let places = StylablePlaces(diagram: diagram)
        for assignment in drafts.classAssignments {
            for target in assignment.targets {
                try modifyStylable(target.identifier, at: target.start, places: places) { classes, _ in Self.appendUnique(assignment.classes, to: &classes) }
            }
        }
        for (target, start, styles) in drafts.styles {
            try modifyStylable(target, at: start, places: places) { _, written in written.append(contentsOf: styles) }
        }
    }

    /// Where each id's element, boundary, JSON table and relationship is in the diagram.
    private struct StylablePlaces {
        let actors: [String: Int]
        let useCases: [String: Int]
        let boundaries: [String: Int]
        let jsonNodes: [String: Int]

        init(diagram: ReferenceUseCaseDiagram) {
            func places(_ identifiers: [String]) -> [String: Int] {
                Dictionary(identifiers.enumerated().map { place, identifier in (identifier, place) }, uniquingKeysWith: { first, _ in first })
            }
            actors = places(diagram.actors.map(\.identifier))
            useCases = places(diagram.useCases.map(\.identifier))
            boundaries = places(diagram.systemBoundaries.map(\.identifier))
            jsonNodes = places(diagram.jsonNodes.map(\.identifier))
        }
    }

    /// An element placed in a boundary.
    private struct Membership: Hashable {
        let boundary: String
        let element: String
    }

    /// The classes and styles of what `identifier` names changed by `change`: an actor, a use case, a boundary or a
    /// JSON table by its kind, else a relationship by its id.
    private mutating func modifyStylable(_ identifier: String, at start: Int, places: StylablePlaces,
                                         _ change: (inout [String], inout [String]) -> Void) throws(ReferenceUseCaseBuildFailure) {
        switch symbols[identifier]?.kind {
        case .actor?:
            if let place = places.actors[identifier] { return Self.change(&diagram.actors[place], change) }
        case .useCase?:
            if let place = places.useCases[identifier] { return Self.change(&diagram.useCases[place], change) }
        case .boundary?:
            if let place = places.boundaries[identifier] { return Self.change(&diagram.systemBoundaries[place], change) }
        case .json?:
            if let place = places.jsonNodes[identifier] { return Self.change(&diagram.jsonNodes[place], change) }
        default:
            if let place = relationshipPlaces[identifier] { return Self.change(&diagram.relationships[place], change) }
        }
        throw contradiction(.unresolvedStyleTarget(identifier: identifier), at: start)
    }

    // The 0.7.0 builder changed each item through a protocol its types conformed to in its own module; a test module
    // cannot make them conform with their setters internal there, so the same change is written out for each type.
    private static func change(_ item: inout UseCaseActor, _ change: (inout [String], inout [String]) -> Void) {
        change(&item.classes, &item.styles)
    }

    private static func change(_ item: inout UseCase, _ change: (inout [String], inout [String]) -> Void) {
        change(&item.classes, &item.styles)
    }

    private static func change(_ item: inout UseCaseSystemBoundary, _ change: (inout [String], inout [String]) -> Void) {
        change(&item.classes, &item.styles)
    }

    private static func change(_ item: inout UseCaseJSONNode, _ change: (inout [String], inout [String]) -> Void) {
        change(&item.classes, &item.styles)
    }

    private static func change(_ item: inout UseCaseRelationship, _ change: (inout [String], inout [String]) -> Void) {
        change(&item.classes, &item.styles)
    }
}
