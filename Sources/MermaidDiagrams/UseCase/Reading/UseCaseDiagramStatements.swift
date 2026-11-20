/**
 * File: UseCaseDiagramStatements.swift
 * ------------------------------------
 * Layer: Core
 * Description: The steps of resolving a use case diagram after its declarations, as Pele's resolveUsecase takes them:
 *              relationships and the use cases their ends make, metadata, the elements checked and published, notes,
 *              and classes and styles.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

extension UseCaseDiagramBuilder {
    /// The boundaries' places and the JSON tables, in the order first mentioned.
    mutating func publishBoundariesAndJSON() {
        let jsonPlaces = Dictionary(drafts.jsons.enumerated().map { place, json in (json.identifier, place) }, uniquingKeysWith: { first, _ in first })
        diagram.jsonNodes = inMentionOrder(drafts.jsons.map(\.identifier)).compactMap { identifier in
            jsonPlaces[identifier].map { place in
                UseCaseJSONNode(identifier: identifier, value: drafts.jsons[place].value, classes: drafts.jsons[place].classes, styles: [])
            }
        }
    }

    /// An end of a relationship that nothing declares becomes a use case.
    private mutating func resolveEndpoint(_ end: UseCaseDraftEndpoint) throws(UseCaseBuildFailure) -> UseCaseSymbolKind {
        if end.isClassed, !end.declares { throw contradiction(.classedEndpointNotDeclared(identifier: end.name.identifier), at: end.name.start) }
        if let origin = symbols[end.name.identifier] { return origin.kind }
        elements[end.name.identifier] = UseCaseElementState(name: end.name, kind: .useCase, shape: .ellipse, classes: [])
        elementOrder.append(end.name.identifier)
        register(end.name, as: .useCase)
        mention(end.name.identifier, at: end.name.start)
        return .useCase
    }

    mutating func resolveRelationships() throws(UseCaseBuildFailure) {
        var anonymousCount = 0
        for draft in drafts.relationships {
            let sourceKind = try resolveEndpoint(draft.source)
            let targetKind = try resolveEndpoint(draft.target)
            try check(draft, sourceKind: sourceKind, targetKind: targetKind)
            let identifier = draft.identifier ?? "edge-\(anonymousCount)"
            if draft.identifier == nil { anonymousCount += 1 }
            relationshipPlaces[identifier] = diagram.relationships.count
            diagram.relationships.append(UseCaseRelationship(
                identifier: identifier, hasExplicitIdentifier: draft.identifier != nil, source: draft.source.name.identifier,
                target: draft.target.name.identifier, type: draft.type, arrow: draft.arrow, label: draft.label?.text, labelType: draft.label?.type,
                minimumLength: draft.minimumLength, classes: [], styles: [], isAnimated: false, animation: nil))
        }
    }

    /// The kinds a relationship's ends and its type allow.
    private func check(_ draft: UseCaseDraftRelationship, sourceKind: UseCaseSymbolKind, targetKind: UseCaseSymbolKind) throws(UseCaseBuildFailure) {
        let related: Set<UseCaseSymbolKind> = [.actor, .useCase, .json]
        if !related.contains(sourceKind) {
            throw contradiction(.relationshipEndpointKind(identifier: draft.source.name.identifier, isSource: true, kind: sourceKind), at: draft.source.name.start)
        }
        if !related.contains(targetKind) {
            throw contradiction(.relationshipEndpointKind(identifier: draft.target.name.identifier, isSource: false, kind: targetKind), at: draft.target.name.start)
        }
        if draft.type == .include || draft.type == .extend, sourceKind != .useCase || targetKind != .useCase {
            throw contradiction(.relationshipNeedsUseCases(draft.type), at: draft.start)
        }
        if draft.type == .generalization, sourceKind == .json || sourceKind != targetKind {
            throw contradiction(.generalizationEndpoints, at: draft.start)
        }
        if draft.type == .association, sourceKind == .json || targetKind == .json, draft.arrow.rawValue > UseCaseArrow.lineSolid.rawValue {
            throw contradiction(.jsonRelationshipMarks(source: draft.source.name.identifier, target: draft.target.name.identifier), at: draft.start)
        }
    }

    /// A declaration's metadata must agree with an earlier one's; a metadata statement replaces what was said.
    mutating func applyMetadata(_ properties: [UseCaseDraftProperty], to state: inout UseCaseElementState, replacing: Bool) throws(UseCaseBuildFailure) {
        for property in properties {
            if state.kind == .actor {
                try applyActorProperty(property, to: &state, replacing: replacing)
            } else if property.key == "business", let value = property.value.boolean {
                if !replacing, let previous = state.isBusiness, previous != value {
                    throw contradiction(.conflictingBusinessMetadata(useCase: state.name.identifier), at: property.keyStart)
                }
                state.isBusiness = value
            } else {
                throw contradiction(.invalidMetadataProperty(target: state.name.identifier, key: property.key, kind: .useCase), at: property.keyStart)
            }
        }
    }

    private func applyActorProperty(_ property: UseCaseDraftProperty, to state: inout UseCaseElementState, replacing: Bool) throws(UseCaseBuildFailure) {
        func clash(_ previous: UseCaseMetadataValue?) throws(UseCaseBuildFailure) {
            guard !replacing, let previous, previous != property.value else { return }
            throw contradiction(.conflictingActorMetadata(actor: state.name.identifier, key: property.key), at: property.keyStart)
        }
        let text = property.value.text
        if property.key == "type", let text, let type = UseCaseActorType(rawValue: text), type != .icon {
            try clash(state.actorType.map { type in .text(type.rawValue) })
            state.actorType = type
        } else if property.key == "icon", let text {
            try clash(state.icon.map(UseCaseMetadataValue.text))
            state.icon = text
        } else if property.key == "business", let value = property.value.boolean {
            try clash(state.isBusiness.map(UseCaseMetadataValue.boolean))
            state.isBusiness = value
        } else {
            throw contradiction(.invalidMetadataProperty(target: state.name.identifier, key: property.key, kind: .actor), at: property.keyStart)
        }
    }

    /// `Id@{ … }` statements in order: for an actor or a use case, its metadata; a boundary's `type`; a relationship's
    /// `animate` and `animation`.
    mutating func applyMetadataStatements() throws(UseCaseBuildFailure) {
        for (target, start, properties) in drafts.metadata {
            guard let origin = symbols[target] else {
                throw contradiction(.unresolvedMetadataTarget(identifier: target, impliedKind: Self.impliedKind(of: properties)), at: start)
            }
            if origin.kind == .actor || origin.kind == .useCase, var state = elements[target] {
                try applyMetadata(properties, to: &state, replacing: true)
                elements[target] = state
                continue
            }
            for property in properties {
                let text = property.value.text
                if origin.kind == .boundary, property.key == "type", let text, let type = UseCaseBoundaryType(rawValue: text), boundaries[target] != nil {
                    boundaries[target]?.type = type
                } else if origin.kind == .edge, let place = relationshipPlaces[target], property.key == "animate", let value = property.value.boolean {
                    diagram.relationships[place].isAnimated = value
                } else if origin.kind == .edge, let place = relationshipPlaces[target], property.key == "animation", let text,
                          let animation = UseCaseAnimation(rawValue: text) {
                    diagram.relationships[place].animation = animation
                    diagram.relationships[place].isAnimated = true
                } else {
                    throw contradiction(.invalidMetadataProperty(target: target, key: property.key, kind: origin.kind), at: property.keyStart)
                }
            }
        }
        for place in diagram.relationships.indices where diagram.relationships[place].animation != nil { diagram.relationships[place].isAnimated = true }
    }

    /// The kind of element the keys of a metadata block could only belong to, for the error.
    static func impliedKind(of properties: [UseCaseDraftProperty]) -> UseCaseSymbolKind? {
        var possible: Set<UseCaseSymbolKind> = [.actor, .useCase, .boundary, .edge]
        for property in properties {
            switch property.key {
            case "icon": possible = [.actor]
            case "animate", "animation": possible = [.edge]
            case "type":
                let text = property.value.text
                possible = text == "rect" || text == "package" ? [.boundary] : text == "normal" || text == "hollow" || text == "awesome" ? [.actor] : []
            case "business": possible.subtract([.boundary, .edge])
            default: return nil
            }
        }
        return possible.count == 1 ? possible.first : nil
    }
}
