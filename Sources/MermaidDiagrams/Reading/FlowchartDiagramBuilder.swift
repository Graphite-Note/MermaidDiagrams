/**
 * File: FlowchartDiagramBuilder.swift
 * -----------------------------------
 * Layer: Core
 * Description: Collects a flowchart as its statements are read.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.7
 * Date: 23/11/2026
 */

/// Collects a flowchart as its statements are read: nodes by identifier, edges within the limits, and the groups open
/// at each point, which take the names written inside them. A group's members are settled when it ends, and the
/// groups' nesting once the whole text is read (`finishedDiagram()`).
struct FlowchartDiagramBuilder {
    private var diagram = FlowchartDiagram()
    private let limits: MermaidDiagramLimits
    /// The nodes by identifier, compared as Swift's strings are; kept only once `keepsIdentifierDictionary`, and made
    /// from the nodes when it starts (`keepIdentifierDictionary()`).
    private var nodeIndexByIdentifier: [String: Int] = [:]
    /// Whether `nodeIndexByIdentifier` holds every node. Until an identifier beyond ASCII is written or a style names a
    /// node, every node was named by ASCII bytes, which are equal as strings only when they are equal as bytes, so the
    /// identifier table alone says whether an identifier names a node and no string is hashed.
    private var keepsIdentifierDictionary = false
    /// The nodes by the bytes of the identifiers written for them, which the parser looks up before making a string.
    private var identifierTable: FlowchartIdentifierTable
    /// For each node, where in the text the brackets and text its shape and label were last set by were written, or an
    /// empty range when attributes set them since, or nothing has.
    private var shapeSources: [Range<Int>] = []
    /// Identifiers given to edges (`e1@-->`), whose `e1@{ … }` sets an edge's attributes rather than a node's.
    private var edgeIdentifiers: Set<String> = []
    /// The groups open now, outermost first.
    private var openSubgraphs: [OpenSubgraph] = []
    /// The groups ended so far, in the order they ended; a group ended again under the same identifier is merged.
    private var endedSubgraphs: [EndedFlowchartSubgraph] = []
    private var endedSubgraphIndexByIdentifier: [String: Int] = [:]
    /// Names a group took as it ended: a node or group belongs to the first group that ends with it named inside.
    private var takenMemberNames: Set<String> = []
    /// How many groups have opened, and how many have ended (the number in an identifier Mermaid makes, `subGraph0`).
    private var openedSubgraphCount = 0
    private var endedSubgraphCount = 0
    /// Identifiers given `@{ view: collapsed }`.
    private var collapsedIdentifiers: Set<String> = []
    /// What each `classDef` sets, by class name (a class defined again keeps what it set and takes what the new one sets).
    private var classStyles: [String: DiagramElementStyle] = [:]
    /// The classes given to nodes by `class` and `:::`, in the order written; resolved when the text ends, since `classDef`
    /// may come after them.
    private var classAssignments: [(identifier: String, className: String)] = []
    /// What `style` sets, by node identifier, in the order written.
    private var nodeStyleStatements: [(identifier: String, style: DiagramElementStyle)] = []
    /// What `linkStyle` sets for every edge (`default`) or for the edges at some indexes, in the order written.
    private var linkStyleStatements: [(indices: [Int]?, style: DiagramElementStyle)] = []

    /// A group open at the reading position.
    private struct OpenSubgraph {
        /// The identifier written after `subgraph`, or nil when Mermaid makes one as the group ends.
        let writtenIdentifier: String?
        let title: DiagramLabel
        let openingOrder: Int
        var direction: FlowchartDirection?
        var memberNames: [String] = []
        var memberNameSet: Set<String> = []

        mutating func add(memberName: String) {
            guard memberNameSet.insert(memberName).inserted else { return }
            memberNames.append(memberName)
        }
    }

    /// - Parameter expectedNodeCount: About how many nodes the text names (its lines), which the lists are made for.
    init(limits: MermaidDiagramLimits, expectedNodeCount: Int = 0) {
        self.limits = limits
        let nodeCount = min(max(expectedNodeCount, 0), limits.maximumNodeCount, Self.largestReservedCount)
        identifierTable = FlowchartIdentifierTable(expectedCount: nodeCount)
        diagram.nodes.reserveCapacity(nodeCount)
        shapeSources.reserveCapacity(nodeCount)
        diagram.edges.reserveCapacity(min(nodeCount, limits.maximumEdgeCount))
    }

