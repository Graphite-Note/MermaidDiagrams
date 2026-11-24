/**
 * File: FlowchartScene.swift
 * --------------------------
 * Layer: Core
 * Description: A laid-out flowchart's scene: its geometry recorded into lanes of the thread's scene workspace and added
 *              back to front in the colors' roles, as Pele paints it, without a Core Graphics path.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 24/11/2026
 */

import CoreGraphics

extension DiagramScene {
    /// The flowchart's painting: the groups' boxes and the titles no edge crosses, the edges and their marks, the
    /// styled edges, the titles edges cross on their patches, the patches behind edge text and that text, the node
    /// shapes, those painted piece by piece, the styled ones, the nodes' text, the title.
    public init(layout: FlowchartLayout) {
        self = DiagramSceneWorkspace.withRecording { workspace in
            var builder = DiagramSceneBuilder(workspace: workspace)
            FlowchartSceneRecording.add(layout, to: &builder, workspace: workspace)
            return builder.scene(size: layout.size, font: layout.font)
        }
    }
}

/// Adds a flowchart's painting to a scene, its paths recorded into lanes of `workspace`: the groups', the edges' and the
/// usual nodes' grouped as `FlowchartDrawingParts` groups them, the styled and piece-by-piece ones each into lanes made
/// for a moment and given back once the builder has copied them. Swimlane diagrams add a flowchart's painting over their
/// lanes the same way.
enum FlowchartSceneRecording {
    /// Every line is drawn with round caps and joins.
    static func add(_ layout: FlowchartLayout, to builder: inout DiagramSceneBuilder, workspace: DiagramSceneWorkspace) {
        let line = DiagramStroke.rounded(lineWidth: FlowchartDrawingParts.lineWidth)
        let clusters = FlowchartClusterPaths(clusters: layout.clusters, making: workspace)
        addBoxes(of: clusters, to: &builder)
        let edges = FlowchartEdgePaths(edges: layout.edges, making: workspace)
        builder.stroke(edges.solid, .line, line, part: .edge)
        builder.stroke(edges.thick, .line, .rounded(lineWidth: FlowchartDrawingParts.thickLineWidth), part: .edge)
        builder.stroke(edges.dotted, .line, .rounded(lineWidth: FlowchartDrawingParts.lineWidth, dashLengths: FlowchartDrawingParts.dottedDashLengths),
                       part: .edge)
        builder.fill(edges.filledMarks, .line, part: .marker)
        builder.stroke(edges.strokedMarks, .line, line, part: .marker)
        for edge in layout.edges where FlowchartEdgePaths<DiagramPathLane>.isStyled(edge) { addStyled(edge, to: &builder, workspace: workspace, line: line) }
        addCrossedTitles(of: clusters, to: &builder)
        builder.fill(edges.textPatches, .background, part: .labelBackground)
        for edge in layout.edges { builder.text(edge.text, .foreground, part: .edgeLabel) }
        addNodes(of: layout, to: &builder, workspace: workspace, line: line)
        builder.title(layout.title)
    }

    /// The usual nodes' shapes, the pieces of those painted piece by piece, the styled nodes, then all the nodes' text.
    private static func addNodes(of layout: FlowchartLayout, to builder: inout DiagramSceneBuilder, workspace: DiagramSceneWorkspace,
                                 line: DiagramStroke) {
        let nodes = FlowchartNodePaths(nodes: layout.nodes, making: workspace)
        builder.fill(nodes.fills, .surface, part: .node)
        builder.stroke(nodes.outlines, .border, line, part: .node)
        for node in layout.nodes where node.hasUsualLook && !node.hasAsset {
            addLayers(of: node.shape, in: node.frame, style: nil, stroke: line, to: &builder, workspace: workspace)
        }
        for node in layout.nodes {
            guard let style = node.style else { continue }
            addStyled(node, style: style, to: &builder, workspace: workspace)
        }
        for node in layout.nodes where node.hasUsualLook { builder.text(node.text, .foreground, part: .label) }
        for node in layout.nodes {
            guard let style = node.style else { continue }
            builder.text(node.text, style.textColor.map(DiagramPaint.color) ?? .foreground, part: .label)
        }
    }

    /// An edge in the stroke or colors the diagram gave it: its line, then its marks in the line's color.
    private static func addStyled(_ edge: FlowchartLayoutEdge, to builder: inout DiagramSceneBuilder, workspace: DiagramSceneWorkspace,
                                  line: DiagramStroke) {
        guard let style = edge.style else { return }
        let madeCount = workspace.madePathCount
        defer { workspace.givePathsBack(downTo: madeCount) }
        let drawn = workspace.makeLane()
        DiagramEdgeDrawing.record(edge.path, into: drawn)
        let filled = workspace.makeLane()
        let stroked = workspace.makeLane()
        if let mark = edge.sourceMark { DiagramEdgeDrawing.addMark(mark, filled: filled, stroked: stroked) }
        if let mark = edge.targetMark { DiagramEdgeDrawing.addMark(mark, filled: filled, stroked: stroked) }
        let paint = style.stroke.map(DiagramPaint.color) ?? .line
        let width = style.strokeWidth ?? FlowchartStyledEdgeParts.usualLineWidth(of: edge.stroke)
        let dashes = style.strokeDashLengths ?? FlowchartStyledEdgeParts.usualDashLengths(of: edge.stroke)
        builder.stroke(drawn, paint, .rounded(lineWidth: width, dashLengths: dashes), part: .edge)
        builder.fill(filled, paint, part: .marker)
        builder.stroke(stroked, paint, line, part: .marker)
    }

