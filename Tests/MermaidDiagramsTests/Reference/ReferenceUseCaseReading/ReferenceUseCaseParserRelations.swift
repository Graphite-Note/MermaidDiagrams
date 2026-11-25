/**
 * File: ReferenceUseCaseParserRelations.swift
 * -------------------------------------------
 * Layer: Tests
 * Description: The statements of a use case diagram that declare elements and relate them, and its system boundaries,
 *              as Pele's parser.ts reads them: actor lists, entities, relationship operators with their labels and
 *              lengths, and the lines of a boundary.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

@testable import MermaidDiagrams

/// What follows a relationship's source: its explicit id, operator, label and target.
struct ReferenceUseCaseRelationTail {
    var identifier: (text: String, start: Int)?
    var type = UseCaseRelationshipType.association
    var arrow = UseCaseArrow.solidArrow
    var label: ReferenceUseCaseDraftLabel?
    var minimumLength = 1
    var target: ReferenceUseCaseParsedItem?
    var start = 0
}

extension ReferenceUseCaseParser {
    /// `actor A, B` declares several actors; at the top level `actor A --> B` declares one and relates it.
    mutating func actors(isTopLevel: Bool) throws(MermaidDiagramReadError) {
        index += 1
        var items = [try element(isActor: true)]
        var tail: ReferenceUseCaseRelationTail?
        if current == .comma {
            repeat {
                index += 1
                items.append(try element(isActor: true))
            } while current == .comma
        } else if isTopLevel, current.isIn(.relation) {
            tail = try relationTail()
        }
        try lineEnd()
        for item in items { drafts.elements.append(draft(item, kind: .actor)) }
        if let tail { relate(items[0], declares: true, tail: tail) }
    }

    /// A use case declared (`Login`, `Login(Sign in)`, `"Reset password"`), or, at the top level, related.
    mutating func entity(isTopLevel: Bool) throws(MermaidDiagramReadError) {
        var source = try element(isActor: false)
        let tail = isTopLevel && current.isIn(.relation) ? try relationTail() : nil
        try lineEnd()
        if tail == nil {
            source.isExplicit = true
            source.shape = source.shape ?? .ellipse
        }
        if source.isExplicit { drafts.elements.append(draft(source, kind: .useCase)) }
        if let tail { relate(source, declares: source.isExplicit, tail: tail) }
    }

    /// `systemBoundary Name …`, the actors and use cases declared on its lines, then `end`.
    mutating func boundary() throws(MermaidDiagramReadError) {
        index += 1
        var named = try name(allowingBrackets: true)
        let inline = current == .metadataStart ? try metadata() : nil
        if current == .classSeparator { try classSuffix(&named.classes) }
        try lineEnd()
        drafts.boundaries.append(ReferenceUseCaseDraftBoundary(name: named.name, classes: named.classes))
        parent = drafts.boundaries.count - 1
        while current.isIn(.boundaryLine) {
            try line(isTopLevel: false)
            try checkCounts()
        }
        parent = nil
        _ = try expect(.endKeyword)
        try lineEnd()
        if let inline { drafts.metadata.append((named.name.identifier, named.name.start, inline)) }
    }

    func draft(_ item: ReferenceUseCaseParsedItem, kind: ReferenceUseCaseElementKind) -> ReferenceUseCaseDraftElement {
        ReferenceUseCaseDraftElement(name: item.name, kind: kind, parent: parent, shape: item.shape, metadata: item.metadata, stereotype: item.stereotype,
                            classes: item.classes)
    }

    private mutating func relate(_ source: ReferenceUseCaseParsedItem, declares: Bool, tail: ReferenceUseCaseRelationTail) {
        guard let target = tail.target else { return }
        if target.isExplicit { drafts.elements.append(draft(target, kind: .useCase)) }
        drafts.relationships.append(ReferenceUseCaseDraftRelationship(
            source: ReferenceUseCaseDraftEndpoint(name: source.name, declares: declares, isClassed: !source.classes.isEmpty),
            target: ReferenceUseCaseDraftEndpoint(name: target.name, declares: target.isExplicit, isClassed: !target.classes.isEmpty),
            start: tail.start, identifier: tail.identifier?.text, identifierStart: tail.identifier?.start, type: tail.type, arrow: tail.arrow,
            label: tail.label, minimumLength: tail.minimumLength))
    }

    /// Whether a label and then one of `closers` (or `--`) come next.
    private func isLabeledAhead(closedBy closers: ReferenceUseCaseTokenSet) -> Bool {
        guard current.isLabelOrString else { return false }
        var position = index + 1
        while true {
            let kind = self.kind(at: position)
            if kind == .markerlessSolid || (!closers.isEmpty && kind.isIn(closers)) { return true }
            if !kind.isLabelOrString { return false }
            position += 1
        }
    }

    /// Each dash beyond the second asks for one more rank between the two ends.
    private func minimumLength(of token: Int) -> Int {
        let dashes = tokens.ends[token] - tokens.starts[token] - (tokens.kinds[token] == .markerlessSolid ? 0 : 1)
        return max(1, dashes - 1)
    }

    /// An explicit id (`login@`), an operator with its label where it takes one, and the target.
    mutating func relationTail() throws(MermaidDiagramReadError) -> ReferenceUseCaseRelationTail {
        var tail = ReferenceUseCaseRelationTail(start: tokens.starts[index])
        if current == .identifier, kind(at: index + 1) == .at {
            tail.identifier = (image(index), tokens.starts[index])
            index += 2
        }
        let operatorToken = index
        index += 1
        switch tokens.kinds[operatorToken] {
        case .dependencyArrow:
            _ = try expect(.colon)
            guard current == .include || current == .extend else { throw unexpected(.includeOrExtend) }
            tail.type = current == .include ? .include : .extend
            tail.label = ReferenceUseCaseDraftLabel(text: tail.type.rawValue, type: .text, start: tokens.starts[index])
            index += 1
        case .generalization: tail.type = .generalization
        case .forwardSolid: tail.minimumLength = minimumLength(of: operatorToken)
        case .backwardSolid: try readBackward(operatorToken, into: &tail)
        case .markerlessSolid: try readMarkerless(operatorToken, into: &tail)
        case .forwardCircle: tail.arrow = .circleArrow
        case .forwardCross: tail.arrow = .crossArrow
        case .backwardCircle, .backwardCross:
            tail.arrow = tokens.kinds[operatorToken] == .backwardCircle ? .circleArrowReversed : .crossArrowReversed
            if isLabeledAhead(closedBy: []) {
                tail.label = try label()
                _ = try expect(.markerlessSolid)
            }
        default:
            index -= 1
            throw unexpected(.relationshipOperator)
        }
        tail.target = try element(isActor: false)
        return tail
    }

    /// `<--`, and only the shortest one opens a label: `A <-- label -- B`.
    private mutating func readBackward(_ operatorToken: Int, into tail: inout ReferenceUseCaseRelationTail) throws(MermaidDiagramReadError) {
        tail.arrow = .backArrow
        guard tokens.ends[operatorToken] - tokens.starts[operatorToken] == 3, isLabeledAhead(closedBy: []) else {
            tail.minimumLength = minimumLength(of: operatorToken)
            return
        }
        tail.label = try label()
        tail.minimumLength = minimumLength(of: try expect(.markerlessSolid))
    }

    /// `--`, or `-- label` closed by `-->`, `--`, `--o` or `--x`, which give its marks.
    private mutating func readMarkerless(_ operatorToken: Int, into tail: inout ReferenceUseCaseRelationTail) throws(MermaidDiagramReadError) {
        tail.arrow = .lineSolid
        guard tokens.ends[operatorToken] - tokens.starts[operatorToken] == 2, isLabeledAhead(closedBy: .closesLabel) else {
            tail.minimumLength = minimumLength(of: operatorToken)
            return
        }
        tail.label = try label()
        switch current {
        case .forwardSolid: tail.arrow = .solidArrow
        case .forwardCircle: tail.arrow = .circleArrow
        case .forwardCross: tail.arrow = .crossArrow
        case .markerlessSolid: break
        default: throw unexpected(.labelClosingOperator)
        }
        if tail.arrow == .solidArrow || tail.arrow == .lineSolid { tail.minimumLength = minimumLength(of: index) }
        index += 1
    }
}