    /// The most nodes and edges the lists are made for before the text is read; more grow them.
    private static let largestReservedCount = 1024

    /// The index of the node named by the identifier written from `start` to `end` of `bytes`, the text the parser reads,
    /// and whether it is new. A new node is added without its text: the parser gives it the text written with it or
    /// its identifier (`giveIdentifierAsLabel(toNodeAt:)`) before it reads on. A node named inside a group joins the
    /// innermost one. The identifier is made a string only when its bytes have not named a node before; the dictionary of
    /// strings, once kept, then says whether another spelling Swift counts as the same string has.
    mutating func nodeIndex(forIdentifierIn bytes: [UInt8], from start: Int, to end: Int) throws(MermaidDiagramReadError) -> (index: Int, isNew: Bool) {
        let (hash, isASCII) = FlowchartIdentifierTable.hash(of: bytes, from: start, to: end)
        if let existing = identifierTable.nodeIndex(in: bytes, from: start, to: end, hash: hash) {
            if !openSubgraphs.isEmpty { openSubgraphs[openSubgraphs.count - 1].add(memberName: String(decoding: bytes[start..<end], as: UTF8.self)) }
            return (existing, false)
        }
        if !isASCII { keepIdentifierDictionary() }
        let identifier = String(decoding: bytes[start..<end], as: UTF8.self)
        let index: Int
        let isNew: Bool
        if keepsIdentifierDictionary, let existing = nodeIndexByIdentifier[identifier] {
            index = existing
            isNew = false
        } else {
            guard diagram.nodes.count < limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
            index = diagram.nodes.count
            isNew = true
            diagram.nodes.append(FlowchartNode(identifier: identifier, label: Self.labelNotGivenYet))
            shapeSources.append(0..<0)
            if keepsIdentifierDictionary { nodeIndexByIdentifier[identifier] = index }
        }
        identifierTable.add(from: start, to: end, hash: hash, nodeIndex: index)
        if !openSubgraphs.isEmpty { openSubgraphs[openSubgraphs.count - 1].add(memberName: identifier) }
        return (index, isNew)
    }

    /// Starts keeping `nodeIndexByIdentifier`, made from the nodes named so far (each named by a different string).
    private mutating func keepIdentifierDictionary() {
        guard !keepsIdentifierDictionary else { return }
        keepsIdentifierDictionary = true
        nodeIndexByIdentifier.reserveCapacity(diagram.nodes.count)
        for index in diagram.nodes.indices { nodeIndexByIdentifier[diagram.nodes[index].identifier] = index }
    }

    /// A new node's label until the parser gives it one, never left on a node.
    private static let labelNotGivenYet = DiagramLabel(lines: [])

    /// A new node written without text shows its identifier.
    mutating func giveIdentifierAsLabel(toNodeAt index: Int) {
        diagram.nodes[index].label = Self.defaultLabel(diagram.nodes[index].identifier)
    }

    /// The length of the brackets and text the node's shape was last written with, when `bytes` from `position` start
    /// with them again: read again they give the shape and label the node has (the reading of brackets looks at no byte
    /// past their closing), so the parser moves past them. Nil when they are not written again or attributes set the
    /// node since.
    func lengthOfShapeWrittenAgain(forNodeAt index: Int, in bytes: [UInt8], at position: Int) -> Int? {
        let source = shapeSources[index]
        guard !source.isEmpty, position + source.count <= bytes.count else { return nil }
        for offset in 0..<source.count where bytes[position + offset] != bytes[source.lowerBound + offset] { return nil }
        return source.count
    }

    /// A node's shape and text written in brackets from `start` to `end` of the text, which replace what it had.
    mutating func define(nodeAt index: Int, asShapeWrittenFrom start: Int, to end: Int, _ definition: FlowchartNodeDefinition) {
        define(nodeAt: index, as: definition)
        shapeSources[index] = start..<end
    }

