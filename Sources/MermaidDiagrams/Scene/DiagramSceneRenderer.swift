/**
 * File: DiagramSceneRenderer.swift
 * --------------------------------
 * Layer: Core
 * Description: Draws any diagram's scene into a Core Graphics context in a palette's colors: the one Core Graphics
 *              painter of every diagram type.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 19/11/2026
 */

import CoreGraphics

/// Draws a scene into a Core Graphics context whose origin is the scene's top left and whose y runs down (a flipped
/// bitmap, a PDF page), back to front, in `palette`'s colors. Nothing is read, laid out or measured here: drawing the
/// same scene in another palette is cheap. Each stroke sets its own width, dashes, caps and joins; the context's state is
/// restored afterwards.
public enum DiagramSceneRenderer {
    public static func draw(_ scene: DiagramScene, in context: CGContext, palette: DiagramPalette) {
        var colors = DiagramPaintColors(palette: palette)
        var text = DiagramTextDrawing(font: scene.font)
        context.saveGState()
        for item in scene.items {
            switch item {
            case .shape(let shape): paint(shape, colors: &colors, in: context)
            case .text(let placed): draw(placed, colors: &colors, text: &text, in: context)
            }
        }
        context.restoreGState()
    }

    private static func paint(_ shape: DiagramSceneShape, colors: inout DiagramPaintColors, in context: CGContext) {
        switch shape.painting {
        case .fill(let paint):
            fill(shape.path, with: paint, colors: &colors, in: context)
        case .stroke(let paint, let stroke):
            self.stroke(shape.path, with: paint, stroke, colors: &colors, in: context)
        case .fillAndStroke(let fillPaint, let strokePaint, let stroke):
            fill(shape.path, with: fillPaint, colors: &colors, in: context)
            self.stroke(shape.path, with: strokePaint, stroke, colors: &colors, in: context)
        case .gradientFill(let gradient):
            fill(shape.path, with: gradient, colors: &colors, in: context)
        }
    }

    private static func fill(_ path: CGPath, with paint: DiagramPaint, colors: inout DiagramPaintColors, in context: CGContext) {
        context.setFillColor(colors.color(of: paint))
        context.addPath(path)
        context.fillPath()
    }

    private static func stroke(_ path: CGPath, with paint: DiagramPaint, _ stroke: DiagramStroke, colors: inout DiagramPaintColors,
                               in context: CGContext) {
        context.setStrokeColor(colors.color(of: paint))
        context.setLineWidth(stroke.lineWidth)
        context.setLineDash(phase: 0, lengths: stroke.dashLengths)
        context.setLineCap(stroke.lineCap)
        context.setLineJoin(stroke.lineJoin)
        context.addPath(path)
        context.strokePath()
    }

    /// The path filled with the gradient at its opacity, the end colors carried on past the gradient's ends.
    private static func fill(_ path: CGPath, with gradient: DiagramLinearGradient, colors: inout DiagramPaintColors, in context: CGContext) {
        let ends = [colors.color(of: gradient.startPaint), colors.color(of: gradient.endPaint)]
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let coreGraphicsGradient = CGGradient(colorsSpace: space, colors: ends as CFArray, locations: [0, 1]) else { return }
        context.saveGState()
        context.addPath(path)
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
