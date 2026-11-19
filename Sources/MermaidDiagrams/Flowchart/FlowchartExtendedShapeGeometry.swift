/**
 * File: FlowchartExtendedShapeGeometry.swift
 * ------------------------------------------
 * Layer: Core
 * Description: The size, the outline's inset and the edges' span of the flowchart node shapes written by name only, Pele's.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// The geometry of the shapes beyond Mermaid's classic ones, with Pele's numbers (`svg/shapes.ts`): the size around a
/// text, how far the outline lies inside the bounding box on a side, and how much of a side edges may spread along. A
/// shape Pele gives no inset or span has none: its edges meet its box at the middle of the side.
enum FlowchartExtendedShapeGeometry {
    private static let horizontalPadding = FlowchartShapeGeometry.horizontalPadding
    private static let verticalPadding = FlowchartShapeGeometry.verticalPadding
    private static let cornerClearance = FlowchartShapeGeometry.cornerClearance

    /// A shape's size around a text of `textSize`, and how far below the shape's center the text's center is; a shape
    /// Pele sizes as a plain box (a card, a data store, a tagged rectangle) is sized as one.
    static func size(of shape: FlowchartNodeShape, textSize: CGSize) -> (size: CGSize, textOffset: CGFloat) {
        if let fixed = fixedSize(of: shape) { return (fixed, 0) }
        let width = textSize.width + 2 * horizontalPadding
        let height = textSize.height + 2 * verticalPadding
        switch shape {
        case .ellipse: return (CGSize(width: textSize.width * 1.3 + 2 * horizontalPadding, height: textSize.height * 1.2 + 2 * verticalPadding), 0)
        case .linedRectangle: return (CGSize(width: width + 8, height: height), 0)
        case .dividedRectangle: return (CGSize(width: width, height: height + 8), 4)
        case .windowPane, .stackedRectangle: return (CGSize(width: width + 8, height: height + 8), 4)
        case .collapsedGroup: return (CGSize(width: width + 8, height: height + 8), -2)
        case .triangle, .flippedTriangle: return triangleSize(textSize: textSize, pointsDown: shape == .flippedTriangle)
        case .slopedRectangle: return (CGSize(width: width, height: height + 10), 5)
        case .notchedPentagon: return (CGSize(width: width, height: height), 0)
        case .delay: return (CGSize(width: width + height / 4, height: height), 0)
        case .horizontalCylinder: return (CGSize(width: width + 2 * horizontalCylinderCapDepth(height: height), height: height), 0)
        case .document, .taggedDocument: return (CGSize(width: width, height: height + 10), -5)
        case .linedDocument: return (CGSize(width: width + 8, height: height + 10), -5)
        case .stackedDocument: return (CGSize(width: width + 8, height: height + 18), -1)
        case .paperTape: return (CGSize(width: width, height: height + 16), 0)
        case .folder: return (CGSize(width: max(width, 64), height: height + 8), 4)
        case .bucket: return (CGSize(width: width + 20, height: height + 10), 3)
        case .console, .browser: return (CGSize(width: max(width, 72), height: height + 12), 6)
        case .person: return (CGSize(width: max(width, 56), height: height + 26), 13)
        case .bang: return (CGSize(width: width + 28, height: height + 24), 0)
        case .cloud: return (CGSize(width: width + 32, height: height + 24), 0)
        case .leftBrace, .rightBrace: return (CGSize(width: width + 12, height: height), 0)
        case .braces: return (CGSize(width: width + 24, height: height), 0)
        case .linedCylinder:
            let cylinderWidth = max(width, 56)
            let capDepth = FlowchartShapeGeometry.cylinderCapDepth(width: cylinderWidth)
            return (CGSize(width: cylinderWidth, height: height + 2 * capDepth + 8), capDepth / 2 + 4)
        case .curvedTrapezoid: return (CGSize(width: width + height * 0.6, height: height), 0)
        case .bowTieRectangle: return (CGSize(width: width + height * 0.4, height: height), 0)
        default: return (CGSize(width: max(width, 2 * horizontalPadding + 12), height: height), 0)
        }
    }

    /// The shapes drawn at one size whatever their text, which they do not show.
    private static func fixedSize(of shape: FlowchartNodeShape) -> CGSize? {
        switch shape {
        case .smallCircle, .filledCircle: CGSize(width: 14, height: 14)
        case .framedCircle: CGSize(width: 18, height: 18)
        case .forkJoin: CGSize(width: 72, height: 8)
        case .hourglass: CGSize(width: 32, height: 40)
        case .crossedCircle: CGSize(width: 44, height: 44)
        case .lightningBolt: CGSize(width: 36, height: 56)
        default: nil
        }
    }

    /// A triangle around its text: wide enough for the text to fit across it 10 points above its base (or below its
    /// top when it points down), Pele's `triSize`.
    private static func triangleSize(textSize: CGSize, pointsDown: Bool) -> (size: CGSize, textOffset: CGFloat) {
        let width = max(1.6 * textSize.width + 40, 80)
        let height = (textSize.height + 10) / (1 - (textSize.width + 8) / width)
        let textOffset = height / 2 - 10 - textSize.height / 2
        return (CGSize(width: width, height: height), pointsDown ? -textOffset : textOffset)
    }

    /// The depth of a horizontal cylinder's elliptical ends.
    static func horizontalCylinderCapDepth(height: CGFloat) -> CGFloat {
        min(12, height / 4)
    }

    /// How far inside the bounding box the outline is on `side`, `offset` from the side's middle.
    static func inset(of shape: FlowchartNodeShape, size: CGSize, side: DiagramSide, offset: CGFloat) -> CGFloat {
        let width = size.width
        let height = size.height
        switch shape {
        case .ellipse, .smallCircle, .framedCircle, .filledCircle, .crossedCircle:
            return side.isHorizontal ? FlowchartShapeGeometry.bulge(offset: offset, halfLength: width / 2, depth: height / 2)
                                     : FlowchartShapeGeometry.bulge(offset: offset, halfLength: height / 2, depth: width / 2)
        case .linedCylinder:
            let capDepth = FlowchartShapeGeometry.cylinderCapDepth(width: width)
            return side.isHorizontal ? FlowchartShapeGeometry.bulge(offset: offset, halfLength: width / 2, depth: capDepth) : 0
        case .triangle, .flippedTriangle, .lightningBolt: return side.isHorizontal ? 0 : width / 4
        case .hourglass: return side.isHorizontal ? 0 : width / 2
        case .slopedRectangle: return side == .top ? 5 : 0
        case .document, .stackedDocument, .taggedDocument, .linedDocument: return side == .bottom ? 10 : 0
        case .paperTape: return side.isHorizontal ? 8 : 0
        case .bucket: return side.isHorizontal ? 0 : height / 12
        case .bang: return 3
        case .cloud: return side.isHorizontal ? 1 : 2
        case .bowTieRectangle: return side == .right ? height * 0.2 : 0
        default: return 0
        }
    }

    /// How much of `side`, centered on its middle, the edges meeting it may spread along; none for a shape Pele gives
    /// no span, whose edges meet the middle of the side.
    static func span(of shape: FlowchartNodeShape, size: CGSize, side: DiagramSide) -> CGFloat {
        let length = side.isHorizontal ? size.width : size.height
        switch shape {
        case .ellipse, .smallCircle, .framedCircle, .filledCircle, .crossedCircle: return length * 0.6
        case .card, .dataStore, .linedRectangle, .dividedRectangle, .windowPane, .notchedPentagon, .console, .browser, .taggedRectangle:
            return length - 2 * cornerClearance
        case .forkJoin: return length - 8
        case .stackedRectangle: return length - 2 * cornerClearance - 8
        case .linedCylinder: return side.isHorizontal ? size.width * 0.6 : size.height - 2 * cornerClearance - 20
        default: return 0
        }
    }
}
