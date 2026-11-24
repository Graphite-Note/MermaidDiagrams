/**
 * File: UseCaseFigureShapes.swift
 * -------------------------------
 * Layer: Core
 * Description: The shapes of a use case diagram as Pele's renderUsecase draws them: an actor's figures, the slash of a
 *              business actor or use case, a note's folded corner, a JSON table's lines and a generalization's hollow
 *              triangle.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import CoreGraphics

/// Pele's figures in the coordinates of the figure's middle, which is 30 points below the top of an actor's node.
enum UseCaseFigureShapes {
    /// A plain figure's head, and its body, arms and legs as lines.
    static let headCenterY: CGFloat = -21
    static let headRadius: CGFloat = 9
    static let hollowHeadRadius: CGFloat = 8
    /// An icon actor's box, and where its slash's head would be.
    static let iconBox = CGRect(x: -22, y: -26, width: 44, height: 44)
    static let iconHeadCenterY: CGFloat = -14
    static let iconHeadRadius: CGFloat = 12
    /// How far a note's corner folds.
    static let noteFold: CGFloat = 9

    static func head(radius: CGFloat, at center: CGPoint) -> DiagramScenePath {
        DiagramScenePath(ellipseIn: CGRect(x: center.x - radius, y: center.y + headCenterY - radius, width: 2 * radius, height: 2 * radius))
    }

    /// `M0,-12V10M-14,-3H14M0,10L-12,30M0,10L12,30`.
    static func limbs(at center: CGPoint) -> DiagramScenePath {
        var path = DiagramScenePath()
        for (from, to) in [((0, -12), (0, 10)), ((-14, -3), (14, -3)), ((0, 10), (-12, 30)), ((0, 10), (12, 30))] as [((CGFloat, CGFloat), (CGFloat, CGFloat))] {
            path.move(to: CGPoint(x: center.x + from.0, y: center.y + from.1))
            path.addLine(to: CGPoint(x: center.x + to.0, y: center.y + to.1))
        }
        return path
    }

    /// The hollow figure's outlined body: `M-20,-9H20V0H5.5L20,15.5L12,25.5L0,12L-12,25.5L-20,15.5L-5.5,0H-20Z`.
    static func hollowBody(at center: CGPoint) -> DiagramScenePath {
        polygon([(-20, -9), (20, -9), (20, 0), (5.5, 0), (20, 15.5), (12, 25.5), (0, 12), (-12, 25.5), (-20, 15.5), (-5.5, 0), (-20, 0)], at: center)
    }

    /// The filled figure: a head of radius 11 at -19, and a body with rounded shoulders and foot corners.
    static func awesomeFigure(at center: CGPoint) -> DiagramScenePath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: center.x + x, y: center.y + y) }
        var path = DiagramScenePath()
        path.addEllipse(in: CGRect(x: center.x - 11, y: center.y - 30, width: 22, height: 22))
        path.move(to: point(-20, 25))
        path.addCurve(to: point(0, -3), control1: point(-20, 9), control2: point(-12, -3))
        path.addCurve(to: point(20, 25), control1: point(12, -3), control2: point(20, 9))
        path.addCurve(to: point(15, 30), control1: point(20, 28), control2: point(18, 30))
        path.addLine(to: point(-15, 30))
        path.addCurve(to: point(-20, 25), control1: point(-18, 30), control2: point(-20, 28))
        path.closeSubpath()
        return path
    }

    /// A business actor's slash: a chord across the lower right of the head.
    static func actorSlash(headY: CGFloat, radius: CGFloat, at center: CGPoint) -> DiagramScenePath {
        line(from: CGPoint(x: center.x + 0.12 * radius, y: center.y + headY + 0.99 * radius),
             to: CGPoint(x: center.x + 0.92 * radius, y: center.y + headY - 0.39 * radius))
    }

    /// A business use case's slash, cutting off the right end of its oval beside the text.
    static func ellipseSlash(in frame: CGRect) -> DiagramScenePath {
        let halfWidth = frame.width / 2
        let halfHeight = frame.height / 2
        func arc(_ at: CGFloat) -> CGFloat { halfHeight * max(1 - (at / halfWidth) * (at / halfWidth), 0).squareRoot() }
        let from = halfWidth - 15
        let to = halfWidth - 5
        return line(from: CGPoint(x: frame.midX + from, y: frame.midY + arc(from)), to: CGPoint(x: frame.midX + to, y: frame.midY - arc(to)))
    }

    /// A note's outline with its top right corner cut, and the fold's two lines.
    static func noteOutline(in frame: CGRect) -> DiagramScenePath {
        var path = DiagramScenePath()
        path.addLines(between: [CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.maxX - noteFold, y: frame.minY),
                                CGPoint(x: frame.maxX, y: frame.minY + noteFold), CGPoint(x: frame.maxX, y: frame.maxY), CGPoint(x: frame.minX, y: frame.maxY)])
        path.closeSubpath()
        return path
    }

    static func noteFold(in frame: CGRect) -> DiagramScenePath {
        var path = DiagramScenePath()
        path.addLines(between: [CGPoint(x: frame.maxX - noteFold, y: frame.minY), CGPoint(x: frame.maxX - noteFold, y: frame.minY + noteFold),
                                CGPoint(x: frame.maxX, y: frame.minY + noteFold)])
        return path
    }

    /// A JSON table's line under its header, and its key column's line when it has one.
    static func tableLines(in frame: CGRect, headHeight: CGFloat, keyColumnWidth: CGFloat) -> DiagramScenePath {
        var path = DiagramScenePath()
        let headerBottom = frame.minY + headHeight
        path.move(to: CGPoint(x: frame.minX, y: headerBottom))
        path.addLine(to: CGPoint(x: frame.maxX, y: headerBottom))
        if keyColumnWidth > 0 {
            path.move(to: CGPoint(x: frame.minX + keyColumnWidth, y: headerBottom))
            path.addLine(to: CGPoint(x: frame.minX + keyColumnWidth, y: frame.maxY))
        }
        return path
    }

    /// A generalization's hollow triangle, its tip at `tip`, pointing along `direction`.
    static func extensionTriangle(tip: CGPoint, direction: CGVector) -> DiagramScenePath {
        let length = UseCaseEdgeLine.extensionLength
        let base = CGPoint(x: tip.x - direction.dx * length, y: tip.y - direction.dy * length)
        let half = length / 2
        var path = DiagramScenePath()
        path.addLines(between: [tip, CGPoint(x: base.x - direction.dy * half, y: base.y + direction.dx * half),
                                CGPoint(x: base.x + direction.dy * half, y: base.y - direction.dx * half)])
        path.closeSubpath()
        return path
    }

    private static func polygon(_ corners: [(CGFloat, CGFloat)], at center: CGPoint) -> DiagramScenePath {
        var path = DiagramScenePath()
        path.addLines(between: corners.map { x, y in CGPoint(x: center.x + x, y: center.y + y) })
        path.closeSubpath()
        return path
    }

    private static func line(from start: CGPoint, to end: CGPoint) -> DiagramScenePath {
        var path = DiagramScenePath()
        path.move(to: start)
        path.addLine(to: end)
        return path
    }
}
