/**
 * File: UseCaseDiagramBuilder.swift
 * ---------------------------------
 * Layer: Core
 * Description: Resolves a use case diagram's drafts as Pele's `resolveUsecase` does: every id declared once as one kind
 *              of thing, its declarations agreeing, its order the order of first mention; the names looked up by their
 *              numbers in lists instead of by Strings in dictionaries.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 25/11/2026
 */

/// Why the drafts were not resolved: statements that contradict each other, at the offset of the one that does, or
/// more distinct nodes than the limit.
enum UseCaseBuildFailure: Error {
    case contradiction(UseCaseContradiction, offset: Int)
    case tooManyNodes
}

/// An actor or a use case as its declarations build it up.
struct UseCaseElementState {
    var name: UseCaseDraftName
    var kind: UseCaseElementKind
    /// The boundary it is declared in, by its place among the drafts' boundaries, or -1.
    var parent: Int32
    var shape: UseCaseShape?
    var stereotype = MermaidTextRange.empty
    var hasStereotype = false
    var classes: [Int32] = []
    var actorType: UseCaseActorType?
    var icon = MermaidTextRange.empty
    var hasIcon = false
    var isBusiness: Bool?
}

/// What the builder knows of one name: what it was first declared as (nil for nothing), where, whether the id was made
/// from a label; its actor's or use case's state, its boundary's state and its explicit relationship's place, or -1;
/// the offset at which it is first mentioned, `Int32.max` for none, which decides the order of the diagram; and the last
/// mark it was given while a list was made unique.
struct UseCaseNameState {
    var kind: UseCaseSymbolKind?
    var isGenerated = false
    var start: Int32 = 0
    var element: Int32 = -1
    var boundary: Int32 = -1
    var relationship: Int32 = -1
    var firstMention = Int32.max
    var mark: Int32 = 0
}

/// A system boundary as its declarations build it up.
struct UseCaseBoundaryState {
    var name: UseCaseDraftName
    var classes: [Int32]
    var type: UseCaseBoundaryType?
    var members: [Int32] = []
}

/// Resolves the drafts in Pele's order, so that of several contradictions the same one is reported. What 0.7.0 kept
/// in dictionaries keyed by ids is kept in lists by the ids' numbers.
struct UseCaseDiagramBuilder {
    let drafts: UseCaseDrafts
    var diagram = UseCaseDiagram()
    /// By name: what it was first declared as, where, its states' places and where it is first mentioned.
    var nameStates: [UseCaseNameState]
    /// The elements' and boundaries' states, in the order they were first added.
    var elements: [UseCaseElementState] = []
    var boundaries: [UseCaseBoundaryState] = []
    /// The last mark given out to the names of one list, so that a list is made unique in time that grows with it alone.
    var seenMark: Int32 = 0

    init(drafts: UseCaseDrafts, text: UseCaseBytes, nameRanges: [MermaidTextRange]) {
        self.drafts = drafts
        diagram.text = text
        diagram.nameRanges = nameRanges
        nameStates = Array(repeating: UseCaseNameState(), count: nameRanges.count)
    }

    mutating func build(limits: MermaidDiagramLimits) throws(UseCaseBuildFailure) {
        try declare()
        publishBoundariesAndJSON()
        try resolveRelationships()
        try applyMetadataStatements()
        try publishElements()
        try resolveNotes()
        try applyClassesAndStyles()
        diagram.direction = drafts.direction ?? .leftToRight
        diagram.accessibilityTitle = drafts.accessibilityTitle
        diagram.accessibilityDescription = Self.withoutIndentation(drafts.accessibilityDescription)
        let nodeCount = diagram.actorRecords.count + diagram.useCaseRecords.count + diagram.boundaryRecords.count + diagram.noteRecords.count
            + diagram.jsonRecords.count
        guard nodeCount <= limits.maximumNodeCount else { throw .tooManyNodes }
    }

    /// The text with each line break and the whitespace after it made one line break, as Mermaid's `accDescr` is.
    private static func withoutIndentation(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var result = String.UnicodeScalarView()
        var isAfterLineBreak = false
        for scalar in text.unicodeScalars {
            if isAfterLineBreak, scalar.value <= 0xFFFF, UseCaseCharacters.isJavaScriptWhitespace(UInt16(scalar.value)) { continue }
            isAfterLineBreak = scalar == "\n"
            result.append(scalar)
        }
        return String(result)
    }

    /// The String of the name numbered `number`, for an error.
    func identifier(_ number: Int32) -> String { diagram.name(number) }

