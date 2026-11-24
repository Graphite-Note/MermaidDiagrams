/**
 * File: DiagramFlatScene.swift
 * ----------------------------
 * Layer: Core (design prototype, not for merging)
 * Description: A scene's items as flat arrays: every path's verbs in one byte array and its points in one point array,
 *              each shape a range into them, each text its placed text, the items an ordered list of references.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics

/// The verbs of a flat path, one byte each, as Core Graphics names its elements.
public enum DiagramPathVerb: UInt8, Sendable {
    case move = 0
    case line = 1
    case quadraticCurve = 2
    case cubicCurve = 3
    case close = 4

    /// How many points follow the verb in the point array.
    @inline(__always)
    var pointCount: Int {
        switch self {
        case .move, .line: 1
        case .quadraticCurve: 2
        case .cubicCurve: 3
        case .close: 0
        }
    }
}

/// One shape of a flat scene: its path as ranges of the scene's verbs and points, its painting and its part.
public struct DiagramFlatShape: Sendable {
    public let verbStart: Int32
    public let verbCount: Int32
    public let pointStart: Int32
    public let painting: DiagramShapePainting
    public let part: DiagramScenePart
}

/// What one item of a flat scene is: a shape or a text, by its index in its array.
public struct DiagramFlatItem: Sendable {
    public let isText: Bool
    public let index: Int32
}

/// A scene as flat arrays. In the prototype it is made from a `DiagramScene` by reading its paths once (the elements
/// Core Graphics gives out, which the SVG writer writes today); in the design the scene builder writes it directly.
public struct DiagramFlatScene: Sendable {
    public let size: CGSize
    public let font: DiagramFont
    public let seriesColors: DiagramSeriesColors
    public private(set) var verbs: [DiagramPathVerb] = []
    public private(set) var points: [CGPoint] = []
    public private(set) var shapes: [DiagramFlatShape] = []
    public private(set) var texts: [DiagramSceneText] = []
    public private(set) var items: [DiagramFlatItem] = []
    /// Whether any shape is filled with a gradient, which needs `<defs>`.
    public private(set) var hasGradientFills = false

    public init(flattening scene: DiagramScene) {
        size = scene.size
        font = scene.font
        seriesColors = scene.seriesColors
        for item in scene.items {
            switch item {
            case .shape(let shape):
                let verbStart = verbs.count
                let pointStart = points.count
                shape.path.applyWithBlock { element in
                    let pointer = element.pointee.points
                    switch element.pointee.type {
                    case .moveToPoint:
                        verbs.append(.move)
                        points.append(pointer[0])
                    case .addLineToPoint:
                        verbs.append(.line)
                        points.append(pointer[0])
                    case .addQuadCurveToPoint:
                        verbs.append(.quadraticCurve)
                        points.append(pointer[0])
                        points.append(pointer[1])
                    case .addCurveToPoint:
                        verbs.append(.cubicCurve)
                        points.append(pointer[0])
                        points.append(pointer[1])
                        points.append(pointer[2])
                    case .closeSubpath:
                        verbs.append(.close)
                    @unknown default:
                        break
                    }
                }
                if case .gradientFill = shape.painting { hasGradientFills = true }
                items.append(DiagramFlatItem(isText: false, index: Int32(shapes.count)))
                shapes.append(DiagramFlatShape(verbStart: Int32(verbStart), verbCount: Int32(verbs.count - verbStart), pointStart: Int32(pointStart),
                                               painting: shape.painting, part: shape.part))
            case .text(let text):
                items.append(DiagramFlatItem(isText: true, index: Int32(texts.count)))
                texts.append(text)
            }
        }
    }
}