    /// A later definition of a node replaces what an earlier one set, as in Mermaid.
    mutating func define(nodeAt index: Int, as definition: FlowchartNodeDefinition) {
        shapeSources[index] = 0..<0
        if let shape = definition.shape { diagram.nodes[index].shape = shape }
        if let label = definition.label { diagram.nodes[index].label = label }
        if definition.asksForCollapsedView { collapsedIdentifiers.insert(diagram.nodes[index].identifier) }
        defineAsset(nodeAt: index, as: definition)
    }

    /// The icon or picture attributes written replace the node's, and a node made an icon or a picture without a label
    /// of its own shows none rather than its identifier (Pele's `addVertex`).
    private mutating func defineAsset(nodeAt index: Int, as definition: FlowchartNodeDefinition) {
        let written = definition.assetAttributes
        // Most nodes are written without these attributes, and copying the node out and back costs more than reading it.
        guard written != FlowchartNodeAssetAttributes() else { return }
        var node = diagram.nodes[index]
        if written.icon != nil || written.image != nil, definition.hasBlankWrittenLabel, node.label == DiagramLabel(node.identifier) {
            node.label = DiagramLabel(lines: [""])
        }
        node.assetAttributes.icon = written.icon ?? node.assetAttributes.icon
        node.assetAttributes.image = written.image ?? node.assetAttributes.image
        node.assetAttributes.form = written.form ?? node.assetAttributes.form
        node.assetAttributes.position = written.position ?? node.assetAttributes.position
        node.assetAttributes.width = written.width ?? node.assetAttributes.width
        node.assetAttributes.height = written.height ?? node.assetAttributes.height
        node.assetAttributes.constraint = written.constraint ?? node.assetAttributes.constraint
        diagram.nodes[index] = node
    }

    /// One edge from each source to each target, as `A & B --> C & D` asks.
    mutating func addEdges(from sourceIndices: [Int], to targetIndices: [Int], link: FlowchartLink) throws(MermaidDiagramReadError) {
        guard diagram.edges.count + sourceIndices.count * targetIndices.count <= limits.maximumEdgeCount else {
            throw .tooManyEdges(limit: limits.maximumEdgeCount)
        }
        for sourceIndex in sourceIndices {
            for targetIndex in targetIndices {
                diagram.edges.append(FlowchartEdge(sourceIndex: sourceIndex, targetIndex: targetIndex, stroke: link.stroke,
                                                   sourceArrowhead: link.sourceArrowhead, targetArrowhead: link.targetArrowhead,
                                                   minimumRankSpan: link.minimumRankSpan, label: link.label))
            }
        }
    }

    mutating func recordEdgeIdentifier(_ identifier: String) {
        edgeIdentifiers.insert(identifier)
    }

    func isEdgeIdentifier(_ identifier: String) -> Bool {
        edgeIdentifiers.contains(identifier)
    }

    /// Whether any edge has been given an identifier.
    var hasEdgeIdentifiers: Bool { !edgeIdentifiers.isEmpty }

    /// Opens a group; `identifier` is nil when the text gives none, and Mermaid's is made as the group ends.
    mutating func openSubgraph(identifier: String?, title: DiagramLabel) {
        openSubgraphs.append(OpenSubgraph(writtenIdentifier: identifier, title: title, openingOrder: openedSubgraphCount))
        openedSubgraphCount += 1
    }

    /// Ends the innermost group: it takes the names written inside it that no group ended before it took, never its
    /// own, and its identifier joins the group around it. False when no group is open.
    mutating func closeSubgraph() -> Bool {
        guard let group = openSubgraphs.popLast() else { return false }
        let identifier = group.writtenIdentifier ?? "subGraph\(endedSubgraphCount)"
        endedSubgraphCount += 1
        let members = group.memberNames.filter { name in !takenMemberNames.contains(name) && name != identifier }
        takenMemberNames.formUnion(members)
        if let existing = endedSubgraphIndexByIdentifier[identifier] {
            endedSubgraphs[existing].memberNames.append(contentsOf: members)
        } else {
            endedSubgraphIndexByIdentifier[identifier] = endedSubgraphs.count
            endedSubgraphs.append(EndedFlowchartSubgraph(identifier: identifier, title: group.title, direction: group.direction,
                                                         openingOrder: group.openingOrder, memberNames: members))
        }
        if !openSubgraphs.isEmpty { openSubgraphs[openSubgraphs.count - 1].add(memberName: identifier) }
        return true
    }

