/**
 * File: ReferenceXYChartRenderer.swift
 * ------------------------------------
 * Layer: Tests
 * Description: XYChartRenderer's Core Graphics painting as it was before the scene, the reference
 *              DiagramSceneParityTests compares the scene's pixels with.
 *
 * Authors: Félix Chevalier
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// The XYChartRenderer as it painted before every type was painted from its scene, kept as the reference the scene's
/// pixels are compared with (`DiagramSceneParityTests`).
enum ReferenceXYChartRenderer {
    static func draw(_ layout: XYChartLayout, in context: CGContext, palette: DiagramPalette) {
        let parts = XYChartDrawingParts(layout: layout)
        var text = DiagramTextDrawing(font: layout.font)
        context.saveGState()
        stroke(parts.gridLines, color: palette.alternateSurface, width: XYChartDrawingParts.lineWidth, in: context)
        for (index, barFill) in parts.barFills.enumerated() { fill(barFill, color: palette.seriesColor(at: index), in: context) }
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for line in parts.lines {
            let color = palette.seriesColor(at: line.seriesIndex)
            stroke(line.stroke, color: color, width: XYChartDrawingParts.seriesLineWidth, in: context)
            fill(line.dots, color: color, in: context)
        }
        context.setLineCap(.butt)
        stroke(parts.axisLines, color: palette.border, width: XYChartDrawingParts.lineWidth, in: context)
        for label in parts.axisLabels { text.draw(label, color: palette.muted, in: context) }
        for block in parts.texts { text.draw(block, color: palette.foreground, in: context) }
        if let turned = parts.turnedText { drawTurned(turned, color: palette.foreground, text: &text, in: context) }
        if let title = parts.title { text.draw(title, color: palette.foreground, isBold: true, in: context) }
        context.restoreGState()
    }

    /// `block` turned a quarter turn counterclockwise about its center, so that it reads from the bottom up.
    private static func drawTurned(_ block: DiagramTextBlock, color: CGColor, text: inout DiagramTextDrawing, in context: CGContext) {
        context.saveGState()
        context.translateBy(x: block.center.x, y: block.center.y)
        context.rotate(by: -.pi / 2)
        var centered = block
        centered.center = .zero
        text.draw(centered, color: color, in: context)
        context.restoreGState()
    }

    private static func stroke(_ path: CGPath, color: CGColor, width: CGFloat, in context: CGContext) {
        guard !path.isEmpty else { return }
        context.setStrokeColor(color)
        context.setLineWidth(width)
        context.addPath(path)
        context.strokePath()
    }

    private static func fill(_ path: CGPath, color: CGColor, in context: CGContext) {
        guard !path.isEmpty else { return }
        context.setFillColor(color)
        context.addPath(path)
        context.fillPath()
    }
}
