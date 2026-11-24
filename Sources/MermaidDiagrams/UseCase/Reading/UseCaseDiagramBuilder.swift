/**
 * File: UseCaseDiagramBuilder.swift
 * ---------------------------------
 * Layer: Core
 * Description: Resolves what the use case parser read into a diagram once the whole text is read, as Pele's
 *              resolveUsecase (Mermaid's UsecaseModelBuilder) does: which ids are actors, use cases, boundaries, JSON
 *              tables or relationships, the order they appear in, and whether the statements about them agree.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

/// Why the drafts were not resolved: statements that contradict each other, at the offset of the one that does, or
/// more distinct nodes than the limit.
enum UseCaseBuildFailure: Error {
    case contradiction(UseCaseContradiction, offset: Int)
    case tooManyNodes
}

/// What an id was first declared as, and where.
struct UseCaseSymbolOrigin {
    let kind: UseCaseSymbolKind
    let start: Int
    let isGenerated: Bool
    /// The label a generated id was made from.
    let label: String?
}

/// An actor or a use case as its declarations build it up.
struct UseCaseElementState {
    let name: UseCaseDraftName
    let kind: UseCaseElementKind
    var parent: Int?
    var shape: UseCaseShape?
    var stereotype: String?
    var stereotypeStart: Int?
    var classes: [String]
    var actorType: UseCaseActorType?
    var icon: String?
    var isBusiness: Bool?
}

/// A system boundary as its declarations build it up.
struct UseCaseBoundaryState {
    let name: UseCaseDraftName
    var classes: [String]
    var type: UseCaseBoundaryType?
    var members: [String] = []
}

/// Resolves the drafts in Pele's order, so that of several contradictions the same one is reported.
struct UseCaseDiagramBuilder {
    let drafts: UseCaseDrafts
    var symbols: [String: UseCaseSymbolOrigin] = [:]
    var elements: [String: UseCaseElementState] = [:]
    /// The elements' ids in the order they were first added.
    var elementOrder: [String] = []
    var boundaries: [String: UseCaseBoundaryState] = [:]
    var boundaryOrder: [String] = []
    /// The offset at which each id is first mentioned, which decides the order of the diagram.
    var firstMention: [String: Int] = [:]
    var diagram = UseCaseDiagram()
    /// Each relationship's place in the diagram, by its id.
    var relationshipPlaces: [String: Int] = [:]

    static func diagram(from drafts: UseCaseDrafts, limits: MermaidDiagramLimits) throws(UseCaseBuildFailure) -> UseCaseDiagram {
        var builder = UseCaseDiagramBuilder(drafts: drafts)
        try builder.declare()
        builder.publishBoundariesAndJSON()
        try builder.resolveRelationships()
        try builder.applyMetadataStatements()
        try builder.publishElements()
        try builder.resolveNotes()
        try builder.applyClassesAndStyles()
        builder.diagram.direction = drafts.direction ?? .leftToRight
        builder.diagram.accessibilityTitle = drafts.accessibilityTitle
        builder.diagram.accessibilityDescription = Self.withoutIndentation(drafts.accessibilityDescription)
        let nodeCount = builder.diagram.actors.count + builder.diagram.useCases.count + builder.diagram.systemBoundaries.count
            + builder.diagram.notes.count + builder.diagram.jsonNodes.count
        guard nodeCount <= limits.maximumNodeCount else { throw .tooManyNodes }
        return builder.diagram
    }

    /// The text with each line break and the whitespace after it made one line break, as Mermaid's `accDescr` is.
    private static func withoutIndentation(_ text: String) -> String {
        var result = String.UnicodeScalarView()
        var isAfterLineBreak = false
        for scalar in text.unicodeScalars {
            if isAfterLineBreak, scalar.value <= 0xFFFF, UseCaseCharacters.isJavaScriptWhitespace(UInt16(scalar.value)) { continue }
            isAfterLineBreak = scalar == "\n"
            result.append(scalar)
        }
        return String(result)
    }

    func contradiction(_ contradiction: UseCaseContradiction, at offset: Int) -> UseCaseBuildFailure {
        .contradiction(contradiction, offset: offset)
    }

    mutating func mention(_ identifier: String, at offset: Int) {
        if let previous = firstMention[identifier], previous <= offset { return }
        firstMention[identifier] = offset
    }

    /// `identifiers` in the order they are first mentioned, those mentioned at one offset in their own order.
    func inMentionOrder(_ identifiers: [String]) -> [String] {
        guard identifiers.count > 1 else { return identifiers }
        // Each id's offset looked up once, not at every comparison of the sort.
        let offsets = identifiers.map { identifier in firstMention[identifier] ?? 0 }
        return identifiers.indices.sorted { first, second in
            offsets[first] != offsets[second] ? offsets[first] < offsets[second] : first < second
        }.map { place in identifiers[place] }
    }

    mutating func register(_ name: UseCaseDraftName, as kind: UseCaseSymbolKind) {
        symbols[name.identifier] = UseCaseSymbolOrigin(kind: kind, start: name.start, isGenerated: name.isGenerated, label: name.label.text)
    }

    /// An id means one thing in the whole diagram, and an id made from a label may be declared once.
    func claim(_ name: UseCaseDraftName, as kind: UseCaseSymbolKind) throws(UseCaseBuildFailure) {
        guard let origin = symbols[name.identifier] else { return }
        if origin.kind != kind { throw contradiction(.declaredAsTwoKinds(identifier: name.identifier, first: origin.kind, second: kind), at: name.start) }
        if origin.isGenerated || name.isGenerated { throw contradiction(.generatedIdentifierCollision(identifier: name.identifier), at: name.start) }
    }

    mutating func unique(_ identifier: String, as kind: UseCaseSymbolKind, at start: Int) throws(UseCaseBuildFailure) {
        if let previous = symbols[identifier] {
            throw contradiction(.declaredMoreThanOnce(identifier: identifier, first: previous.kind, second: kind), at: start)
        }
        symbols[identifier] = UseCaseSymbolOrigin(kind: kind, start: start, isGenerated: false, label: nil)
    }

    /// Every declaration, in the order written: elements, boundaries, JSON tables and relationships' explicit ids.
    private mutating func declare() throws(UseCaseBuildFailure) {
        enum Declaration {
            case element(Int), boundary(Int), json(Int), relationship(Int)
        }
        reserveRoom()
        var declarations: [(offset: Int, declaration: Declaration)] = []
        declarations.reserveCapacity(drafts.elements.count + drafts.boundaries.count + drafts.jsons.count + drafts.relationships.count)
        for relationship in drafts.relationships {
            mention(relationship.source.name.identifier, at: relationship.source.name.start)
            mention(relationship.target.name.identifier, at: relationship.target.name.start)
        }
        for (place, element) in drafts.elements.enumerated() {
            mention(element.name.identifier, at: element.name.start)
            declarations.append((element.name.start, .element(place)))
        }
        for (place, boundary) in drafts.boundaries.enumerated() {
            mention(boundary.name.identifier, at: boundary.name.start)
            declarations.append((boundary.name.start, .boundary(place)))
        }
        for (place, json) in drafts.jsons.enumerated() {
            mention(json.identifier, at: json.start)
            declarations.append((json.start, .json(place)))
        }
        for (place, relationship) in drafts.relationships.enumerated() where relationship.identifier != nil && relationship.identifierStart != nil {
            declarations.append((relationship.identifierStart ?? 0, .relationship(place)))
        }
        let ordered = declarations.enumerated().sorted { first, second in
            first.element.offset != second.element.offset ? first.element.offset < second.element.offset : first.offset < second.offset
        }
        for (_, (_, declaration)) in ordered {
            switch declaration {
            case .element(let place): try declareElement(drafts.elements[place])
            case .boundary(let place): try declareBoundary(drafts.boundaries[place])
            case .json(let place): try unique(drafts.jsons[place].identifier, as: .json, at: drafts.jsons[place].start)
            case .relationship(let place):
                let relationship = drafts.relationships[place]
                try unique(relationship.identifier ?? "", as: .edge, at: relationship.identifierStart ?? 0)
            }
        }
    }

    /// Room for every id the drafts can declare or mention, made once: each declaration, and both ends of each relationship.
    private mutating func reserveRoom() {
        let declarationCount = drafts.elements.count + drafts.boundaries.count + drafts.jsons.count + drafts.relationships.count
        firstMention.reserveCapacity(declarationCount + drafts.relationships.count)
        symbols.reserveCapacity(declarationCount + drafts.relationships.count)
        elements.reserveCapacity(drafts.elements.count + 2 * drafts.relationships.count)
    }

    /// The boundary a draft is declared in, when its title makes an id: one whose title makes none is no parent.
    func namedParent(_ parent: Int?) -> Int? {
        guard let parent, !drafts.boundaries[parent].name.identifier.isEmpty else { return nil }
        return parent
    }

    private mutating func declareElement(_ draft: UseCaseDraftElement) throws(UseCaseBuildFailure) {
        let kind: UseCaseSymbolKind = draft.kind == .actor ? .actor : .useCase
        try claim(draft.name, as: kind)
        guard var existing = elements[draft.name.identifier] else {
            var state = UseCaseElementState(name: draft.name, kind: draft.kind, parent: namedParent(draft.parent), shape: draft.shape,
                                            stereotype: draft.stereotype, stereotypeStart: draft.stereotype == nil ? nil : draft.name.start,
                                            classes: draft.classes)
            try applyMetadata(draft.metadata ?? [], to: &state, replacing: false)
            elements[draft.name.identifier] = state
            elementOrder.append(draft.name.identifier)
            register(draft.name, as: kind)
            return
        }
        try checkAgreement(of: draft, with: existing)
        existing.shape = existing.shape ?? draft.shape
        existing.parent = existing.parent ?? draft.parent
        if existing.stereotype == nil {
            existing.stereotype = draft.stereotype
            existing.stereotypeStart = draft.stereotype == nil ? nil : draft.name.start
        }
        Self.appendUnique(draft.classes, to: &existing.classes)
        try applyMetadata(draft.metadata ?? [], to: &existing, replacing: false)
        elements[draft.name.identifier] = existing
    }

    /// Two declarations of one element give it one label, shape, boundary and stereotype.
    private func checkAgreement(of draft: UseCaseDraftElement, with existing: UseCaseElementState) throws(UseCaseBuildFailure) {
        let identifier = draft.name.identifier
        if existing.name.label.text != draft.name.label.text || existing.name.label.type != draft.name.label.type {
            throw contradiction(.conflictingLabels(identifier: identifier), at: draft.name.start)
        }
        if let shape = draft.shape, let existingShape = existing.shape, shape != existingShape {
            throw contradiction(.conflictingShapes(useCase: identifier), at: draft.name.start)
        }
        if let parent = namedParent(draft.parent), let existingParent = namedParent(existing.parent),
           drafts.boundaries[parent].name.identifier != drafts.boundaries[existingParent].name.identifier {
            throw contradiction(.inMoreThanOneBoundary(identifier: identifier), at: drafts.boundaries[parent].name.start)
        }
        if let stereotype = draft.stereotype, let existingStereotype = existing.stereotype, stereotype != existingStereotype {
            throw contradiction(.conflictingStereotypes(identifier: identifier), at: draft.name.start)
        }
    }

    private mutating func declareBoundary(_ draft: UseCaseDraftBoundary) throws(UseCaseBuildFailure) {
        try claim(draft.name, as: .boundary)
        if var existing = boundaries[draft.name.identifier] {
            if existing.name.label.text != draft.name.label.text || existing.name.label.type != draft.name.label.type {
                throw contradiction(.conflictingBoundaryTitles(boundary: draft.name.identifier), at: draft.name.start)
            }
            Self.appendUnique(draft.classes, to: &existing.classes)
            boundaries[draft.name.identifier] = existing
            return
        }
        boundaries[draft.name.identifier] = UseCaseBoundaryState(name: draft.name, classes: draft.classes)
        boundaryOrder.append(draft.name.identifier)
        register(draft.name, as: .boundary)
    }

    static func appendUnique(_ values: [String], to target: inout [String]) {
        guard !values.isEmpty else { return }
        var seen = Set(target)
        for value in values where seen.insert(value).inserted { target.append(value) }
    }
}