    /// The identifier of the innermost group still open (as Mermaid would make it, when the text gives none), or nil.
    var innermostOpenSubgraphIdentifier: String? {
        openSubgraphs.last.map { group in group.writtenIdentifier ?? "subGraph\(endedSubgraphCount)" }
    }

    var hasOpenSubgraph: Bool { !openSubgraphs.isEmpty }

    /// `direction` inside the innermost open group.
    mutating func setInnermostSubgraphDirection(_ direction: FlowchartDirection) {
        guard !openSubgraphs.isEmpty else { return }
        openSubgraphs[openSubgraphs.count - 1].direction = direction
    }

    /// The flowchart read, its groups nested and ordered (`FlowchartSubgraphNesting`), its nodes and edges styled.
    mutating func finishedDiagram() -> FlowchartDiagram {
        // The groups and the statements that style nodes find nodes by identifier.
        if !endedSubgraphs.isEmpty || !classAssignments.isEmpty || !nodeStyleStatements.isEmpty { keepIdentifierDictionary() }
        // The builder is done: the diagram moves out of it, so that styling the nodes and edges changes them in place.
        var finished = FlowchartDiagram()
        swap(&finished, &diagram)
        finished.subgraphs = FlowchartSubgraphNesting.subgraphs(endedSubgraphs, endedIndexByIdentifier: endedSubgraphIndexByIdentifier,
                                                                nodeIndexByIdentifier: nodeIndexByIdentifier,
                                                                collapsedIdentifiers: collapsedIdentifiers)
        finished.unappliedStatementCount += applyStyles(to: &finished)
        return finished
    }

    /// Gives `diagram`'s nodes and edges the styles the statements set, and returns how many statements named a node or a
    /// link that is not there.
    private func applyStyles(to diagram: inout FlowchartDiagram) -> Int {
        styleNodes(of: &diagram) + styleEdges(of: &diagram)
    }

    /// A node takes the `default` class, then its classes in the order they were given, then its own `style`. Returns how
    /// many `class` and `style` statements named no node (a group's, whose box is not styled yet, or none at all).
    private func styleNodes(of diagram: inout FlowchartDiagram) -> Int {
        let defaultStyle = classStyles["default"] ?? DiagramElementStyle()
        // Without classes given or styles written, every node takes the default class, and none at all leaves each nil.
        if classAssignments.isEmpty, nodeStyleStatements.isEmpty, defaultStyle.isEmpty { return 0 }
        var unappliedCount = 0
        var classNamesByNode: [Int: [String]] = [:]
        for assignment in classAssignments {
            guard let node = nodeIndexByIdentifier[assignment.identifier] else {
                unappliedCount += 1
                continue
            }
            classNamesByNode[node, default: []].append(assignment.className)
        }
        var ownStylesByNode: [Int: DiagramElementStyle] = [:]
        for statement in nodeStyleStatements {
            guard let node = nodeIndexByIdentifier[statement.identifier] else {
                unappliedCount += 1
                continue
            }
            ownStylesByNode[node] = (ownStylesByNode[node] ?? DiagramElementStyle()).overridden(by: statement.style)
        }
        for node in diagram.nodes.indices {
            var style = defaultStyle
            for className in classNamesByNode[node] ?? [] { style = style.overridden(by: classStyles[className] ?? DiagramElementStyle()) }
            style = style.overridden(by: ownStylesByNode[node] ?? DiagramElementStyle())
            diagram.nodes[node].style = style.isEmpty ? nil : style
        }
        return unappliedCount
    }

