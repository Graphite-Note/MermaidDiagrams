/**
 * File: SequenceParticipantShapeDrawing.swift
 * -------------------------------------------
 * Layer: Core
 * Description: The paths of a sequence participant's shape, Pele's: a box, the actor's stick figure, the boundary,
 *              control, entity and database figures, the two cards of collections and the queue's lying cylinder.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

import CoreGraphics

/// The participants' paths by how they are painted (`sequence/actors.ts`): shapes filled with the surface and outlined
/// in the border color, lines stroked in the border color, and the front card of collections, filled and outlined after
/// the others so that it hides the back card's outline.
struct SequenceParticipantShapeDrawing<Path: DiagramCurvedPathRecording> {
    let shapes: Path
    let lines: Path
    let frontShapes: Path

    init<Maker: DiagramPathMaking>(participants: [SequenceLayoutParticipant], making maker: Maker) where Maker.Path == Path {
        shapes = maker.makePath()
        lines = maker.makePath()
        frontShapes = maker.makePath()
        for participant in participants { add(participant.kind, in: participant.frame, making: maker) }
    }

    private func add<Maker: DiagramPathMaking>(_ kind: SequenceParticipantKind, in frame: CGRect, making maker: Maker) where Maker.Path == Path {
        let centerX = frame.midX
        let top = frame.minY
        func point(_ horizontal: CGFloat, _ depth: CGFloat) -> CGPoint { CGPoint(x: centerX + horizontal, y: top + depth) }
        func circle(_ horizontal: CGFloat, _ depth: CGFloat) -> CGRect {
            let radius: CGFloat = 11
            return CGRect(x: centerX + horizontal - radius, y: top + depth - radius, width: 2 * radius, height: 2 * radius)
        }
        let cornerRadius = SequenceDrawingParts.cornerRadius
        switch kind {
        case .participant: maker.addMadeRoundedRectangle(frame, cornerWidth: cornerRadius, cornerHeight: cornerRadius, to: shapes)
        case .actor:
            shapes.addEllipse(in: SequenceParticipantGeometry.figureHead(in: frame))
            for limb in SequenceParticipantGeometry.figureLimbs(in: frame) { lines.addLines(between: limb) }
        case .boundary:
            lines.addLines(between: [point(-19, 6), point(-19, 28)])
            lines.addLines(between: [point(-19, 17), point(-8, 17)])
            shapes.addEllipse(in: circle(3, 17))
        case .control:
            shapes.addEllipse(in: circle(0, 21))
            lines.addLines(between: [point(5, 5), point(-1, 10), point(5, 15)])
        case .entity:
            shapes.addEllipse(in: circle(0, 15))
            lines.addLines(between: [point(-11, 30), point(11, 30)])
        case .database: addDatabase(centerX: centerX, top: top)
        case .collections:
            let offset = SequenceParticipantGeometry.collectionsOffset
            let cardSize = CGSize(width: frame.width - offset, height: frame.height - offset)
            maker.addMadeRoundedRectangle(CGRect(origin: CGPoint(x: frame.minX + offset, y: top), size: cardSize), cornerWidth: cornerRadius,
                                          cornerHeight: cornerRadius, to: shapes)
            maker.addMadeRoundedRectangle(CGRect(origin: CGPoint(x: frame.minX, y: top + offset), size: cardSize), cornerWidth: cornerRadius,
                                          cornerHeight: cornerRadius, to: frontShapes)
        case .queue: addQueue(in: frame)
        }
    }

    /// A cylinder 28 points wide whose ends are ellipses 5 points high, from 7 to 27 points under the top, and the front
    /// half of its top end.
    private func addDatabase(centerX: CGFloat, top: CGFloat) {
        let radii = CGSize(width: 14, height: 5)
        let topCenter = CGPoint(x: centerX, y: top + 7)
        let bottomCenter = CGPoint(x: centerX, y: top + 27)
        shapes.move(to: CGPoint(x: centerX - radii.width, y: topCenter.y))
        shapes.addLine(to: CGPoint(x: centerX - radii.width, y: bottomCenter.y))
        Self.addHalfEllipse(to: shapes, center: bottomCenter, radii: radii, from: .pi, to: 0, isClockwise: true)
        shapes.addLine(to: CGPoint(x: centerX + radii.width, y: topCenter.y))
        Self.addHalfEllipse(to: shapes, center: topCenter, radii: radii, from: 0, to: -.pi, isClockwise: true)
        shapes.closeSubpath()
        lines.move(to: CGPoint(x: centerX - radii.width, y: topCenter.y))
        Self.addHalfEllipse(to: lines, center: topCenter, radii: radii, from: .pi, to: 0, isClockwise: true)
    }

    /// A cylinder lying on its side: its ends are half ellipses 6 points wide as tall as the frame, and the inner half of
    /// its right end.
    private func addQueue(in frame: CGRect) {
        let cap = SequenceParticipantGeometry.queueCapWidth
        let radii = CGSize(width: cap, height: frame.height / 2)
        let left = frame.minX + cap
        let right = frame.maxX - cap
        shapes.move(to: CGPoint(x: left, y: frame.minY))
        shapes.addLine(to: CGPoint(x: right, y: frame.minY))
        Self.addHalfEllipse(to: shapes, center: CGPoint(x: right, y: frame.midY), radii: radii, from: -.pi / 2, to: .pi / 2, isClockwise: false)
        shapes.addLine(to: CGPoint(x: left, y: frame.maxY))
        Self.addHalfEllipse(to: shapes, center: CGPoint(x: left, y: frame.midY), radii: radii, from: .pi / 2, to: 3 * .pi / 2, isClockwise: false)
        shapes.closeSubpath()
        lines.move(to: CGPoint(x: right, y: frame.minY))
        Self.addHalfEllipse(to: lines, center: CGPoint(x: right, y: frame.midY), radii: radii, from: -.pi / 2, to: -3 * .pi / 2, isClockwise: true)
    }

    /// Half an ellipse from angle `start` to `end`, on a page whose y runs down: angles grow toward the bottom, and
    /// Core Graphics' `clockwise` is against their growth there.
    private static func addHalfEllipse(to path: Path, center: CGPoint, radii: CGSize, from start: CGFloat, to end: CGFloat, isClockwise: Bool) {
        let transform = CGAffineTransform(a: radii.width, b: 0, c: 0, d: radii.height, tx: center.x, ty: center.y)
        path.addArc(center: .zero, radius: 1, startAngle: start, endAngle: end, clockwise: isClockwise, transform: transform)
    }
}
