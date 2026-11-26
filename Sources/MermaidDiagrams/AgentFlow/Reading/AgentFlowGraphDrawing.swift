/**
 * File: AgentFlowGraphDrawing.swift
 * ---------------------------------
 * Layer: Core
 * Description: The nodes and edges of an agent flow's graph as Pele's graph.ts makes them: flows as groups, nodes with
 *              the styles of their classes and their own, edges between what is still drawn with their curves.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

/// The model's attributes grouped by owner, made only for the lists that have any, and the names of the classes every
/// node is given (`default`, `node`).
struct AgentFlowGraphStyles {
    let vertexAttributes: AgentFlowOwnerIndex
    let edgeAttributes: AgentFlowOwnerIndex
    let flowAttributes: AgentFlowOwnerIndex
    let classAttributes: AgentFlowOwnerIndex

    init(model: AgentFlowModel, arena: DiagramScratchArena) {
        vertexAttributes = Self.index(model.vertexAttributes, ownerCount: model.vertices.count, arena: arena)
        edgeAttributes = Self.index(model.edgeAttributes, ownerCount: model.edges.count, arena: arena)
        flowAttributes = Self.index(model.flowAttributes, ownerCount: model.flows.count, arena: arena)
        classAttributes = Self.index(model.classAttributes, ownerCount: model.classDefinitions.count, arena: arena)
    }

    static func index(_ attributes: [AgentFlowAttribute], ownerCount: Int, arena: DiagramScratchArena) -> AgentFlowOwnerIndex {
        attributes.isEmpty ? AgentFlowOwnerIndex()
            : AgentFlowOwnerIndex(ownerCount: ownerCount, count: attributes.count, arena: arena) { entry in attributes[entry].owner }
    }
}

extension AgentFlowDiagramBuilder {
    /// The flows still drawn, as groups, each after the flows it holds (the last closed first), then the nodes; a node of a
    /// flow's identifier gives the flow's group its styles.
    mutating func drawNodes(_ naming: inout AgentFlowGraphNaming, styles: AgentFlowGraphStyles) {
        model.graph.nodes.reserveCapacity(model.flows.count + model.vertices.count)
        var parentNames: ScratchList<Int32> = arena.list(capacity: model.flows.count + model.vertices.count)
        for flowIndex in model.flows.indices.reversed() where !naming.byName[Int(model.flows[flowIndex].name)].isHidden {
            let flow = model.flows[flowIndex]
            naming.byName[Int(flow.name)].graphNode = Int32(model.graph.nodes.count)
            var node = AgentFlowGraphNodeRecord(name: flow.name, identifier: flow.identifier, label: flow.title, labelType: flow.labelType,
                                                shape: flow.isCollapsed ? AgentFlowShapeNames.collapsedGroup : AgentFlowShapeNames.flowGroup,
                                                isGroup: !flow.isCollapsed, flow: Int32(flowIndex))
            node.compiledStyles = compiledStyles(of: styles.flowAttributes.entries(of: flowIndex), in: model.flowAttributes, firstAttribute: 0,
                                                 withNodeClasses: false, styles: styles)
            model.graph.nodes.append(node)
            parentNames.append(naming.byName[Int(flow.name)].parent)
        }
        for vertexIndex in model.vertices.indices where !naming.byName[Int(model.vertices[vertexIndex].name)].isHidden {
            let vertex = model.vertices[vertexIndex]
            let ownAttributes = styles.vertexAttributes.entries(of: vertexIndex)
            let existing = naming.byName[Int(vertex.name)].graphNode
            if existing >= 0 {
                model.graph.nodes[Int(existing)].vertex = Int32(vertexIndex)
                model.graph.nodes[Int(existing)].styles = vertexStyles(ownAttributes, firstAttribute: vertex.firstAttribute)
                model.graph.nodes[Int(existing)].compiledStyles = compiledStyles(of: ownAttributes, in: model.vertexAttributes,
                                                                                 firstAttribute: vertex.firstAttribute, withNodeClasses: false, styles: styles)
                continue
            }
            naming.byName[Int(vertex.name)].graphNode = Int32(model.graph.nodes.count)
            var node = AgentFlowGraphNodeRecord(name: vertex.name, identifier: vertex.identifier, label: vertex.text, labelType: vertex.labelType,
                                                shape: vertex.type >= 0 ? AgentFlowShapeNames.graphShapes[Int(vertex.type)] : AgentFlowShapeNames.squareRect,
                                                isGroup: false, vertex: Int32(vertexIndex))
            node.styles = vertexStyles(ownAttributes, firstAttribute: vertex.firstAttribute)
            node.compiledStyles = compiledStyles(of: ownAttributes, in: model.vertexAttributes, firstAttribute: vertex.firstAttribute,
                                                 withNodeClasses: true, styles: styles)
            node.tooltip = names[vertex.name].tooltip
            model.graph.nodes.append(node)
            parentNames.append(naming.byName[Int(vertex.name)].parent)
        }
        for (index, parent) in parentNames.enumerated() where parent >= 0 { model.graph.nodes[index].parent = naming.byName[Int(parent)].graphNode }
    }

    /// A node's own `style` statements, a run of the graph's style ranges.
    private mutating func vertexStyles(_ attributes: ScratchSpan<Int32>, firstAttribute: Int32) -> Range<Int32> {
        let start = Int32(model.graph.styleRanges.count)
        for attribute in attributes where attribute >= firstAttribute && model.vertexAttributes[Int(attribute)].kind == .style {
            model.graph.styleRanges.append(model.vertexAttributes[Int(attribute)].value)
        }
        return start..<Int32(model.graph.styleRanges.count)
    }

    /// The styles of the classes named among `attributes` (after `default` and `node` for a node), each trimmed, the text
    /// styles of each class after its styles; none without a class definition.
    private mutating func compiledStyles(of attributes: ScratchSpan<Int32>, in list: [AgentFlowAttribute], firstAttribute: Int32,
                                         withNodeClasses: Bool, styles: AgentFlowGraphStyles) -> Range<Int32> {
        let start = Int32(model.graph.styleRanges.count)
        guard !model.classDefinitions.isEmpty else { return start..<start }
        if withNodeClasses {
            appendClassStyles(of: name(of: constant(.defaultClass)), styles: styles)
            appendClassStyles(of: name(of: constant(.nodeClass)), styles: styles)
        }
        for attribute in attributes where attribute >= firstAttribute && list[Int(attribute)].kind == .className {
            appendClassStyles(of: name(of: list[Int(attribute)].value), styles: styles)
        }
        return start..<Int32(model.graph.styleRanges.count)
    }

    private mutating func appendClassStyles(of className: Int32, styles: AgentFlowGraphStyles) {
        let definition = names[className].classDefinition
        guard definition >= 0 else { return }
        let entries = styles.classAttributes.entries(of: Int(definition))
        for kind in [AgentFlowAttribute.Kind.style, .textStyle] {
            for entry in entries where model.classAttributes[Int(entry)].kind == kind {
                model.graph.styleRanges.append(model.text.trimmed(model.classAttributes[Int(entry)].value))
            }
        }
    }

    /// Each edge between what is still drawn: an end inside a collapsed flow meets the flow, and an edge between two
    /// things inside one collapsed flow has nothing left to connect.
    mutating func drawEdges(_ naming: AgentFlowGraphNaming, styles: AgentFlowGraphStyles) {
        model.graph.edges.reserveCapacity(model.edges.count)
        for index in model.edges.indices {
            let raw = model.edges[index]
            let start = collapsedEnd(raw.start, raw.startName, naming)
            let end = collapsedEnd(raw.end, raw.endName, naming)
            if start.name == end.name, raw.startName != raw.endName { continue }
            let arrow: FlowchartArrowhead = raw.arrow == .open ? .none : raw.arrow == .cross ? .cross : .arrow
            let curve = raw.interpolation.flatMap { curve in curve.isEmpty ? nil : curve } ?? model.defaultInterpolation.flatMap { curve in curve.isEmpty ? nil : curve }
            let identifier = raw.identifier.isEmpty ? madeGraphEdgeIdentifier(start.range, end.range, index: index) : raw.identifier
            let compiled = compiledStyles(of: styles.edgeAttributes.entries(of: index), in: model.edgeAttributes, firstAttribute: 0, withNodeClasses: false,
                                          styles: styles)
            let styleStart = Int32(model.graph.styleRanges.count)
            if let run = model.defaultEdgeStyle { for style in run { model.graph.styleRanges.append(model.styleRanges[Int(style)]) } }
            if let run = raw.style { for style in run { model.graph.styleRanges.append(model.styleRanges[Int(style)]) } }
            model.graph.edges.append(AgentFlowGraphEdgeRecord(edge: Int32(index), identifier: identifier, start: start, end: end,
                                                              startNode: naming.byName[Int(start.name)].graphNode, endNode: naming.byName[Int(end.name)].graphNode,
                                                              arrowTypeEnd: arrow, compiledStyles: compiled,
                                                              style: styleStart..<Int32(model.graph.styleRanges.count), curve: curve))
        }
    }

    /// An edge's end as drawn: the outermost collapsed flow it is inside, or itself.
    private func collapsedEnd(_ range: MermaidTextRange, _ name: Int32, _ naming: AgentFlowGraphNaming) -> AgentFlowNamedText {
        let flowName = naming.byName[Int(name)].collapsedInto
        guard flowName >= 0 else { return AgentFlowNamedText(range: range, name: name) }
        return AgentFlowNamedText(range: model.flows[Int(names[flowName].flow)].identifier, name: flowName)
    }

    /// `L_start_end_index`, for an edge without an identifier.
    private mutating func madeGraphEdgeIdentifier(_ start: MermaidTextRange, _ end: MermaidTextRange, index: Int) -> MermaidTextRange {
        let first = model.text.bytes.count
        model.text.bytes.append(76)
        model.text.bytes.append(MermaidByte.underscore)
        model.text.appendCopy(of: start)
        model.text.bytes.append(MermaidByte.underscore)
        model.text.appendCopy(of: end)
        model.text.bytes.append(MermaidByte.underscore)
        AgentFlowPairCounts.appendDecimal(index, to: &model.text.bytes)
        return MermaidTextRange(start: first, end: model.text.bytes.count)
    }
}
