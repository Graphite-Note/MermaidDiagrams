/**
 * File: DiagramSceneRenderer.swift
 * --------------------------------
 * Layer: Core
 * Description: Draws any diagram's scene into a Core Graphics context in a palette's colors: the one Core Graphics
 *              painter of every diagram type, laying each shape's elements into the context where the scene keeps them.
 *
 * Authors: Bahey Shalash
 * Version: 0.5
 * Date: 24/11/2026
 */

import CoreGraphics

/// Draws a scene into a Core Graphics context whose origin is the scene's top left and whose y runs down (a flipped
/// bitmap, a PDF page), back to front, in `palette`'s colors. Nothing is read, laid out or measured here: drawing the
/// same scene in another palette is cheap. Each stroke sets its own width, dashes, caps and joins; the context's state is
/// restored afterwards.
public enum DiagramSceneRenderer {
    /// The series the diagram's own theme variables set are drawn in their colors over `palette`'s
    /// (`DiagramScene.palette(over:)`).
    public static func draw(_ scene: DiagramScene, in context: CGContext, palette: DiagramPalette) {
        var colors = DiagramPaintColors(palette: scene.palette(over: palette))
        var text = DiagramTextDrawing(font: scene.font)
        context.saveGState()
        scene.forEachItem { item in
            switch item {
            case .shape(let shape): paint(shape, colors: &colors, in: context)
            case .text(let placed): draw(placed, colors: &colors, text: &text, in: context)
            }
        }
        context.restoreGState()
    }

    /// The shape's path laid into the context again for each paint, from its elements: the context's path is used up
    /// by each fill, stroke or clip.
    private static func paint(_ shape: DiagramSceneShapeView, colors: inout DiagramPaintColors, in context: CGContext) {
        switch shape.painting {
        case .fill(let paint):
            fill(shape, with: paint, colors: &colors, in: context)
        case .stroke(let paint, let stroke):
            self.stroke(shape, with: paint, stroke, colors: &colors, in: context)
        case .fillAndStroke(let fillPaint, let strokePaint, let stroke):
            fill(shape, with: fillPaint, colors: &colors, in: context)
            self.stroke(shape, with: strokePaint, stroke, colors: &colors, in: context)
        case .gradientFill(let gradient):
            fill(shape, with: gradient, colors: &colors, in: context)
        }
    }

    /// The shape's elements added to the context's path, as `CGContext.addPath` adds a path's.
    private static func addPath(of shape: DiagramSceneShapeView, to context: CGContext) {
        shape.forEachElement { verb, points in
            switch verb {
            case .move: context.move(to: points[0])
            case .line: context.addLine(to: points[0])
            case .quadraticCurve: context.addQuadCurve(to: points[1], control: points[0])
            case .cubicCurve: context.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .close: context.closePath()
            }
        }
    }

    private static func fill(_ shape: DiagramSceneShapeView, with paint: DiagramPaint, colors: inout DiagramPaintColors, in context: CGContext) {
        context.setFillColor(colors.color(of: paint))
        addPath(of: shape, to: context)
        context.fillPath()
    }

    private static func stroke(_ shape: DiagramSceneShapeView, with paint: DiagramPaint, _ stroke: DiagramStroke, colors: inout DiagramPaintColors,
                               in context: CGContext) {
        context.setStrokeColor(colors.color(of: paint))
        context.setLineWidth(stroke.lineWidth)
        context.setLineDash(phase: 0, lengths: stroke.dashLengths)
        context.setLineCap(stroke.lineCap)
        context.setLineJoin(stroke.lineJoin)
        addPath(of: shape, to: context)
        context.strokePath()
    }

    /// The path filled with the gradient at its opacity, the end colors carried on past the gradient's ends.
    private static func fill(_ shape: DiagramSceneShapeView, with gradient: DiagramLinearGradient, colors: inout DiagramPaintColors,
                             in context: CGContext) {
        let ends = [colors.color(of: gradient.startPaint), colors.color(of: gradient.endPaint)]
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let coreGraphicsGradient = CGGradient(colorsSpace: space, colors: ends as CFArray, locations: [0, 1]) else { return }
        context.saveGState()
        addPath(of: shape, to: context)
        context.clip()
        context.setAlpha(gradient.opacity)
        context.drawLinearGradient(coreGraphicsGradient, start: gradient.startPoint, end: gradient.endPoint,
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        context.restoreGState()
    }

    /// The text where it lies, or turned by its rotation about its block's center.
    private static func draw(_ placed: DiagramSceneText, colors: inout DiagramPaintColors, text: inout DiagramTextDrawing, in context: CGContext) {
        let color = colors.color(of: placed.paint)
        let outline = placed.outline.map { outline in (color: colors.color(of: outline.paint), lineWidth: outline.lineWidth) }
        guard let rotation = placed.rotation else {
            return text.draw(placed.block, color: color, isBold: placed.isBold, isItalic: placed.isItalic, isMonospaced: placed.isMonospaced,
                             outline: outline, in: context)
        }
        context.saveGState()
        context.translateBy(x: placed.block.center.x, y: placed.block.center.y)
        context.rotate(by: rotation)
        var centered = placed.block
        centered.center = .zero
        text.draw(centered, color: color, isBold: placed.isBold, isItalic: placed.isItalic, isMonospaced: placed.isMonospaced, outline: outline, in: context)
        context.restoreGState()
    }
}

/// The colors of the paints of one drawing, each resolved once.
struct DiagramPaintColors {
    let palette: DiagramPalette
    private var colorsByPaint: [DiagramPaint: CGColor] = [:]

    init(palette: DiagramPalette) {
        self.palette = palette
    }

    mutating func color(of paint: DiagramPaint) -> CGColor {
        if let color = colorsByPaint[paint] { return color }
        let color = paint.color(in: palette)
        colorsByPaint[paint] = color
        return color
    }
}
