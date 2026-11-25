/**
 * File: UseCaseDiagramStatements.swift
 * ------------------------------------
 * Layer: Core
 * Description: The JSON tables, relationships and metadata of a use case diagram resolved as Pele's `resolveUsecase`
 *              resolves them: an end nothing declares made a use case, the kinds a relationship joins checked, a
 *              declaration's metadata agreeing with an earlier one's, a metadata statement replacing it.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 25/11/2026
 */

extension UseCaseDiagramBuilder {
    /// The JSON tables, in the order first mentioned, each id at the place of its first table.
    mutating func publishBoundariesAndJSON() {
        guard !drafts.jsons.isEmpty else { return }
        var firstPlaces: [Int32: Int] = [:]
        for (place, json) in drafts.jsons.enumerated() where firstPlaces[json.name] == nil { firstPlaces[json.name] = place }
        for mentioned in placesInMentionOrder(drafts.jsons.map(\.name)) {
            let name = drafts.jsons[mentioned].name
            guard let place = firstPlaces[name] else { continue }
            let draft = drafts.jsons[place]
            diagram.jsonValues.append(drafts.jsonValues[Int(draft.value)])
            diagram.jsonRecords.append(UseCaseJSONRecord(name: name, value: Int32(diagram.jsonValues.count - 1), classes: poolNames(draft.classes),
                                                         styles: .empty))
        }
    }

    /// `span` of the drafts' name pool copied to the diagram's.
    mutating func poolNames(_ span: UseCaseListSpan) -> UseCaseListSpan {
        guard !span.isEmpty else { return .empty }
        let start = diagram.namePool.count
        diagram.namePool.append(contentsOf: drafts.names[span.range])
        return UseCaseListSpan(start: Int32(start), count: span.count)
    }

    /// An end of a relationship that nothing declares becomes a use case.
    private mutating func resolveEndpoint(_ end: UseCaseDraftEndpoint) throws(UseCaseBuildFailure) -> UseCaseSymbolKind {
        if end.isClassed, !end.declares { throw contradiction(.classedEndpointNotDeclared(identifier: identifier(end.name.name)), at: end.name.start) }
        if let origin = nameStates[Int(end.name.name)].kind { return origin }
        nameStates[Int(end.name.name)].element = Int32(elements.count)
        elements.append(UseCaseElementState(name: end.name, kind: .useCase, parent: -1, shape: .ellipse))
        register(end.name, as: .useCase)
        mention(end.name.name, at: end.name.start)
        return .useCase
    }

    mutating func resolveRelationships() throws(UseCaseBuildFailure) {
        var anonymousCount: Int32 = 0
        diagram.relationshipRecords.reserveCapacity(drafts.relationships.count)
        for draft in drafts.relationships {
            let sourceKind = try resolveEndpoint(draft.source)
            let targetKind = try resolveEndpoint(draft.target)
            try check(draft, sourceKind: sourceKind, targetKind: targetKind)
            if draft.identifier >= 0 { nameStates[Int(draft.identifier)].relationship = Int32(diagram.relationshipRecords.count) }
            diagram.relationshipRecords.append(UseCaseRelationshipRecord(
                name: draft.identifier, anonymousNumber: draft.identifier >= 0 ? -1 : anonymousCount, source: draft.source.name.name,
                target: draft.target.name.name, type: draft.type, arrow: draft.arrow, label: draft.label, hasLabel: draft.hasLabel,
                minimumLength: draft.minimumLength, classes: .empty, styles: .empty, isAnimated: false, animation: nil))
            if draft.identifier < 0 { anonymousCount += 1 }
        }
    }

    /// The kinds a relationship's ends and its type allow.
    private func check(_ draft: UseCaseDraftRelationship, sourceKind: UseCaseSymbolKind, targetKind: UseCaseSymbolKind) throws(UseCaseBuildFailure) {
        func isRelated(_ kind: UseCaseSymbolKind) -> Bool { kind == .actor || kind == .useCase || kind == .json }
        if !isRelated(sourceKind) {
            throw contradiction(.relationshipEndpointKind(identifier: identifier(draft.source.name.name), isSource: true, kind: sourceKind),
                                at: draft.source.name.start)
        }
        if !isRelated(targetKind) {
            throw contradiction(.relationshipEndpointKind(identifier: identifier(draft.target.name.name), isSource: false, kind: targetKind),
                                at: draft.target.name.start)
        }
        if draft.type == .include || draft.type == .extend, sourceKind != .useCase || targetKind != .useCase {
            throw contradiction(.relationshipNeedsUseCases(draft.type), at: draft.start)
        }
        if draft.type == .generalization, sourceKind == .json || sourceKind != targetKind {
            throw contradiction(.generalizationEndpoints, at: draft.start)
        }
        if draft.type == .association, sourceKind == .json || targetKind == .json, draft.arrow.rawValue > UseCaseArrow.lineSolid.rawValue {
            throw contradiction(.jsonRelationshipMarks(source: identifier(draft.source.name.name), target: identifier(draft.target.name.name)),
                                at: draft.start)
        }
    }

    /// Whether a property's key is `key`.
    func isKey(_ property: UseCaseDraftProperty, _ key: StaticString) -> Bool { diagram.text.spells(property.key, key) }

    /// The text value of a property, or nil for `true` and `false`.
    func textValue(_ property: UseCaseDraftProperty) -> MermaidTextRange? { property.value.kind == .text ? property.value.text : nil }

    func booleanValue(_ property: UseCaseDraftProperty) -> Bool? { property.value.kind == .boolean ? property.value.boolean : nil }

