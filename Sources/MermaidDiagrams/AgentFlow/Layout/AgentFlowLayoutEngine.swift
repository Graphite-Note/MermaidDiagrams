/**
 * File: AgentFlowLayoutEngine.swift
 * ---------------------------------
 * Layer: Core
 * Description: Lays an agent flow out as Pele's agentflow render.ts does: nodes sized for text wrapped at 120 points and
 *              at least 120 wide, collapsed flows with their dots, flows as nested boxes on the flowchart's compound
 *              layout, and the edges between a node and a flow around it drawn to the flow's border.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// Lays an agent flow out with Pele's numbers (`agentflow/render.ts`): 40 points between nodes and 48 between ranks (or
/// the `agentflow:` options), edges 16 apart and border points 20 from their rank, text wrapped at 120 points, every
/// shape but a diamond sized for text at least 120 wide, a collapsed flow 14 points taller for its dots, flows as boxes
/// with 20 points of room and a band for their titles, on the flowchart's compound layout (`FlowchartLayoutEngine`).
public enum AgentFlowLayoutEngine {
    static let edgeSeparation: CGFloat = 16
    static let borderSeparation: CGFloat = 20
    /// The room a collapsed flow's dashed line and dots take below its text.
    static let collapsedMarkHeight: CGFloat = 14

    /// The diagram laid out; `isTurnedToRunDown` lays a diagram that runs across out as one that runs down, as Pele does
    /// for a narrow column.
    public static func layout(_ diagram: AgentFlowDiagram, typography: DiagramTypography, limits: MermaidDiagramLimits = .standard,
                              isTurnedToRunDown: Bool = false) throws(FlowchartLayoutError) -> AgentFlowLayout {
        try layout(diagram, nodeText: typography.nodeText, edgeText: typography.edgeText, font: typography.font, limits: limits,
                   isTurnedToRunDown: isTurnedToRunDown)
    }

    static func layout<Measurer: DiagramTextMeasuring>(_ diagram: AgentFlowDiagram, nodeText: Measurer, edgeText: Measurer, font: DiagramFont,
                                                       limits: MermaidDiagramLimits,
                                                       isTurnedToRunDown: Bool = false) throws(FlowchartLayoutError) -> AgentFlowLayout {
        var clustered = AgentFlowClusterGraph(graph: diagram.graph, direction: isTurnedToRunDown ? .topToBottom : diagram.direction)
        clustered.flowchart.title = diagram.title
        let measurement = AgentFlowMeasurement(graph: diagram.graph, clustered: clustered, nodeText: nodeText, edgeText: edgeText,
                                               options: diagram.options)
        for (subgraph, group) in clustered.subgraphGraphIndices.enumerated() {
            clustered.flowchart.subgraphs[subgraph].title = measurement.groupTitles[group]
        }
        let spacing = LayeredSpacing(nodeSeparation: CGFloat(diagram.options.nodeSpacing), edgeSeparation: edgeSeparation,
                                     rankSeparation: CGFloat(diagram.options.rankSpacing), borderSeparation: borderSeparation)
        let laidOut = try FlowchartLayoutEngine.layout(clustered.flowchart, measured: measurement.flowchartMeasurement, nodeText: nodeText,
                                                       font: font, limits: limits, spacing: spacing)
        return AgentFlowLayoutAssembly(diagram: diagram, clustered: clustered, measurement: measurement, laidOut: laidOut).layout
    }
}

/// An agent flow's text measured and its shapes sized as Pele's `draw` sizes them, in the flowchart's terms.
struct AgentFlowMeasurement {
    let flowchartMeasurement: FlowchartMeasurement
    /// Each graph node's title as a flow's box shows it: unwrapped.
    let groupTitles: [DiagramLabel]
    /// Each graph node's style, from its classes then its own statements.
    let styles: [DiagramElementStyle?]
    /// The texts of the edges between a node and a flow around it, by graph edge index.
    let heldEdgeTexts: [Int: DiagramTextBlock]

    init<Measurer: DiagramTextMeasuring>(graph: AgentFlowGraph, clustered: AgentFlowClusterGraph, nodeText: Measurer, edgeText: Measurer,
                                         options: AgentFlowOptions) {
        let wrappingWidth = CGFloat(options.wrappingWidth)
        let minimumWidth = CGFloat(options.minimumNodeWidth)
        groupTitles = graph.nodes.map { node in Self.label(node.label, type: node.labelType) }
        styles = graph.nodes.map { node in Self.style(node.compiledStyles + node.styles) }
        let count = clustered.flowchart.nodes.count
        var texts = [DiagramTextBlock](repeating: DiagramTextBlock(label: DiagramLabel(lines: []), measurer: nodeText, maximumWidth: 0), count: count)
        var sizes = [CGSize](repeating: .zero, count: count)
        var offsets = [CGFloat](repeating: 0, count: count)
        for (flowchartIndex, graphIndex) in clustered.drawnGraphIndices.enumerated() {
            let node = graph.nodes[graphIndex]
            let text = DiagramTextBlock(label: Self.label(node.label, type: node.labelType), measurer: nodeText, maximumWidth: wrappingWidth)
            texts[flowchartIndex] = text
            (sizes[flowchartIndex], offsets[flowchartIndex]) = Self.size(of: node, textSize: text.size, minimumWidth: minimumWidth)
        }
        func measuredText(of edgeIndex: Int) -> DiagramTextBlock? {
            let edge = graph.edges[edgeIndex]
            let text = DiagramTextBlock(label: Self.label(edge.label, type: edge.labelType), measurer: edgeText, maximumWidth: wrappingWidth)
            return text.lines.isEmpty ? nil : text
        }
        let edgeTexts = clustered.laidOutEdgeIndices.map(measuredText(of:))
        var heldEdgeTexts: [Int: DiagramTextBlock] = [:]
        for held in clustered.heldEdges { heldEdgeTexts[held.edgeIndex] = measuredText(of: held.edgeIndex) }
        self.heldEdgeTexts = heldEdgeTexts
        var loops = [[Int]](repeating: [], count: count)
        for (edgeIndex, edge) in clustered.flowchart.edges.enumerated() where edge.sourceIndex == edge.targetIndex {
            loops[edge.sourceIndex].append(edgeIndex)
        }
        flowchartMeasurement = FlowchartMeasurement(nodeTexts: texts, shapeSizes: sizes, textOffsets: offsets, edgeTexts: edgeTexts,
                                                    selfLoopEdgeIndices: loops)
    }

    /// A node's shape around its text, and how far below the shape's center the text is: a collapsed flow is a box with
    /// room for its dots below the text, any other shape is sized for text at least `minimumWidth` wide but a diamond,
    /// which grows twice as fast as its text and so keeps the text's own width.
    static func size(of node: AgentFlowGraphNode, textSize: CGSize, minimumWidth: CGFloat) -> (CGSize, CGFloat) {
        guard node.shape != "collapsedGroup" else {
            return (CGSize(width: max(textSize.width, minimumWidth) + 2 * FlowchartShapeGeometry.horizontalPadding,
                           height: textSize.height + 2 * FlowchartShapeGeometry.verticalPadding + AgentFlowLayoutEngine.collapsedMarkHeight),
                    -AgentFlowLayoutEngine.collapsedMarkHeight / 2)
        }
        let shape = AgentFlowShapes.drawnShape(node.shape)
        let sizingWidth = shape == .diamond ? textSize.width : max(textSize.width, minimumWidth)
        let sized = FlowchartShapeGeometry.size(of: shape, textSize: CGSize(width: sizingWidth, height: textSize.height))
        return (sized.size, sized.textOffset)
    }

    /// A node's, a flow's or an edge's text as drawn: a Markdown string loses its markers, `<br>` breaks lines.
    static func label(_ text: String?, type: AgentFlowLabelType) -> DiagramLabel {
        guard let text, !text.isEmpty else { return DiagramLabel(lines: []) }
        return DiagramLabelDecoder.label(from: text, form: type == .markdown ? .markdown : .plain)
    }

    /// The style a list of declarations gives, or nil when it sets nothing this look has room for.
    static func style(_ declarations: [String]) -> DiagramElementStyle? {
        guard !declarations.isEmpty else { return nil }
        let style = DiagramElementStyle.reading(declarations.joined(separator: ",")).style
        return style.isEmpty ? nil : style
    }
}

extension FlowchartMeasurement {
    /// A flowchart measured by a diagram drawn as one, which sizes its nodes its own way.
    init(nodeTexts: [DiagramTextBlock], shapeSizes: [CGSize], textOffsets: [CGFloat], edgeTexts: [DiagramTextBlock?], selfLoopEdgeIndices: [[Int]]) {
        self.nodeTexts = nodeTexts
        self.shapeSizes = shapeSizes
        self.textOffsets = textOffsets
        self.edgeTexts = edgeTexts
        self.selfLoopEdgeIndices = selfLoopEdgeIndices
    }
}
