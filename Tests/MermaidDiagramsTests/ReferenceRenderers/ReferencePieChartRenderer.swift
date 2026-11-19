/**
 * File: ReferencePieChartRenderer.swift
 * -------------------------------------
 * Layer: Tests
 * Description: PieChartRenderer's Core Graphics painting as it was before the scene, the reference
 *              DiagramSceneParityTests compares the scene's pixels with.
 *
 * Authors: Félix Chevalier
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// The PieChartRenderer as it painted before every type was painted from its scene, kept as the reference the scene's
/// pixels are compared with (`DiagramSceneParityTests`).
enum ReferencePieChartRenderer {
    static func draw(_ layout: PieChartLayout, in context: CGContext, palette: DiagramPalette) {
        let parts = PieChartDrawingParts(layout: layout)
        var text = DiagramTextDrawing(font: layout.font)
        context.saveGState()
        context.setLineJoin(.round)
        for (index, seriesFill) in parts.seriesFills.enumerated() { fill(seriesFill, color: palette.seriesColor(at: index), in: context) }
        stroke(parts.sliceEdges, color: palette.background, in: context)
        stroke(parts.emptyPieOutline, color: palette.border, in: context)
        for percentage in parts.insidePercentages { text.draw(percentage, color: palette.background, in: context) }
        for block in parts.outsidePercentages + parts.legendTexts { text.draw(block, color: palette.foreground, in: context) }
        if let title = parts.title { text.draw(title, color: palette.foreground, isBold: true, in: context) }
        context.restoreGState()
    }

    private static func stroke(_ path: CGPath, color: CGColor, in context: CGContext) {
        guard !path.isEmpty else { return }
        context.setStrokeColor(color)
        context.setLineWidth(PieChartDrawingParts.lineWidth)
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
