/**
 * File: AgentFlowDiagramGraph.swift
 * ---------------------------------
 * Layer: Core
 * Description: What an agent flow draws (Pele's `buildAgentGraph`), made from the graph records its reader keeps when it
 *              is asked for, as 0.7.0 stored it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

extension AgentFlowDiagram {
    /// What is drawn: the nodes and the edges of Pele's `buildAgentGraph`.
    public var graph: AgentFlowGraph {
        DiagramScratchArena.withCurrentThread { arena in
            graph(AgentFlowGraphStyles.index(model.vertexAttributes, ownerCount: model.vertices.count, arena: arena),
                  flowAttributes: AgentFlowGraphStyles.index(model.flowAttributes, ownerCount: model.flows.count, arena: arena))
        }
    }

    private func graph(_ attributes: AgentFlowOwnerIndex, flowAttributes: AgentFlowOwnerIndex) -> AgentFlowGraph {
        let records = model.graph
        var graph = AgentFlowGraph()
        graph.nodes = records.nodes.map { record in
            var classes = record.vertex >= 0 ? classNames(attributes.entries(of: Int(record.vertex)), model.vertexAttributes,
                                                          firstAttribute: model.vertices[Int(record.vertex)].firstAttribute) : []
            if record.vertex < 0 { classes = classNames(flowAttributes.entries(of: Int(record.flow)), model.flowAttributes, firstAttribute: 0) }
            let isVertexNode = record.flow < 0
            let vertex = isVertexNode ? model.vertices[Int(record.vertex)] : nil
            let flow = record.flow >= 0 ? model.flows[Int(record.flow)] : nil
            var node = AgentFlowGraphNode(identifier: model.text.string(record.identifier), label: model.text.string(record.label), labelType: record.labelType,
                                          shape: AgentFlowShapeNames.names[Int(record.shape)], isGroup: record.isGroup,
                                          parentIdentifier: record.parent >= 0 ? model.text.string(records.nodes[Int(record.parent)].identifier) : nil,
                                          styles: graphStrings(record.styles), compiledStyles: graphStrings(record.compiledStyles),
                                          classes: isVertexNode ? "default " + classes.joined(separator: " ") : classes.joined(separator: " "),
                                          directionKeyword: model.text.string(orNil: flow?.directionKeyword),
                                          link: model.text.string(orNil: vertex?.link), linkTarget: model.text.string(orNil: vertex?.linkTarget),
                                          tooltip: model.text.string(orNil: record.tooltip))
            node.colorIndex = record.colorIndex >= 0 ? Int(record.colorIndex) : nil
            node.containerNumber = record.containerNumber >= 0 ? Int(record.containerNumber) : nil
            node.kind = record.kind
            return node
        }
        graph.edges = records.edges.map { record in
            let raw = model.edges[Int(record.edge)]
            return AgentFlowGraphEdge(identifier: model.text.string(record.identifier), isUserDefinedIdentifier: raw.isUserDefinedIdentifier,
                                      start: model.text.string(record.start.range), end: model.text.string(record.end.range), type: raw.arrow.name,
                                      label: model.text.string(raw.text), labelType: raw.labelType, thickness: raw.stroke.name,
                                      minimumLength: raw.length >= 0 ? Int(raw.length) : nil, arrowTypeEnd: Self.arrowTypeEndName(record.arrowTypeEnd),
                                      compiledStyles: graphStrings(record.compiledStyles), style: graphStrings(record.style), curve: model.text.string(orNil: record.curve))
        }
        return graph
    }

    private func classNames(_ entries: ScratchSpan<Int32>, _ list: [AgentFlowAttribute], firstAttribute: Int32) -> [String] {
        entries.compactMap { entry in
            entry >= firstAttribute && list[Int(entry)].kind == .className ? model.text.string(list[Int(entry)].value) : nil
        }
    }

    private func graphStrings(_ run: Range<Int32>) -> [String] {
        run.map { style in model.text.string(model.graph.styleRanges[Int(style)]) }
    }

    /// Mermaid's name of an edge's end mark.
    static func arrowTypeEndName(_ arrowhead: FlowchartArrowhead) -> String {
        switch arrowhead {
        case .none: "none"
        case .cross: "arrow_cross"
        default: "arrow_point"
        }
    }
}
