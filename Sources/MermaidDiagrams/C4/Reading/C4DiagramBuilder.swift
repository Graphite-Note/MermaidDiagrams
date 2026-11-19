/**
 * File: C4DiagramBuilder.swift
 * ----------------------------
 * Layer: Core
 * Description: Builds a C4 diagram from the parser's calls as Pele's db.ts does: each macro's positional arguments
 *              to the fields of their places, named ones to the fields they name, an alias written again merged into
 *              its element, boundaries opened and closed around what is written inside them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// Builds a C4 diagram as Pele's `C4Db` does. A positional argument fills the field of its place; a named one fills the
/// field it names whatever its place, as Mermaid assigns it. Every new shape and boundary counts against the node limit
/// and every new relation against the edge limit before it is made.
struct C4DiagramBuilder {
    var diagram = C4Diagram()
    private let limits: MermaidDiagramLimits
    private var shapeIndexByAlias: [String: Int] = [:]
    /// The top level is not listed, so a boundary a diagram names `global` is its own box.
    private var boundaryIndexByAlias: [String: Int] = [:]
    private var relationIndexByEnds: [C4RelationEnds: Int] = [:]
    private var currentBoundaryIndex = 0
    private var openBoundaryIndices: [Int] = []

    init(limits: MermaidDiagramLimits) {
        self.limits = limits
    }

    mutating func setAccessibilityDescription(_ text: String) {
        diagram.accessibilityDescription = C4DiagramBuilder.collapsingIndentedLines(text)
    }

    // MARK: - Shapes

    /// `alias, label, ?descr, ?sprite, ?tags, $link` for people and systems; containers and components take `?techn`
    /// before `?descr`.
    mutating func addShape(_ kind: C4ShapeKind, arguments: [C4Argument]) throws(MermaidDiagramReadError) {
        let index: Int
        if case .positional(let alias) = arguments[0], let known = shapeIndexByAlias[alias] {
            index = known
            diagram.shapes[index].kind = kind
        } else {
            index = diagram.shapes.count
            diagram.shapes.append(C4Shape(element: try newElement(alias: arguments[0], indexedIn: &shapeIndexByAlias, at: index), kind: kind))
        }
        let takesTechnology = kind.takesTechnology
        let detailsStart = takesTechnology ? 4 : 3
        let currentBoundaryIndex = currentBoundaryIndex
        Self.change(&diagram.shapes[index].element) { element in
            element.applyLabel(Self.argument(arguments, 1))
            if takesTechnology { element.fill(.technology, from: Self.argument(arguments, 2)) }
            element.fill(.description, from: Self.argument(arguments, detailsStart - 1))
            element.put(.sprite, Self.argument(arguments, detailsStart))
            element.put(.tags, Self.argument(arguments, detailsStart + 1))
            element.put(.link, Self.argument(arguments, detailsStart + 2))
            element.parentBoundaryIndex = currentBoundaryIndex
        }
    }

    // MARK: - Boundaries

    /// `alias, label, ?type, ?tags, $link` for boundaries, the enterprise, system and container ones with their kind
    /// written in as the third argument; `alias, label, ?type, ?descr, ?sprite, ?tags, $link` for deployment nodes.
    mutating func addBoundary(_ macro: C4TokenKind, arguments written: [C4Argument]) throws(MermaidDiagramReadError) {
        var arguments = written
        let kindWord: String? = switch macro {
        case .enterpriseBoundary: "ENTERPRISE"
        case .systemBoundary: "SYSTEM"
        case .containerBoundary: "CONTAINER"
        default: nil
        }
        if let kindWord { arguments.insert(.positional(kindWord), at: min(2, arguments.count)) }
        let node: C4DeploymentNodeKind? = switch macro {
        case .node: .node
        case .leftNode: .leftNode
        case .rightNode: .rightNode
        default: nil
        }
        let index = try boundaryIndex(for: arguments[0])
        let fallbackType = node != nil ? "node" : macro == .containerBoundary ? "container" : "system"
        Self.change(&diagram.boundaries[index].element) { element in
            element.applyLabel(Self.argument(arguments, 1))
            if let type = Self.argument(arguments, 2) { element.put(.type, type) } else { element.type = fallbackType }
            if node != nil {
                element.fill(.description, from: Self.argument(arguments, 3))
                // Mermaid drops whatever is in the sprite's place, a named argument included.
                element.put(.sprite, Self.argument(arguments, 4))
            }
            let tagsPlace = node != nil ? 5 : 3
            element.put(.tags, Self.argument(arguments, tagsPlace))
            element.put(.link, Self.argument(arguments, tagsPlace + 1))
        }
        if node != nil { diagram.boundaries[index].deploymentNode = node }
        diagram.boundaries[index].element.parentBoundaryIndex = currentBoundaryIndex
        openBoundaryIndices.append(currentBoundaryIndex)
        currentBoundaryIndex = index
    }

    mutating func closeBoundary() {
        currentBoundaryIndex = openBoundaryIndices.popLast() ?? 0
    }

    private mutating func boundaryIndex(for alias: C4Argument) throws(MermaidDiagramReadError) -> Int {
        if case .positional(let written) = alias, let known = boundaryIndexByAlias[written] { return known }
        let index = diagram.boundaries.count
        diagram.boundaries.append(C4Boundary(element: try newElement(alias: alias, indexedIn: &boundaryIndexByAlias, at: index), deploymentNode: nil))
        return index
    }

    /// A new element with its alias, or with the named argument written in its place applied, counted against the
    /// node limit.
    private func newElement(alias: C4Argument, indexedIn index: inout [String: Int], at position: Int) throws(MermaidDiagramReadError) -> C4Element {
        guard diagram.shapes.count + diagram.boundaries.count - 1 < limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
        var element = C4Element()
        switch alias {
        case .positional(let written):
            element.alias = written
            index[written] = position
        case .named(let argument):
            element.aliasArgument = argument
            element.apply(argument)
        }
        return element
    }

    // MARK: - Relations

    /// `from, to, label, ?techn, ?descr, ?sprite, ?tags, $link`; nothing without the first three. A relation between two
    /// aliases already related is that relation again, of the new kind.
    mutating func addRelation(_ kind: C4RelationKind, arguments: [C4Argument]) throws(MermaidDiagramReadError) {
        guard arguments.count >= 3 else { return }
        let index: Int
        let ends: C4RelationEnds? = if case .positional(let from) = arguments[0], case .positional(let to) = arguments[1] {
            C4RelationEnds(from: from, to: to)
        } else { nil }
        if let ends, let known = relationIndexByEnds[ends] {
            index = known
        } else {
            guard diagram.relations.count < limits.maximumEdgeCount else { throw .tooManyEdges(limit: limits.maximumEdgeCount) }
            index = diagram.relations.count
            var relation = C4Relation(kind: kind)
            if let ends { relationIndexByEnds[ends] = index }
            switch arguments[0] {
            case .positional(let from): relation.from = from
            case .named(let argument): relation.fromArgument = argument
            }
            switch arguments[1] {
            case .positional(let to): relation.to = to
            case .named(let argument): relation.toArgument = argument
            }
            diagram.relations.append(relation)
        }
        Self.change(&diagram.relations[index]) { relation in
            relation.kind = kind
            relation.applyLabel(arguments[2])
            relation.fill(.technology, from: Self.argument(arguments, 3))
            relation.fill(.description, from: Self.argument(arguments, 4))
            relation.put(.sprite, Self.argument(arguments, 5))
            relation.put(.tags, Self.argument(arguments, 6))
            relation.put(.link, Self.argument(arguments, 7))
        }
    }

    // MARK: - Updates

    /// `elementName, ?bgColor, ?fontColor, ?borderColor, ?shadowing, ?shape, ?sprite, ?techn, ?legendText, ?legendSprite`.
    mutating func updateElementStyle(_ arguments: [C4Argument]) {
        guard case .positional(let alias) = arguments[0] else { return }
        let fields: [C4ElementField] = [.backgroundColor, .fontColor, .borderColor, .shadowing, .shape, .sprite, .technology, .legendText, .legendSprite]
        func update(_ element: inout C4Element) {
            for (offset, field) in fields.enumerated() { element.put(field, Self.argument(arguments, offset + 1)) }
        }
        if let index = shapeIndexByAlias[alias] {
            update(&diagram.shapes[index].element)
        } else if let index = boundaryIndexByAlias[alias] {
            update(&diagram.boundaries[index].element)
        }
    }

    /// `from, to, ?textColor, ?lineColor, ?offsetX, ?offsetY`, for a relation already written.
    mutating func updateRelationStyle(_ arguments: [C4Argument]) {
        guard arguments.count >= 2, case .positional(let from) = arguments[0], case .positional(let to) = arguments[1],
              let index = relationIndexByEnds[C4RelationEnds(from: from, to: to)] else { return }
        Self.change(&diagram.relations[index]) { relation in
            relation.put(.textColor, Self.argument(arguments, 2))
            relation.put(.lineColor, Self.argument(arguments, 3))
            switch Self.argument(arguments, 4) {
            case .positional(let offset): relation.labelOffsetX = JavaScriptInteger.parsed(offset)
            case .named(let argument): relation.apply(argument)
            case nil: break
            }
            switch Self.argument(arguments, 5) {
            case .positional(let offset): relation.labelOffsetY = JavaScriptInteger.parsed(offset)
            case .named(let argument): relation.apply(argument)
            case nil: break
            }
        }
    }

    /// `?c4ShapeInRow, ?c4BoundaryInRow`. As in Mermaid, the place decides which one a value sets, not its name; a value
    /// under one is left out.
    mutating func updateLayoutConfiguration(_ arguments: [C4Argument]) {
        func count(_ argument: C4Argument?) -> Int? {
            let text: String? = switch argument {
            case .positional(let value): value
            case .named(let named): named.value
            case nil: nil
            }
            guard let value = text.flatMap(JavaScriptInteger.parsed), value >= 1 else { return nil }
            return Int(min(value, Self.largestRowCount))
        }
        if let shapes = count(Self.argument(arguments, 0)) { diagram.shapesPerRow = shapes }
        if let boundaries = count(Self.argument(arguments, 1)) { diagram.boundariesPerRow = boundaries }
    }

    // MARK: - Helpers

    /// A row holds at most this many: more than any diagram within the limits has, so that it acts as Mermaid's any.
    private static let largestRowCount: Double = 1_000_000_000

    private static func argument(_ arguments: [C4Argument], _ place: Int) -> C4Argument? {
        place < arguments.count ? arguments[place] : nil
    }

    private static func change<Value>(_ value: inout Value, _ body: (inout Value) -> Void) {
        body(&value)
    }

    /// Mermaid's `replace(/\n\s+/g, '\n')`: the white space after each line break, line breaks included, taken out.
    static func collapsingIndentedLines(_ text: String) -> String {
        let units = Array(text.utf16)
        var kept: [UInt16] = []
        kept.reserveCapacity(units.count)
        var index = 0
        while index < units.count {
            kept.append(units[index])
            if units[index] == C4Characters.lineFeed, index + 1 < units.count, C4Characters.isSpace(units[index + 1]) {
                index += 1
                while index < units.count, C4Characters.isSpace(units[index]) { index += 1 }
                continue
            }
            index += 1
        }
        return String(decoding: kept, as: UTF16.self)
    }
}

/// The aliases a relation joins, by which `UpdateRelStyle` and a relation written again find it.
private struct C4RelationEnds: Hashable {
    let from: String
    let to: String
}