    func contradiction(_ contradiction: UseCaseContradiction, at offset: Int32) -> UseCaseBuildFailure {
        .contradiction(contradiction, offset: Int(offset))
    }

    mutating func mention(_ name: Int32, at offset: Int32) {
        if nameStates[Int(name)].firstMention <= offset { return }
        nameStates[Int(name)].firstMention = offset
    }

    /// The places of `names` in the order their names are first mentioned, those mentioned at one offset in their own
    /// order.
    func placesInMentionOrder(_ names: [Int32]) -> [Int] {
        guard names.count > 1 else { return Array(names.indices) }
        // Each name's offset looked up once, not at every comparison of the sort.
        let offsets = names.map { name in nameStates[Int(name)].firstMention == Int32.max ? 0 : nameStates[Int(name)].firstMention }
        return names.indices.sorted { first, second in
            offsets[first] != offsets[second] ? offsets[first] < offsets[second] : first < second
        }
    }

    mutating func register(_ name: UseCaseDraftName, as kind: UseCaseSymbolKind) {
        nameStates[Int(name.name)].kind = kind
        nameStates[Int(name.name)].start = name.start
        nameStates[Int(name.name)].isGenerated = name.isGenerated
    }

    /// An id means one thing in the whole diagram, and an id made from a label may be declared once.
    func claim(_ name: UseCaseDraftName, as kind: UseCaseSymbolKind) throws(UseCaseBuildFailure) {
        guard let origin = nameStates[Int(name.name)].kind else { return }
        if origin != kind { throw contradiction(.declaredAsTwoKinds(identifier: identifier(name.name), first: origin, second: kind), at: name.start) }
        if nameStates[Int(name.name)].isGenerated || name.isGenerated {
            throw contradiction(.generatedIdentifierCollision(identifier: identifier(name.name)), at: name.start)
        }
    }

    mutating func unique(_ name: Int32, as kind: UseCaseSymbolKind, at start: Int32) throws(UseCaseBuildFailure) {
        if let previous = nameStates[Int(name)].kind {
            throw contradiction(.declaredMoreThanOnce(identifier: identifier(name), first: previous, second: kind), at: start)
        }
        nameStates[Int(name)].kind = kind
        nameStates[Int(name)].start = start
        nameStates[Int(name)].isGenerated = false
    }

    /// Every declaration, in the order written: elements, boundaries, JSON tables and relationships' explicit ids.
    private mutating func declare() throws(UseCaseBuildFailure) {
        enum Declaration {
            case element(Int), boundary(Int), json(Int), relationship(Int)
        }
        elements.reserveCapacity(drafts.elements.count + 2 * drafts.relationships.count)
        var declarations: [(offset: Int32, declaration: Declaration)] = []
        declarations.reserveCapacity(drafts.elements.count + drafts.boundaries.count + drafts.jsons.count + drafts.relationships.count)
        for relationship in drafts.relationships {
            mention(relationship.source.name.name, at: relationship.source.name.start)
            mention(relationship.target.name.name, at: relationship.target.name.start)
        }
        for (place, element) in drafts.elements.enumerated() {
            mention(element.name.name, at: element.name.start)
            declarations.append((element.name.start, .element(place)))
        }
        for (place, boundary) in drafts.boundaries.enumerated() {
            mention(boundary.name.name, at: boundary.name.start)
            declarations.append((boundary.name.start, .boundary(place)))
        }
        for (place, json) in drafts.jsons.enumerated() {
            mention(json.name, at: json.start)
            declarations.append((json.start, .json(place)))
        }
        for (place, relationship) in drafts.relationships.enumerated() where relationship.identifier >= 0 {
            declarations.append((relationship.identifierStart, .relationship(place)))
        }
        let ordered = declarations.enumerated().sorted { first, second in
            first.element.offset != second.element.offset ? first.element.offset < second.element.offset : first.offset < second.offset
        }
        for (_, (_, declaration)) in ordered {
            switch declaration {
            case .element(let place): try declareElement(drafts.elements[place])
            case .boundary(let place): try declareBoundary(drafts.boundaries[place])
            case .json(let place): try unique(drafts.jsons[place].name, as: .json, at: drafts.jsons[place].start)
            case .relationship(let place):
                let relationship = drafts.relationships[place]
                try unique(relationship.identifier, as: .edge, at: relationship.identifierStart)
            }
        }
    }

    /// The boundary a draft is declared in, when its title makes an id: one whose title makes none is no parent.
    func namedParent(_ parent: Int32) -> Int32 {
        guard parent >= 0, !diagram.nameRanges[Int(drafts.boundaries[Int(parent)].name.name)].isEmpty else { return -1 }
        return parent
    }

