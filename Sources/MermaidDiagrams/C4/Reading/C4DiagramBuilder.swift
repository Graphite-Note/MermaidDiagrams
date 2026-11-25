/**
 * File: C4DiagramBuilder.swift
 * ----------------------------
 * Layer: Core
 * Description: Builds a C4 diagram from the parser's calls as Pele's db.ts does: each macro's positional arguments
 *              to the fields of their places, named ones to the fields they name, an alias written again merged into
 *              its element, boundaries opened and closed around what is written inside them; every field a range of
 *              the text and every alias an interned name.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 25/11/2026
 */

/// Builds a C4 diagram as Pele's `C4Db` does. A positional argument fills the field of its place; a named one fills the
/// field it names whatever its place, as Mermaid assigns it. Every new shape and boundary counts against the node limit
/// and every new relation against the edge limit before it is made. Aliases and relations' ends are interned names
/// (`C4NameTable`), which find a shape, a boundary or a relation by number.
struct C4DiagramBuilder {
    var diagram: C4Diagram
    let limits: MermaidDiagramLimits
    private var names: C4NameTable
    /// By name: the shape and the boundary written with it as their alias, -1 for none. The top level is not listed, so
    /// a boundary a diagram names `global` is its own box.
    var shapeIndexByName: [Int32] = []
    var boundaryIndexByName: [Int32] = []
    /// By the names of its two ends, the relation between them.
    var relationIndexByEnds: [UInt64: Int32] = [:]
    private var currentBoundaryIndex: Int32 = 0
    private var openBoundaryIndices: [Int32] = []

    init(source: [UInt8], limits: MermaidDiagramLimits) {
        diagram = C4Diagram(source: source)
        self.limits = limits
        names = C4NameTable(bytes: source)
    }

    /// Room for as many shapes, boundaries, relations and names as `kinds` holds macros, made once.
    mutating func reserveCapacity(for counts: (shapes: Int, boundaries: Int, relations: Int)) {
        let shapeCount = counts.shapes
        let boundaryCount = counts.boundaries + 1
        let relationCount = counts.relations
        diagram.shapeRecords.reserveCapacity(shapeCount)
        diagram.boundaryRecords.reserveCapacity(boundaryCount)
        diagram.relationRecords.reserveCapacity(relationCount)
        let nameCount = shapeCount + boundaryCount + 2 * relationCount
        names.reserveCapacity(nameCount)
        shapeIndexByName.reserveCapacity(nameCount)
        boundaryIndexByName.reserveCapacity(nameCount)
        relationIndexByEnds.reserveCapacity(relationCount)
    }

    /// The diagram as read, with the count of its names.
    var finished: C4Diagram {
        var finished = diagram
        finished.nameCount = names.count
        return finished
    }

    mutating func setAccessibilityDescription(_ text: C4Text) {
        diagram.accessibilityDescriptionText = C4IndentedLines.collapsed(text, in: &diagram)
    }

    /// A named argument added to the diagram's list.
    mutating func namedArgument(key: C4Text, value: C4Text) -> C4ArgumentRecord {
        diagram.namedArguments.append(C4NamedArgumentRecord(key: key, value: value))
        return .named(Int32(diagram.namedArguments.count - 1))
    }

    /// The number of the name `text` spells: a range of the source, or an empty argument (`C4DerivedText.empty`), whose
    /// name is the empty one.
    mutating func name(of text: C4Text) -> Int32 {
        precondition(!text.isDerived || text.count == 0, "A name is read from the source")
        let (start, end) = text.isDerived ? (0, 0) : (Int(text.start), Int(text.end))
        let number = diagram.source.withUnsafeBufferPointer { bytes in names.intern(bytes, from: start, to: end) }
        if Int(number) == shapeIndexByName.count {
            shapeIndexByName.append(-1)
            boundaryIndexByName.append(-1)
        }
        return number
    }

    // MARK: - Shapes

    /// `alias, label, ?descr, ?sprite, ?tags, $link` for people and systems; containers and components take `?techn`
    /// before `?descr`.
    mutating func addShape(_ kind: C4ShapeKind, arguments: ScratchSpan<C4ArgumentRecord>) throws(MermaidDiagramReadError) {
        let index: Int
        let alias = arguments[0]
        let name = alias.isNamed ? -1 : self.name(of: alias.text)
        if name >= 0, shapeIndexByName[Int(name)] >= 0 {
            index = Int(shapeIndexByName[Int(name)])
            diagram.shapeRecords[index].kind = kind
        } else {
            index = diagram.shapeRecords.count
            try checkNodeLimit()
            var element = C4ElementRecord()
            setAlias(alias, name: name, of: &element)
            if name >= 0 { shapeIndexByName[Int(name)] = Int32(index) }
            diagram.shapeRecords.append(C4ShapeRecord(element: element, kind: kind))
        }
        let takesTechnology = kind.takesTechnology
        let detailsStart = takesTechnology ? 4 : 3
        var element = diagram.shapeRecords[index].element
        diagram.applyLabel(Self.argument(arguments, 1), to: &element)
        if takesTechnology { diagram.fill(.technology, from: Self.argument(arguments, 2), to: &element) }
        diagram.fill(.description, from: Self.argument(arguments, detailsStart - 1), to: &element)
        diagram.put(.sprite, Self.argument(arguments, detailsStart), to: &element)
        diagram.put(.tags, Self.argument(arguments, detailsStart + 1), to: &element)
        diagram.put(.link, Self.argument(arguments, detailsStart + 2), to: &element)
        element.parentBoundaryIndex = currentBoundaryIndex
        diagram.shapeRecords[index].element = element
    }

