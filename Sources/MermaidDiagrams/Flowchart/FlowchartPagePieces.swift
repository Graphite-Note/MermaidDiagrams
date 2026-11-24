/**
 * File: FlowchartPagePieces.swift
 * -------------------------------
 * Layer: Core
 * Description: The pieces of a flowchart's page, each made where the layout placed it: a node, an edge along its route,
 *              a loop, and the page's frame (its size, the title's place and how far everything moves inside the padding).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics

/// The page around a laid-out flowchart: the drawing starts `padding` from the top left, below the title, and is
/// centered under the title when the title is wider. The drawing is the layout's box, `extent` on the page from the
/// origin, as Pele sizes its page from the layout's width and height. Known before anything is placed on the page, so
/// that each piece is made once and moved by `offset`.
struct FlowchartPageFrame {
    /// How far every piece moves from where the layout placed it.
    let offset: CGVector
    let size: CGSize
    /// The title, centered above the drawing.
    let title: DiagramTextBlock?

    init(extent: CGSize, title: DiagramTextBlock?, padding: CGFloat = FlowchartLayoutEngine.padding,
         titleGap: CGFloat = FlowchartLayoutEngine.titleGap) {
        let bounds = CGRect(origin: .zero, size: extent)
        let titleSize = title?.size ?? .zero
        let innerWidth = max(bounds.width, titleSize.width)
        let titleHeight = title == nil ? 0 : titleSize.height + titleGap
        offset = CGVector(dx: padding + (innerWidth - bounds.width) / 2 - bounds.minX, dy: padding + titleHeight - bounds.minY)
        size = CGSize(width: (innerWidth + 2 * padding).rounded(.up), height: (bounds.height + titleHeight + 2 * padding).rounded(.up))
        var placedTitle = title
        placedTitle?.center = CGPoint(x: size.width / 2, y: padding + titleSize.height / 2)
        self.title = placedTitle
    }
}

/// A flowchart's nodes, edges and loops as the page draws them, before they are moved by the page's offset.
enum FlowchartPagePieces {
    /// Node `node` at `center`, its text below the shape's center by its offset.
    static func node(_ node: Int, of diagram: FlowchartDiagram, center: CGPoint, measured: FlowchartMeasurement) -> FlowchartLayoutNode {
        var text = measured.nodeTexts[node]
        text.center = CGPoint(x: center.x, y: center.y + measured.textOffsets[node])
        let size = measured.shapeSizes[node]
        return FlowchartLayoutNode(shape: diagram.nodeShape(at: node),
                                   frame: CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height),
                                   text: text, style: diagram.nodeStyle(at: node), asset: diagram.nodeAsset(at: node))
    }

    /// Edge `edgeIndex` through `points`, its ends on their outlines, each segment an S along the flow, its text at
    /// `textCenter`.
    static func edge(_ edgeIndex: Int, of diagram: FlowchartDiagram, along points: [CGPoint], textCenter: CGPoint, flowIsVertical: Bool,
                     measured: FlowchartMeasurement) -> FlowchartLayoutEdge {
        let edge = diagram.edgeDrawing(at: edgeIndex)
        let drawn = DiagramRouteDrawing.path(through: points, flowIsVertical: flowIsVertical, startTrim: DiagramEdgeMark.lineTrim(for: edge.sourceArrowhead),
                                             endTrim: DiagramEdgeMark.lineTrim(for: edge.targetArrowhead))
        return Self.edge(edge, edgeIndex: edgeIndex, points: points, drawn: drawn, textCenter: textCenter, measured: measured)
    }

    /// Edge `edgeIndex` through `points`, each segment an S along its own flow.
    static func edge<Axes: RandomAccessCollection<Bool>>(_ edgeIndex: Int, of diagram: FlowchartDiagram, along points: [CGPoint], segmentsRunVertically: Axes,
                                                         textCenter: CGPoint, measured: FlowchartMeasurement) -> FlowchartLayoutEdge where Axes.Index == Int {
        let edge = diagram.edgeDrawing(at: edgeIndex)
        let drawn = DiagramRouteDrawing.path(through: points, segmentsRunVertically: segmentsRunVertically,
                                             startTrim: DiagramEdgeMark.lineTrim(for: edge.sourceArrowhead),
                                             endTrim: DiagramEdgeMark.lineTrim(for: edge.targetArrowhead))
        return Self.edge(edge, edgeIndex: edgeIndex, points: points, drawn: drawn, textCenter: textCenter, measured: measured)
    }

    private static func edge(_ edge: FlowchartEdgeDrawing, edgeIndex: Int, points: [CGPoint],
                             drawn: (path: DiagramPath, startDirection: CGVector, endDirection: CGVector), textCenter: CGPoint,
                             measured: FlowchartMeasurement) -> FlowchartLayoutEdge {
        let leaving = CGVector(dx: -drawn.startDirection.dx, dy: -drawn.startDirection.dy)
        return FlowchartLayoutEdge(stroke: edge.stroke, path: drawn.path,
                                   sourceMark: mark(edge.sourceArrowhead, tip: points[0], direction: leaving),
                                   targetMark: mark(edge.targetArrowhead, tip: points[points.count - 1], direction: drawn.endDirection),
                                   text: centered(measured.edgeTexts[edgeIndex], at: textCenter), style: edge.style)
    }

    /// The `loopIndex`-th drawn loop of `node`, edge `edgeIndex`, as Pele's `loopPath` draws it (`FlowchartSelfLoops`); a
    /// group's from the middle of its box (`shapeSize` zero), as Pele loops a group whose drawn node has no size.
    static func selfLoop(_ edgeIndex: Int, of diagram: FlowchartDiagram, node: Int, center: CGPoint, shapeSize: CGSize, loopIndex: Int,
                         flowRunsAcross: Bool, measured: FlowchartMeasurement) -> FlowchartLayoutEdge {
        let edge = diagram.edgeDrawing(at: edgeIndex)
        let text = measured.edgeTexts[edgeIndex]
        let loop = FlowchartSelfLoops.loop(center: center, shapeSize: shapeSize, loopIndex: loopIndex, flowRunsAcross: flowRunsAcross,
                                           endTrim: DiagramEdgeMark.lineTrim(for: edge.targetArrowhead), textSize: text?.size)
        return FlowchartLayoutEdge(stroke: edge.stroke, path: loop.path,
                                   sourceMark: mark(edge.sourceArrowhead, tip: loop.leave, direction: loop.intoNodeAtLeave),
                                   targetMark: mark(edge.targetArrowhead, tip: loop.back, direction: loop.arriving),
                                   text: centered(text, at: loop.textCenter), style: edge.style)
    }

    static func mark(_ arrowhead: FlowchartArrowhead, tip: CGPoint, direction: CGVector) -> DiagramEdgeMark? {
        arrowhead == .none ? nil : DiagramEdgeMark(arrowhead: arrowhead, tip: tip, direction: direction)
    }

    static func centered(_ text: DiagramTextBlock?, at center: CGPoint) -> DiagramTextBlock? {
        guard var text else { return nil }
        text.center = center
        return text
    }
}
