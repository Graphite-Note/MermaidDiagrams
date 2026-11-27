/**
 * File: FlowchartPagePieces.swift
 * -------------------------------
 * Layer: Core
 * Description: The pieces of a flowchart's page, each written into the layout's records where the layout placed it,
 *              moved onto the page as it is written: a node, an edge along its route, a loop; and the page's frame (its
 *              size, the title's place and how far everything moves inside the padding).
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 26/11/2026
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

/// A flowchart's nodes, edges and loops written into its layout's records where the page draws them: each made where
/// the layout placed it and moved by the page's offset as it is written.
enum FlowchartPagePieces {
    /// Node `node` at `center`, its text below the shape's center by its offset, moved by `offset`.
    static func appendNode(_ node: Int, of diagram: FlowchartDiagram, center: CGPoint, measured: FlowchartMeasurement, offset: CGVector,
                           to recording: inout FlowchartLayoutRecording) {
        var text = measured.nodeText(of: node)
        text.center = CGPoint(x: center.x, y: center.y + measured.textOffset(of: node)).translated(by: offset)
        let size = measured.shapeSize(of: node)
        let frame = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
        recording.appendNode(shape: diagram.nodeShape(at: node), frame: frame.offsetBy(dx: offset.dx, dy: offset.dy), text: text,
                             style: diagram.nodeStyle(at: node), asset: diagram.nodeAsset(at: node))
    }

    /// Edge `edgeIndex` through `points`, its ends on their outlines, each segment an S along the flow its axis gives,
    /// its text at `textCenter`, moved by `offset`. The route's ends are trimmed for the marks where they lie in `points`.
    static func appendEdge<Axes: RandomAccessCollection<Bool>>(_ edgeIndex: Int, of diagram: FlowchartDiagram, along points: ScratchSpan<CGPoint>,
                                                               segmentsRunVertically: Axes, textCenter: CGPoint, measured: FlowchartMeasurement,
                                                               offset: CGVector, to recording: inout FlowchartLayoutRecording) where Axes.Index == Int {
        let edge = diagram.edgeDrawing(at: edgeIndex)
        let sourceTip = points[0]
        let targetTip = points[points.count - 1]
        let firstSegment = recording.segments.count
        let drawn = DiagramRouteDrawing.appendPath(through: points, segmentsRunVertically: segmentsRunVertically,
                                                   startTrim: DiagramEdgeMark.lineTrim(for: edge.sourceArrowhead),
                                                   endTrim: DiagramEdgeMark.lineTrim(for: edge.targetArrowhead), offset: offset, to: &recording.segments)
        let leaving = CGVector(dx: -drawn.startDirection.dx, dy: -drawn.startDirection.dy)
        recording.appendEdge(stroke: edge.stroke, start: drawn.start, firstSegment: firstSegment,
                             sourceMark: mark(edge.sourceArrowhead, tip: sourceTip, direction: leaving)?.translated(by: offset),
                             targetMark: mark(edge.targetArrowhead, tip: targetTip, direction: drawn.endDirection)?.translated(by: offset),
                             text: placed(measured.edgeText(of: edgeIndex), at: textCenter.translated(by: offset)), style: edge.style)
    }

    /// The `loopIndex`-th drawn loop of `node`, edge `edgeIndex`, as Pele's `loopPath` draws it (`FlowchartSelfLoops`); a
    /// group's from the middle of its box (`shapeSize` zero), as Pele loops a group whose drawn node has no size. Moved by
    /// `offset`; returns the loop's stroke.
    @discardableResult
    static func appendSelfLoop(_ edgeIndex: Int, of diagram: FlowchartDiagram, node: Int, center: CGPoint, shapeSize: CGSize, loopIndex: Int,
                               flowRunsAcross: Bool, measured: FlowchartMeasurement, offset: CGVector,
                               to recording: inout FlowchartLayoutRecording) -> FlowchartEdgeStroke {
        let edge = diagram.edgeDrawing(at: edgeIndex)
        let text = measured.edgeText(of: edgeIndex)
        let loop = FlowchartSelfLoops.loop(center: center, shapeSize: shapeSize, loopIndex: loopIndex, flowRunsAcross: flowRunsAcross,
                                           endTrim: DiagramEdgeMark.lineTrim(for: edge.targetArrowhead), textSize: text?.size)
        let firstSegment = recording.segments.count
        let start = DiagramRouteDrawing.appendSegments(of: loop.path, offset: offset, to: &recording.segments)
        recording.appendEdge(stroke: edge.stroke, start: start, firstSegment: firstSegment,
                             sourceMark: mark(edge.sourceArrowhead, tip: loop.leave, direction: loop.intoNodeAtLeave)?.translated(by: offset),
                             targetMark: mark(edge.targetArrowhead, tip: loop.back, direction: loop.arriving)?.translated(by: offset),
                             text: placed(text, at: loop.textCenter.translated(by: offset)), style: edge.style)
        return edge.stroke
    }

    static func mark(_ arrowhead: FlowchartArrowhead, tip: CGPoint, direction: CGVector) -> DiagramEdgeMark? {
        arrowhead == .none ? nil : DiagramEdgeMark(arrowhead: arrowhead, tip: tip, direction: direction)
    }

    /// `text` centered at `center`, or nil.
    static func placed(_ text: DiagramPlacedText?, at center: CGPoint) -> DiagramPlacedText? {
        guard var text else { return nil }
        text.center = center
        return text
    }
}
