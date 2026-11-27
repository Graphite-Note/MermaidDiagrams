/**
 * File: FlowchartDrawingPaths.swift
 * ---------------------------------
 * Layer: Core
 * Description: A laid-out flowchart's edges and nodes of the usual look grouped by how they are painted, recorded into
 *              Core Graphics paths for the public drawing parts or into lanes for the scene, by the same drawing, from
 *              the layout's flat records.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 26/11/2026
 */

import CoreGraphics

/// The edges' lines by stroke, their marks, and the patches behind their text, in any kind a drawing records. The edges a
/// diagram styles are left to be painted apart (`FlowchartStyledEdgeParts`); an invisible edge has only its patch.
struct FlowchartEdgePaths<Path: DiagramPathRecording> {
    let solid: Path
    let thick: Path
    let dotted: Path
    let filledMarks: Path
    let strokedMarks: Path
    let textPatches: Path

    init<Maker: DiagramPathMaking>(records: FlowchartLayoutRecords, making maker: Maker) where Maker.Path == Path {
        solid = maker.makePath()
        thick = maker.makePath()
        dotted = maker.makePath()
        filledMarks = maker.makePath()
        strokedMarks = maker.makePath()
        textPatches = maker.makePath()
        for edge in records.edges {
            if !edge.isStyled { addLineAndMarks(of: edge, in: records, making: maker) }
            if let text = edge.text {
                let madeCount = maker.madePathCount
                textPatches.addPath(maker.roundedRectangle(text.frame.insetBy(dx: -FlowchartDrawingParts.edgeTextPatchExtraWidth / 2, dy: 0),
                                                           cornerWidth: FlowchartDrawingParts.edgeTextPatchCornerRadius,
                                                           cornerHeight: FlowchartDrawingParts.edgeTextPatchCornerRadius))
                maker.givePathsBack(downTo: madeCount)
            }
        }
    }

    /// Whether the edge is painted apart, in the stroke or colors the diagram gave it.
    static func isStyled(_ edge: FlowchartLayoutEdge) -> Bool {
        if case .none = edge.style { return false }
        return edge.stroke != .invisible
    }

    private func addLineAndMarks<Maker: DiagramPathMaking>(of edge: FlowchartPlacedEdge, in records: FlowchartLayoutRecords,
                                                           making maker: Maker) where Maker.Path == Path {
        let grouped: Path
        switch edge.stroke {
        case .solid: grouped = solid
        case .thick: grouped = thick
        case .dotted: grouped = dotted
        case .invisible: return
        }
        let madeCount = maker.madePathCount
        let line = maker.makePath()
        DiagramEdgeDrawing.record(edge, of: records, into: line)
        grouped.addPath(line)
        maker.givePathsBack(downTo: madeCount)
        if let mark = edge.sourceMark { DiagramEdgeDrawing.addMark(mark, filled: filledMarks, stroked: strokedMarks) }
        if let mark = edge.targetMark { DiagramEdgeDrawing.addMark(mark, filled: filledMarks, stroked: strokedMarks) }
    }
}

/// The node shapes of the usual look to fill, and their outlines and inner lines to stroke, in any kind a drawing
/// records. Nodes a diagram styles and shapes painted piece by piece are left to be painted apart.
struct FlowchartNodePaths<Path: DiagramPathRecording> {
    let fills: Path
    let outlines: Path

    init<Maker: DiagramPathMaking>(records: FlowchartLayoutRecords, making maker: Maker) where Maker.Path == Path {
        fills = maker.makePath()
        outlines = maker.makePath()
        for node in records.nodes where node.hasUsualLook {
            let madeCount = maker.madePathCount
            defer { maker.givePathsBack(downTo: madeCount) }
            if let asset = records.asset(at: node.assetIndex) {
                if let frame = FlowchartNodeAssetDrawing.frame(of: asset, in: node.frame, hasLabel: node.text.lineCount > 0, making: maker) {
                    fills.addPath(frame, alsoTo: outlines)
                }
                continue
            }
            if FlowchartLayeredShapeDrawing.isPaintedPieceByPiece(node.shape) { continue }
            if let outline = FlowchartShapeDrawing.outline(of: node.shape, in: node.frame, making: maker) { fills.addPath(outline, alsoTo: outlines) }
            if let innerLines = FlowchartShapeDrawing.innerLines(of: node.shape, in: node.frame, making: maker) { outlines.addPath(innerLines) }
        }
    }
}

extension FlowchartLayeredShapeDrawing {
    /// Whether the shape is painted piece by piece (`forEachLayer`), without making its pieces.
    static func isPaintedPieceByPiece(_ shape: FlowchartNodeShape) -> Bool {
        switch shape {
        case .person, .stackedDocument, .stackedRectangle, .collapsedGroup, .forkJoin, .filledCircle, .framedCircle, .dataStore: true
        default: false
        }
    }
}

extension FlowchartLayoutNode {
    /// Whether the diagram gave the node no colors of its own, asked without copying its style.
    var hasUsualLook: Bool {
        if case .none = style { return true }
        return false
    }

    var hasAsset: Bool {
        if case .none = asset { return false }
        return true
    }
}