    /// A node in the colors the diagram gave it: its pieces, or its shape filled and its outline and lines stroked.
    private static func addStyled(_ node: FlowchartLayoutNode, style: DiagramElementStyle, to builder: inout DiagramSceneBuilder,
                                  workspace: DiagramSceneWorkspace) {
        let madeCount = workspace.madePathCount
        defer { workspace.givePathsBack(downTo: madeCount) }
        let stroke = DiagramStroke.rounded(lineWidth: style.strokeWidth ?? FlowchartDrawingParts.lineWidth, dashLengths: style.strokeDashLengths ?? [])
        if !node.hasAsset, addLayers(of: node.shape, in: node.frame, style: style, stroke: stroke, to: &builder, workspace: workspace) { return }
        let fill: DiagramPathLane?
        let outline: DiagramPathLane
        if let asset = node.asset {
            fill = FlowchartNodeAssetDrawing.frame(of: asset, in: node, making: workspace)
            outline = fill ?? workspace.makeLane()
        } else {
            fill = FlowchartShapeDrawing.outline(of: node.shape, in: node.frame, making: workspace)
            outline = workspace.makeLane()
            if let fill { outline.addPath(fill) }
            if let innerLines = FlowchartShapeDrawing.innerLines(of: node.shape, in: node.frame, making: workspace) { outline.addPath(innerLines) }
        }
        if let fill { builder.fill(fill, style.fill.map(DiagramPaint.color) ?? .surface, part: .node) }
        builder.stroke(outline, style.stroke.map(DiagramPaint.color) ?? .border, stroke, part: .node)
    }

    /// The pieces of a shape painted piece by piece, each apart from the shapes before it, in the usual colors or in those
    /// a node's style sets: Pele's style overrides the fill and the stroke of every piece but a fork's or a junction's
    /// line-colored fill, and strokes a data store's box only when it sets a stroke. False for a shape painted otherwise.
    @discardableResult
    private static func addLayers(of shape: FlowchartNodeShape, in frame: CGRect, style: DiagramElementStyle?, stroke: DiagramStroke,
                                  to builder: inout DiagramSceneBuilder, workspace: DiagramSceneWorkspace) -> Bool {
        guard FlowchartLayeredShapeDrawing.isPaintedPieceByPiece(shape) else { return false }
        let madeCount = workspace.madePathCount
        defer { workspace.givePathsBack(downTo: madeCount) }
        let fillPaint = style?.fill.map(DiagramPaint.color) ?? .surface
        let strokePaint = style?.stroke.map(DiagramPaint.color) ?? .border
        return FlowchartLayeredShapeDrawing.forEachLayer(of: shape, in: frame, making: workspace) { piece, painting in
            builder.keepNextShapeApart()
            switch painting {
            case .filledAndOutlined: builder.fillAndStroke(piece, fill: fillPaint, stroke: strokePaint, stroke, part: .node)
            case .outlined: builder.stroke(piece, strokePaint, stroke, part: .node)
            case .filledInLineColorAndOutlined: builder.fillAndStroke(piece, fill: .line, stroke: strokePaint, stroke, part: .node)
            case .filledOnly:
                builder.fill(piece, fillPaint, part: .node)
                if let color = style?.stroke { builder.stroke(piece, .color(color), stroke, part: .node) }
            }
        }
    }

    /// The boxes behind everything: their fills depth by depth, their outlines and the titles no edge crosses.
    static func addBoxes(of clusters: FlowchartClusterPaths<DiagramPathLane>, to builder: inout DiagramSceneBuilder) {
        for depthFill in clusters.fillsByDepth { builder.fill(depthFill, FlowchartClusterDrawingParts.boxPaint, part: .cluster) }
        builder.stroke(clusters.outlines, .border, .rounded(lineWidth: FlowchartDrawingParts.lineWidth), part: .cluster)
        builder.texts(clusters.titles, .muted, part: .clusterLabel)
    }

    /// The titles edges run through, over the edges, each on a patch painted as its box is where it sits: the background,
    /// then the box's paint once for each box it is inside and its own.
    static func addCrossedTitles(of clusters: FlowchartClusterPaths<DiagramPathLane>, to builder: inout DiagramSceneBuilder) {
        for (depth, patches) in clusters.crossedTitlePatchesByDepth.enumerated() where !patches.isEmpty {
            builder.fill(patches, .background, part: .labelBackground)
            for _ in 0...depth { builder.fill(patches, FlowchartClusterDrawingParts.boxPaint, part: .labelBackground) }
        }
        builder.texts(clusters.crossedTitles, .muted, part: .clusterLabel)
    }
}

extension FlowchartClusterDrawingParts {
    /// Each box's inside: the alternate surface at `fillOpacity`.
    static let boxPaint = DiagramPaint.alternateSurface.atOpacity(fillOpacity)

    /// The boxes as Core Graphics paths, as `FlowchartSceneRecording` adds them from lanes: for a scene made from the
    /// public drawing parts' Core Graphics paths.
    func addBoxes(to builder: inout DiagramSceneBuilder) {
        for depthFill in fillsByDepth { builder.fill(depthFill, Self.boxPaint, part: .cluster) }
        builder.stroke(outlines, .border, .rounded(lineWidth: FlowchartDrawingParts.lineWidth), part: .cluster)
        builder.texts(titles, .muted, part: .clusterLabel)
    }

    func addCrossedTitles(to builder: inout DiagramSceneBuilder) {
        for (depth, patches) in crossedTitlePatchesByDepth.enumerated() where !patches.isEmpty {
            builder.fill(patches, .background, part: .labelBackground)
            for _ in 0...depth { builder.fill(patches, Self.boxPaint, part: .labelBackground) }
        }
        builder.texts(crossedTitles, .muted, part: .clusterLabel)
    }
}