    /// The actor type a text names (`normal`, `hollow`, `awesome`, `icon`), or nil.
    func actorType(_ text: MermaidTextRange) -> UseCaseActorType? {
        let spelled = diagram.text
        return spelled.spells(text, "normal") ? .normal : spelled.spells(text, "hollow") ? .hollow : spelled.spells(text, "awesome") ? .awesome
            : spelled.spells(text, "icon") ? .icon : nil
    }

    /// A declaration's metadata must agree with an earlier one's; a metadata statement replaces what was said.
    mutating func applyMetadata(_ span: UseCaseListSpan, to state: inout UseCaseElementState, replacing: Bool) throws(UseCaseBuildFailure) {
        for property in drafts.properties[span.range] {
            if state.kind == .actor {
                try applyActorProperty(property, to: &state, replacing: replacing)
            } else if isKey(property, "business"), let value = booleanValue(property) {
                if !replacing, let previous = state.isBusiness, previous != value {
                    throw contradiction(.conflictingBusinessMetadata(useCase: identifier(state.name.name)), at: property.keyStart)
                }
                state.isBusiness = value
            } else {
                throw contradiction(.invalidMetadataProperty(target: identifier(state.name.name), key: diagram.text.string(property.key), kind: .useCase),
                                    at: property.keyStart)
            }
        }
    }

    private func applyActorProperty(_ property: UseCaseDraftProperty, to state: inout UseCaseElementState, replacing: Bool) throws(UseCaseBuildFailure) {
        func clash() -> UseCaseBuildFailure {
            contradiction(.conflictingActorMetadata(actor: identifier(state.name.name), key: diagram.text.string(property.key)), at: property.keyStart)
        }
        let text = textValue(property)
        if isKey(property, "type"), let text, let type = actorType(text), type != .icon {
            if !replacing, let previous = state.actorType, previous != type { throw clash() }
            state.actorType = type
        } else if isKey(property, "icon"), let text {
            if !replacing, state.hasIcon, !diagram.text.spellSame(state.icon, text) { throw clash() }
            state.icon = text
            state.hasIcon = true
        } else if isKey(property, "business"), let value = booleanValue(property) {
            if !replacing, let previous = state.isBusiness, previous != value { throw clash() }
            state.isBusiness = value
        } else {
            throw contradiction(.invalidMetadataProperty(target: identifier(state.name.name), key: diagram.text.string(property.key), kind: .actor),
                                at: property.keyStart)
        }
    }

    /// `Id@{ … }` statements in order: for an actor or a use case, its metadata; a boundary's `type`; a relationship's
    /// `animate` and `animation`.
    mutating func applyMetadataStatements() throws(UseCaseBuildFailure) {
        for statement in drafts.metadata {
            let target = Int(statement.target)
            guard let origin = nameStates[target].kind else {
                throw contradiction(.unresolvedMetadataTarget(identifier: identifier(statement.target), impliedKind: impliedKind(of: statement.properties)),
                                    at: statement.start)
            }
            if origin == .actor || origin == .useCase, nameStates[target].element >= 0 {
                var state = elements[Int(nameStates[target].element)]
                try applyMetadata(statement.properties, to: &state, replacing: true)
                elements[Int(nameStates[target].element)] = state
                continue
            }
            for property in drafts.properties[statement.properties.range] {
                let text = textValue(property)
                let relationship = Int(nameStates[target].relationship)
                if origin == .boundary, isKey(property, "type"), let text, let type = boundaryType(text), nameStates[target].boundary >= 0 {
                    boundaries[Int(nameStates[target].boundary)].type = type
                } else if origin == .edge, relationship >= 0, isKey(property, "animate"), let value = booleanValue(property) {
                    diagram.relationshipRecords[relationship].isAnimated = value
                } else if origin == .edge, relationship >= 0, isKey(property, "animation"), let text, let animation = animation(text) {
                    diagram.relationshipRecords[relationship].animation = animation
                    diagram.relationshipRecords[relationship].isAnimated = true
                } else {
                    throw contradiction(.invalidMetadataProperty(target: identifier(statement.target), key: diagram.text.string(property.key), kind: origin),
                                        at: property.keyStart)
                }
            }
        }
        for place in diagram.relationshipRecords.indices where diagram.relationshipRecords[place].animation != nil {
            diagram.relationshipRecords[place].isAnimated = true
        }
    }

    private func boundaryType(_ text: MermaidTextRange) -> UseCaseBoundaryType? {
        diagram.text.spells(text, "rect") ? .rectangle : diagram.text.spells(text, "package") ? .package : nil
    }

    private func animation(_ text: MermaidTextRange) -> UseCaseAnimation? {
        diagram.text.spells(text, "fast") ? .fast : diagram.text.spells(text, "slow") ? .slow : nil
    }

    /// The kind of element the keys of a metadata block could only belong to, for the error.
    func impliedKind(of span: UseCaseListSpan) -> UseCaseSymbolKind? {
        var possible: Set<UseCaseSymbolKind> = [.actor, .useCase, .boundary, .edge]
        for property in drafts.properties[span.range] {
            if isKey(property, "icon") {
                possible = [.actor]
            } else if isKey(property, "animate") || isKey(property, "animation") {
                possible = [.edge]
            } else if isKey(property, "type") {
                let text = textValue(property)
                possible = text.map { text in boundaryType(text) != nil } == true ? [.boundary]
                    : text.map { text in actorType(text).map { type in type != .icon } ?? false } == true ? [.actor] : []
            } else if isKey(property, "business") {
                possible.subtract([.boundary, .edge])
            } else {
                return nil
            }
        }
        return possible.count == 1 ? possible.first : nil
    }
}