    /// An edge takes `linkStyle default`, then the `linkStyle` of its index. Returns how many indexes named no edge.
    private func styleEdges(of diagram: inout FlowchartDiagram) -> Int {
        // Without `linkStyle`, every edge's style stays nil.
        if linkStyleStatements.isEmpty { return 0 }
        var unappliedCount = 0
        var defaultEdgeStyle = DiagramElementStyle()
        var edgeStyles: [Int: DiagramElementStyle] = [:]
        for statement in linkStyleStatements {
            guard let indices = statement.indices else {
                defaultEdgeStyle = defaultEdgeStyle.overridden(by: statement.style)
                continue
            }
            for index in indices {
                guard diagram.edges.indices.contains(index) else {
                    unappliedCount += 1
                    continue
                }
                edgeStyles[index] = (edgeStyles[index] ?? DiagramElementStyle()).overridden(by: statement.style)
            }
        }
        for edge in diagram.edges.indices {
            let style = defaultEdgeStyle.overridden(by: edgeStyles[edge] ?? DiagramElementStyle())
            diagram.edges[edge].style = style.isEmpty ? nil : style
        }
        return unappliedCount
    }

    /// Records what a statement that styles the diagram sets; a statement that could not be read is counted as not applied.
    mutating func apply(_ statement: FlowchartStyleStatement?) {
        guard let statement else {
            countUnappliedStatement()
            return
        }
        switch statement {
        case .classDefinition(let names, let declarations):
            let (style, hasUnappliedDeclaration) = DiagramElementStyle.reading(declarations)
            for name in names { classStyles[name] = (classStyles[name] ?? DiagramElementStyle()).overridden(by: style) }
            if hasUnappliedDeclaration { countUnappliedStatement() }
        case .classAssignment(let identifiers, let className):
            for identifier in identifiers { classAssignments.append((identifier, className)) }
        case .nodeStyle(let identifier, let declarations):
            addNodeNamedByStyle(identifier)
            let (style, hasUnappliedDeclaration) = DiagramElementStyle.reading(declarations)
            nodeStyleStatements.append((identifier, style))
            if hasUnappliedDeclaration { countUnappliedStatement() }
        case .linkStyle(let indices, let declarations):
            var (style, hasUnappliedDeclaration) = DiagramElementStyle.reading(declarations)
            // An edge has no inside to fill; its text color is not set from here.
            style.fill = nil
            if style.textColor != nil {
                style.textColor = nil
                hasUnappliedDeclaration = true
            }
            linkStyleStatements.append((indices, style))
            if hasUnappliedDeclaration { countUnappliedStatement() }
        }
    }

    /// `style X …` adds X as a node when nothing has named it yet, as Pele's database does (its style statement calls
    /// `addVertex`), without making it a member of an open group, as Pele's parser lists no member for a style statement.
    /// A group's own identifier is left to the group, and past the node limit nothing is added (the style is then unapplied).
    private mutating func addNodeNamedByStyle(_ identifier: String) {
        keepIdentifierDictionary()
        guard nodeIndexByIdentifier[identifier] == nil, endedSubgraphIndexByIdentifier[identifier] == nil,
              !openSubgraphs.contains(where: { group in group.writtenIdentifier == identifier }),
              diagram.nodes.count < limits.maximumNodeCount else { return }
        nodeIndexByIdentifier[identifier] = diagram.nodes.count
        diagram.nodes.append(FlowchartNode(identifier: identifier, label: Self.defaultLabel(identifier)))
        shapeSources.append(0..<0)
    }

    /// The label of a node written without text: its identifier, drawn as Pele draws a vertex's text, which is its
    /// identifier (flowchart/db.ts `addVertex`), through the label layout, so `\node` breaks at its `\n` there too.
    private static func defaultLabel(_ identifier: String) -> DiagramLabel {
        DiagramLabelDecoder.label(from: identifier, form: .plain)
    }

    /// `A:::name`: the node at `index` takes the class.
    mutating func assignClass(_ className: String, toNodeAt index: Int) {
        classAssignments.append((diagram.nodes[index].identifier, className))
    }

    mutating func setDirection(_ direction: FlowchartDirection) {
        diagram.direction = direction
    }

    mutating func setAccessibilityTitle(_ title: String) {
        diagram.accessibilityTitle = title
    }

    mutating func setAccessibilityDescription(_ description: String) {
        diagram.accessibilityDescription = description
    }

    mutating func countUnappliedStatement() {
        diagram.unappliedStatementCount += 1
    }
}