    private mutating func declareElement(_ draft: UseCaseDraftElement) throws(UseCaseBuildFailure) {
        let kind: UseCaseSymbolKind = draft.kind == .actor ? .actor : .useCase
        try claim(draft.name, as: kind)
        let place = nameStates[Int(draft.name.name)].element
        guard place >= 0 else {
            var state = UseCaseElementState(name: draft.name, kind: draft.kind, parent: namedParent(draft.parent), shape: draft.shape,
                                            stereotype: draft.stereotype, hasStereotype: draft.hasStereotype, classes: names(draft.classes))
            if draft.hasMetadata { try applyMetadata(draft.metadata, to: &state, replacing: false) }
            nameStates[Int(draft.name.name)].element = Int32(elements.count)
            elements.append(state)
            register(draft.name, as: kind)
            return
        }
        var existing = elements[Int(place)]
        try checkAgreement(of: draft, with: existing)
        existing.shape = existing.shape ?? draft.shape
        if existing.parent < 0 { existing.parent = draft.parent }
        if !existing.hasStereotype {
            existing.stereotype = draft.stereotype
            existing.hasStereotype = draft.hasStereotype
        }
        Self.appendUnique(drafts.names[draft.classes.range], to: &existing.classes, marks: &nameStates, mark: &seenMark)
        if draft.hasMetadata { try applyMetadata(draft.metadata, to: &existing, replacing: false) }
        elements[Int(place)] = existing
    }

    /// Two declarations of one element give it one label, shape, boundary and stereotype.
    private func checkAgreement(of draft: UseCaseDraftElement, with existing: UseCaseElementState) throws(UseCaseBuildFailure) {
        let name = draft.name.name
        if !isSameLabel(existing.name.label, draft.name.label) {
            throw contradiction(.conflictingLabels(identifier: identifier(name)), at: draft.name.start)
        }
        if let shape = draft.shape, let existingShape = existing.shape, shape != existingShape {
            throw contradiction(.conflictingShapes(useCase: identifier(name)), at: draft.name.start)
        }
        let parent = namedParent(draft.parent)
        let existingParent = namedParent(existing.parent)
        if parent >= 0, existingParent >= 0, drafts.boundaries[Int(parent)].name.name != drafts.boundaries[Int(existingParent)].name.name {
            throw contradiction(.inMoreThanOneBoundary(identifier: identifier(name)), at: drafts.boundaries[Int(parent)].name.start)
        }
        if draft.hasStereotype, existing.hasStereotype, !diagram.text.spellSame(draft.stereotype, existing.stereotype) {
            throw contradiction(.conflictingStereotypes(identifier: identifier(name)), at: draft.name.start)
        }
    }

    /// Whether two labels are one: the same text, as Swift compares Strings, and the same type.
    func isSameLabel(_ first: UseCaseLabelText, _ second: UseCaseLabelText) -> Bool {
        first.type == second.type && diagram.text.spellSame(first.text, second.text)
    }

    private mutating func declareBoundary(_ draft: UseCaseDraftBoundary) throws(UseCaseBuildFailure) {
        try claim(draft.name, as: .boundary)
        let place = nameStates[Int(draft.name.name)].boundary
        if place >= 0 {
            if !isSameLabel(boundaries[Int(place)].name.label, draft.name.label) {
                throw contradiction(.conflictingBoundaryTitles(boundary: identifier(draft.name.name)), at: draft.name.start)
            }
            Self.appendUnique(drafts.names[draft.classes.range], to: &boundaries[Int(place)].classes, marks: &nameStates, mark: &seenMark)
            return
        }
        nameStates[Int(draft.name.name)].boundary = Int32(boundaries.count)
        boundaries.append(UseCaseBoundaryState(name: draft.name, classes: names(draft.classes)))
        register(draft.name, as: .boundary)
    }

    /// The names of `span` of the drafts' name pool.
    func names(_ span: UseCaseListSpan) -> [Int32] { span.isEmpty ? [] : Array(drafts.names[span.range]) }

    /// `values` added to `target`, each that is not in it yet, in their order.
    /// `marks` holds a mark by name, and `mark` the last one given out.
    static func appendUnique<Names: Collection>(_ values: Names, to target: inout [Int32], marks: inout [UseCaseNameState], mark: inout Int32)
        where Names.Element == Int32 {
        guard !values.isEmpty else { return }
        mark += 1
        for name in target { marks[Int(name)].mark = mark }
        for name in values where marks[Int(name)].mark != mark {
            marks[Int(name)].mark = mark
            target.append(name)
        }
    }
}