    // MARK: - Boundaries

    /// `alias, label, ?type, ?tags, $link` for boundaries, the enterprise, system and container ones with their kind
    /// written in as the third argument; `alias, label, ?type, ?descr, ?sprite, ?tags, $link` for deployment nodes.
    mutating func addBoundary(_ macro: C4TokenKind, arguments: ScratchSpan<C4ArgumentRecord>) throws(MermaidDiagramReadError) {
        let kindWord: C4Text? = switch macro {
        case .enterpriseBoundary: C4DerivedText.enterprise
        case .systemBoundary: C4DerivedText.systemWord
        case .containerBoundary: C4DerivedText.containerWord
        default: nil
        }
        // The kind's word written in as the third argument, or after the last when there are fewer, without a copy.
        let kindPlace = kindWord == nil ? Int.max : min(2, arguments.count)
        func argument(_ place: Int) -> C4ArgumentRecord? {
            if place < kindPlace { return Self.argument(arguments, place) }
            if place == kindPlace, let kindWord { return .positional(kindWord) }
            return Self.argument(arguments, place - 1)
        }
        let node: C4DeploymentNodeKind? = switch macro {
        case .node: .node
        case .leftNode: .leftNode
        case .rightNode: .rightNode
        default: nil
        }
        let index = try boundaryIndex(for: argument(0) ?? arguments[0])
        let fallbackType = node != nil ? C4DerivedText.node : macro == .containerBoundary ? C4DerivedText.container : C4DerivedText.system
        var element = diagram.boundaryRecords[index].element
        diagram.applyLabel(argument(1), to: &element)
        if let type = argument(2) { diagram.put(.type, type, to: &element) } else { element.type = fallbackType }
        if node != nil {
            diagram.fill(.description, from: argument(3), to: &element)
            // Mermaid drops whatever is in the sprite's place, a named argument included.
            diagram.put(.sprite, argument(4), to: &element)
        }
        let tagsPlace = node != nil ? 5 : 3
        diagram.put(.tags, argument(tagsPlace), to: &element)
        diagram.put(.link, argument(tagsPlace + 1), to: &element)
        element.parentBoundaryIndex = currentBoundaryIndex
        diagram.boundaryRecords[index].element = element
        if node != nil { diagram.boundaryRecords[index].deploymentNode = node }
        openBoundaryIndices.append(currentBoundaryIndex)
        currentBoundaryIndex = Int32(index)
    }

    mutating func closeBoundary() {
        currentBoundaryIndex = openBoundaryIndices.popLast() ?? 0
    }

    private mutating func boundaryIndex(for alias: C4ArgumentRecord) throws(MermaidDiagramReadError) -> Int {
        let name = alias.isNamed ? -1 : self.name(of: alias.text)
        if name >= 0, boundaryIndexByName[Int(name)] >= 0 { return Int(boundaryIndexByName[Int(name)]) }
        let index = diagram.boundaryRecords.count
        try checkNodeLimit()
        var element = C4ElementRecord()
        setAlias(alias, name: name, of: &element)
        if name >= 0 { boundaryIndexByName[Int(name)] = Int32(index) }
        diagram.boundaryRecords.append(C4BoundaryRecord(element: element, deploymentNode: nil))
        return index
    }

    /// Whether another shape or boundary fits the node limit.
    private func checkNodeLimit() throws(MermaidDiagramReadError) {
        guard diagram.shapeRecords.count + diagram.boundaryRecords.count - 1 < limits.maximumNodeCount else {
            throw .tooManyNodes(limit: limits.maximumNodeCount)
        }
    }

    /// A new element's alias, or the named argument written in its place applied, once `checkNodeLimit` let it be made.
    private mutating func setAlias(_ alias: C4ArgumentRecord, name: Int32, of element: inout C4ElementRecord) {
        if alias.isNamed {
            element.alias = C4DerivedText.empty
            element.aliasArgument = alias.named
            diagram.apply(alias.named, to: &element)
        } else {
            element.alias = alias.text
            element.name = name
        }
    }

    static func argument(_ arguments: ScratchSpan<C4ArgumentRecord>, _ place: Int) -> C4ArgumentRecord? {
        place < arguments.count ? arguments[place] : nil
    }
}
