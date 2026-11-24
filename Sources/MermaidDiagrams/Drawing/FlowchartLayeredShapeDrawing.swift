/**
 * File: FlowchartLayeredShapeDrawing.swift
 * ----------------------------------------
 * Layer: Core
 * Description: The flowchart node shapes Pele paints piece by piece: a person, stacked documents and rectangles, a
 *              collapsed group, a fork's bar, a junction, a stop and a data store.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

import CoreGraphics

/// One piece of a node shape painted piece by piece, in its shape's order: the pieces may overlap, so each is filled
/// and stroked before the next is.
public struct FlowchartShapeLayer {
    public let path: CGPath
    public let painting: FlowchartShapeLayerPainting
}

/// How a piece of a shape is painted.
public enum FlowchartShapeLayerPainting: Equatable, Sendable {
    /// Filled in the surface color and outlined in the border color, as a shape's outline is.
    case filledAndOutlined
    /// Outlined in the border color: lines over the pieces before.
    case outlined
    /// Filled in the line color and outlined in the border color: a fork's bar, a junction's dot.
    case filledInLineColorAndOutlined
    /// Filled in the surface color, not outlined: a data store's box, whose open ends are not drawn.
    case filledOnly
}

/// The pieces of the shapes Pele draws as several SVG elements that overlap or are painted unlike an outline
/// (`svg/shapes.ts`: `person`, `docs`, `st-rect`, `collapsedGroup`, `fork`, `f-circ`, `fr-circ`, `datastore`).
enum FlowchartLayeredShapeDrawing {
    private static let boxCornerRadius = FlowchartShapeDrawing.rectangleCornerRadius

    /// The pieces, back to front, or nil for a shape painted as one outline and its lines.
    static func layers(of shape: FlowchartNodeShape, in frame: CGRect) -> [FlowchartShapeLayer]? {
        var layers: [FlowchartShapeLayer] = []
        let isLayered = forEachLayer(of: shape, in: frame, making: DiagramCoreGraphicsPaths()) { piece, painting in
            layers.append(FlowchartShapeLayer(path: piece.path, painting: painting))
        }
        return isLayered ? layers : nil
    }

    /// Calls `body` with each piece made by `maker` and how it is painted, back to front, and says whether the shape is
    /// painted piece by piece; nothing is made for a shape painted as one outline and its lines.
    static func forEachLayer<Maker: DiagramPathMaking>(of shape: FlowchartNodeShape, in frame: CGRect, making maker: Maker,
                                                       _ body: (Maker.Path, FlowchartShapeLayerPainting) -> Void) -> Bool {
        switch shape {
        case .person:
            let torso = CGRect(x: frame.minX, y: frame.minY + 26, width: frame.width, height: frame.height - 26)
            let headRadius: CGFloat = 13
            let head = CGRect(x: frame.midX - headRadius, y: frame.minY + 14 - headRadius, width: 2 * headRadius, height: 2 * headRadius)
            body(FlowchartExtendedShapeDrawing.roundedRectangle(torso, radius: 12, making: maker), .filledAndOutlined)
            body(maker.ellipse(in: head), .filledAndOutlined)
        case .stackedDocument:
            for index in 0..<3 {
                let center = CGPoint(x: frame.midX + CGFloat(1 - index) * 4, y: frame.midY + CGFloat(index - 1) * 4)
                body(FlowchartExtendedShapeDrawing.wave(width: frame.width - 8, height: frame.height - 8, center: center, making: maker), .filledAndOutlined)
            }
        case .stackedRectangle:
            for index in 0..<3 {
                let sheet = CGRect(x: frame.minX + CGFloat(2 - index) * 4, y: frame.minY + CGFloat(index) * 4, width: frame.width - 8, height: frame.height - 8)
                body(FlowchartExtendedShapeDrawing.roundedRectangle(sheet, radius: boxCornerRadius, making: maker), .filledAndOutlined)
            }
        case .collapsedGroup:
            let behind = CGRect(x: frame.minX + 6, y: frame.minY + 8, width: frame.width - 12, height: frame.height - 8)
            let front = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height - 4)
            body(FlowchartExtendedShapeDrawing.roundedRectangle(behind, radius: boxCornerRadius, making: maker), .filledAndOutlined)
            body(FlowchartExtendedShapeDrawing.roundedRectangle(front, radius: boxCornerRadius, making: maker), .filledAndOutlined)
        case .forkJoin: body(FlowchartExtendedShapeDrawing.roundedRectangle(frame, radius: 2, making: maker), .filledInLineColorAndOutlined)
        case .filledCircle: body(maker.ellipse(in: frame), .filledInLineColorAndOutlined)
        case .framedCircle:
            let ringWidth: CGFloat = 4
            body(maker.ellipse(in: frame), .filledAndOutlined)
            body(maker.ellipse(in: frame.insetBy(dx: ringWidth, dy: ringWidth)), .filledInLineColorAndOutlined)
        case .dataStore: forEachDataStoreLayer(in: frame, making: maker, body)
        default: return false
        }
        return true
    }

    /// A data store: its box filled without an outline, then a line along its top and one along its bottom.
    private static func forEachDataStoreLayer<Maker: DiagramPathMaking>(in frame: CGRect, making maker: Maker,
                                                                        _ body: (Maker.Path, FlowchartShapeLayerPainting) -> Void) {
        body(maker.rectangle(frame), .filledOnly)
        let lines = maker.makePath()
        for y in [frame.minY, frame.maxY] {
            lines.move(to: CGPoint(x: frame.minX, y: y))
            lines.addLine(to: CGPoint(x: frame.maxX, y: y))
        }
        body(lines, .outlined)
    }
}
