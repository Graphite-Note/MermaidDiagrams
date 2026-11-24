/**
 * File: StateDiagramShapeDrawing.swift
 * ------------------------------------
 * Layer: Core
 * Description: The outlines of a state diagram's shapes, Pele's, as scene paths in a frame.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import CoreGraphics

/// The outlines of a state diagram's shapes, Pele's, as Core Graphics paths in a frame.
enum StateDiagramShapeDrawing {
    /// The largest corner radius of a state's box: Pele's.
    static let boxCornerRadius: CGFloat = 10
    /// The corner radius of a fork's or a join's bar.
    static let barCornerRadius: CGFloat = 2
    /// The radius of an end's inner dot; its ring is half a point inside its frame, so that its stroke stays inside.
    static let endDotRadius: CGFloat = 5
    static let endRingInset: CGFloat = 0.5
    /// How far down and in a note's folded corner reaches.
    static let noteFoldSize: CGFloat = 8
    /// How far below a box's name the line under it is.
    static let ruleGap: CGFloat = 6

    /// A box, rounded at most `boxCornerRadius`.
    static func box(in frame: CGRect) -> DiagramScenePath {
        let radius = min(boxCornerRadius, frame.height / 2)
        return DiagramScenePath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius)
    }

    static func diamond(in frame: CGRect) -> DiagramScenePath {
        var path = DiagramScenePath()
        path.addLines(between: [CGPoint(x: frame.midX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.midY), CGPoint(x: frame.midX, y: frame.maxY),
                                CGPoint(x: frame.minX, y: frame.midY)])
        path.closeSubpath()
        return path
    }

    static func bar(in frame: CGRect) -> DiagramScenePath {
        DiagramScenePath(roundedRect: frame, cornerWidth: barCornerRadius, cornerHeight: barCornerRadius)
    }

    static func endRing(in frame: CGRect) -> DiagramScenePath {
        DiagramScenePath(ellipseIn: frame.insetBy(dx: endRingInset, dy: endRingInset))
    }

    static func endDot(in frame: CGRect) -> DiagramScenePath {
        DiagramScenePath(ellipseIn: CGRect(x: frame.midX - endDotRadius, y: frame.midY - endDotRadius, width: 2 * endDotRadius,
                                           height: 2 * endDotRadius))
    }

    /// A note's sheet, its top right corner cut off where it folds.
    static func noteSheet(in frame: CGRect) -> DiagramScenePath {
        var path = DiagramScenePath()
        path.addLines(between: [CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.maxX - noteFoldSize, y: frame.minY),
                                CGPoint(x: frame.maxX, y: frame.minY + noteFoldSize), CGPoint(x: frame.maxX, y: frame.maxY),
                                CGPoint(x: frame.minX, y: frame.maxY)])
        path.closeSubpath()
        return path
    }

    /// The fold of a note's top right corner.
    static func noteFold(in frame: CGRect) -> DiagramScenePath {
        var path = DiagramScenePath()
        path.addLines(between: [CGPoint(x: frame.maxX - noteFoldSize, y: frame.minY), CGPoint(x: frame.maxX - noteFoldSize, y: frame.minY + noteFoldSize),
                                CGPoint(x: frame.maxX, y: frame.minY + noteFoldSize)])
        return path
    }

    /// The line across a box under its name, above its other descriptions.
    static func rule(in frame: CGRect, below name: DiagramTextBlock) -> DiagramScenePath {
        var path = DiagramScenePath()
        let ruleHeight = name.frame.maxY + ruleGap
        path.move(to: CGPoint(x: frame.minX, y: ruleHeight))
        path.addLine(to: CGPoint(x: frame.maxX, y: ruleHeight))
        return path
    }
}
