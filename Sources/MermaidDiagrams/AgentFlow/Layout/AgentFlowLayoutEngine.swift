/**
 * File: AgentFlowLayoutEngine.swift
 * ---------------------------------
 * Layer: Core
 * Description: Lays an agent flow out as Pele's agentflow render.ts does: nodes sized for text wrapped at 120 points and
 *              at least 120 wide, collapsed flows with their dots, flows as nested boxes on the flowchart's compound
 *              layout, and the edges between a node and a flow around it drawn to the flow's border.
 *
 * Authors: Bahey Shalash
 * Version: 0.6
 * Date: 26/11/2026
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
    /// for a narrow column. A node whose style sets a font size, bold or italic has its text measured so in Core Text.
    public static func layout(_ diagram: AgentFlowDiagram, typography: DiagramTypography, limits: MermaidDiagramLimits = .standard,
                              isTurnedToRunDown: Bool = false) throws(FlowchartLayoutError) -> AgentFlowLayout {
        let font = typography.font
        let measurers = BlockMeasurers(nodeText: typography.nodeText, edgeText: typography.edgeText, titleText: typography.boldNodeText,
                                       restyled: { fontSize, isBold, isItalic in
                                           CoreTextDiagramTextMeasurer(font: font.resized(to: fontSize), isBold: isBold, isItalic: isItalic)
                                       })
        return try layout(diagram, measurers: measurers, font: font, limits: limits, isTurnedToRunDown: isTurnedToRunDown)
    }

    static func layout<Measurer: DiagramTextMeasuring>(_ diagram: AgentFlowDiagram, measurers: BlockMeasurers<Measurer>, font: DiagramFont,
                                                       limits: MermaidDiagramLimits,
                                                       isTurnedToRunDown: Bool = false) throws(FlowchartLayoutError) -> AgentFlowLayout {
        let model = diagram.model
        let direction = isTurnedToRunDown ? .topToBottom : diagram.direction
        let spacing = LayeredSpacing(nodeSeparation: CGFloat(diagram.options.nodeSpacing), edgeSeparation: edgeSeparation,
                                     rankSeparation: CGFloat(diagram.options.rankSpacing), borderSeparation: borderSeparation)
        // The cluster graph's lists live in the thread's scratch arena for the layout's run.
        let laidOut = DiagramScratchArena.withCurrentThread { arena in
            Result { () throws(FlowchartLayoutError) in
                let clustered = AgentFlowClusterGraph(model: model, direction: direction, arena: arena)
                let measurement = AgentFlowMeasurement(model: model, clustered: clustered, measurers: measurers, options: diagram.options)
                let flowchart = clustered.flowchart(titles: measurement.subgraphTitles, title: diagram.title, text: model.text)
                let placed = try FlowchartLayoutEngine.layout(flowchart, measured: measurement.flowchartMeasurement, nodeText: measurers.nodeText,
                                                              font: font, limits: limits, spacing: spacing)
                return AgentFlowLayoutAssembly(model: model, clustered: clustered, measurement: measurement, laidOut: placed).layout
            }
        }
        return try laidOut.get()
    }
}

/// An agent flow's text measured and its shapes sized as Pele's `draw` sizes them, in the flowchart's terms: text of more
/// than one line has its lines 1.3 sizes apart, as Pele's `layoutLabel` sets them (`PlaneMapLabel`).
struct AgentFlowMeasurement {
    let flowchartMeasurement: FlowchartMeasurement
    /// Each subgraph's title as its flow's box shows it, unwrapped, in the subgraphs' order.
    let subgraphTitles: [DiagramLabel]
    /// Each graph node's style, from its classes then its own statements; empty when no node has styles.
    private let styles: [DiagramElementStyle?]
    /// Each graph node's text's weight and slant, as its style sets them (Pele's `resolveStyle`); empty when no node has
    /// styles.
    private let textLooks: [(isBold: Bool, isItalic: Bool)]
    /// The texts of the edges between a node and a flow around it, by graph edge index.
    let heldEdgeTexts: [Int: DiagramTextBlock]

    init<Measurer: DiagramTextMeasuring>(model: AgentFlowModel, clustered: AgentFlowClusterGraph, measurers: BlockMeasurers<Measurer>,
                                         options: AgentFlowOptions) {
        let wrappingWidth = CGFloat(options.wrappingWidth)
        let minimumWidth = CGFloat(options.minimumNodeWidth)
        let nodeText = measurers.nodeText
        let edgeText = measurers.edgeText
        let nodes = model.graph.nodes
        let text = model.text
        var titles: [DiagramLabel] = []
        titles.reserveCapacity(clustered.subgraphGraphIndices.count)
        for group in clustered.subgraphGraphIndices { titles.append(Self.label(nodes[group].label, type: nodes[group].labelType, in: text)) }
        subgraphTitles = titles
        let looks = Self.looks(of: model)
        styles = looks.styles
        textLooks = looks.textLooks
        var restyled = BlockMeasurerCache(measurers: measurers)
        let count = clustered.flowchartNodeCount
        // The nodes standing for themselves come first among the flowchart's nodes, in order; a node standing for a flow
        // has no text of its own.
        var texts: [DiagramTextBlock] = []
        texts.reserveCapacity(count)
        var sizes = [CGSize](repeating: .zero, count: count)
        var offsets = [CGFloat](repeating: 0, count: count)
        let plain = BlockAppearance()
        for (flowchartIndex, graphIndex) in clustered.drawnGraphIndices.enumerated() {
            let label = Self.label(nodes[graphIndex].label, type: nodes[graphIndex].labelType, in: text)
            let measured = PlaneMapLabel.block(label, measurer: restyled.measurer(for: looks.styledAppearances[graphIndex] ?? plain), maximumWidth: wrappingWidth)
            texts.append(measured)
            (sizes[flowchartIndex], offsets[flowchartIndex]) = Self.size(ofShape: nodes[graphIndex].shape, textSize: measured.size, minimumWidth: minimumWidth)
        }
        texts += repeatElement(DiagramTextBlock(label: DiagramLabel(lines: []), measurer: nodeText, maximumWidth: 0), count: count - texts.count)
        let edgeTexts = Self.edgeTexts(of: clustered, in: model, measurer: edgeText, wrappingWidth: wrappingWidth)
        heldEdgeTexts = edgeTexts.held
        var flowchartMeasurement = FlowchartMeasurement(nodeTexts: texts, shapeSizes: sizes, textOffsets: offsets, edgeTexts: edgeTexts.laidOut,
                                                        selfLoopEdgeIndices: clustered.selfLoopEdgeIndices)
        // Pele gives an agent flow's nodes no span: the edges on one side of a node meet in its middle.
        flowchartMeasurement.spreadsEdgeEnds = false
        self.flowchartMeasurement = flowchartMeasurement
    }

    /// The texts of the edges laid out, in their order, and of the edges held back, by graph edge index.
    private static func edgeTexts(of clustered: AgentFlowClusterGraph, in model: AgentFlowModel, measurer: some DiagramTextMeasuring,
                                  wrappingWidth: CGFloat) -> (laidOut: [DiagramTextBlock?], held: [Int: DiagramTextBlock]) {
        var laidOut: [DiagramTextBlock?] = []
        laidOut.reserveCapacity(clustered.laidOutEdgeIndices.count)
        for edgeIndex in clustered.laidOutEdgeIndices {
            laidOut.append(edgeText(of: edgeIndex, in: model, measurer: measurer, wrappingWidth: wrappingWidth))
        }
        var held: [Int: DiagramTextBlock] = [:]
        for heldEdge in clustered.heldEdges {
            held[heldEdge.edgeIndex] = edgeText(of: heldEdge.edgeIndex, in: model, measurer: measurer, wrappingWidth: wrappingWidth)
        }
        return (laidOut, held)
    }

    /// The text of the graph's edge at `edgeIndex` measured, or nil when it has none.
    private static func edgeText(of edgeIndex: Int, in model: AgentFlowModel, measurer: some DiagramTextMeasuring,
                                 wrappingWidth: CGFloat) -> DiagramTextBlock? {
        let raw = model.edges[Int(model.graph.edges[edgeIndex].edge)]
        guard !raw.text.isEmpty else { return nil }
        let measured = PlaneMapLabel.block(label(raw.text, type: raw.labelType, in: model.text), measurer: measurer, maximumWidth: wrappingWidth)
        return measured.lineCount == 0 ? nil : measured
    }

    /// Each graph node's style and text look from its classes' styles then its own, and the look of each node that has
    /// styles (a node without any has no style and the look of no declaration, `BlockAppearance()`).
    private static func looks(of model: AgentFlowModel)
        -> (styles: [DiagramElementStyle?], textLooks: [(isBold: Bool, isItalic: Bool)], styledAppearances: [Int: BlockAppearance]) {
        let nodes = model.graph.nodes
        var styles: [DiagramElementStyle?] = []
        var textLooks: [(isBold: Bool, isItalic: Bool)] = []
        var styledAppearances: [Int: BlockAppearance] = [:]
        for index in nodes.indices where !nodes[index].compiledStyles.isEmpty || !nodes[index].styles.isEmpty {
            if styles.isEmpty {
                styles = [DiagramElementStyle?](repeating: nil, count: nodes.count)
                textLooks = [(isBold: Bool, isItalic: Bool)](repeating: (false, false), count: nodes.count)
            }
            let declarations = model.graphStyleStrings(nodes[index].compiledStyles) + model.graphStyleStrings(nodes[index].styles)
            styles[index] = style(declarations)
            let appearance = BlockAppearance(classNames: nil, styles: declarations, classes: [:])
            textLooks[index] = (appearance.isBold, appearance.isItalic)
            styledAppearances[index] = appearance
        }
        return (styles, textLooks, styledAppearances)
    }

    /// The style of the graph node at `index`, or nil.
    func style(of index: Int) -> DiagramElementStyle? { styles.isEmpty ? nil : styles[index] }

    /// The weight and slant of the text of the graph node at `index`.
    func textLook(of index: Int) -> (isBold: Bool, isItalic: Bool) { textLooks.isEmpty ? (false, false) : textLooks[index] }

    /// A node's shape around its text, and how far below the shape's center the text is: a collapsed flow is a box with
    /// room for its dots below the text, any other shape is sized for text at least `minimumWidth` wide but a diamond,
    /// which grows twice as fast as its text and so keeps the text's own width. `shape` is a number of
    /// `AgentFlowShapeNames`.
    static func size(ofShape shape: Int16, textSize: CGSize, minimumWidth: CGFloat) -> (CGSize, CGFloat) {
        guard shape != AgentFlowShapeNames.collapsedGroup else {
            return (CGSize(width: max(textSize.width, minimumWidth) + 2 * FlowchartShapeGeometry.horizontalPadding,
                           height: textSize.height + 2 * FlowchartShapeGeometry.verticalPadding + AgentFlowLayoutEngine.collapsedMarkHeight),
                    -AgentFlowLayoutEngine.collapsedMarkHeight / 2)
        }
        let drawn = AgentFlowShapeNames.drawnShapes[Int(shape)]
        let sizingWidth = drawn == .diamond ? textSize.width : max(textSize.width, minimumWidth)
        let sized = FlowchartShapeGeometry.size(of: drawn, textSize: CGSize(width: sizingWidth, height: textSize.height))
        return (sized.size, sized.textOffset)
    }

    /// The text of the range `range` of `text` as drawn: a Markdown string loses its markers, `<br>` breaks lines.
    static func label(_ range: MermaidTextRange, type: AgentFlowLabelType, in text: AgentFlowTextBytes) -> DiagramLabel {
        guard !range.isEmpty else { return DiagramLabel(lines: []) }
        return text.bytes.withUnsafeBufferPointer { bytes in
            DiagramLabelDecoder.label(fromUTF8: UnsafeBufferPointer(rebasing: bytes[range.lowerBound..<range.upperBound]),
                                      form: type == .markdown ? .markdown : .plain)
        }
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
