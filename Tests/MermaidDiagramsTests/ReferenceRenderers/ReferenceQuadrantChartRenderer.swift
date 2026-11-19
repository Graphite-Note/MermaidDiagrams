/**
 * File: ReferenceQuadrantChartRenderer.swift
 * ------------------------------------------
 * Layer: Tests
 * Description: QuadrantChartRenderer's Core Graphics painting as it was before the scene, the reference
 *              DiagramSceneParityTests compares the scene's pixels with.
 *
 * Authors: Félix Chevalier
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// The QuadrantChartRenderer as it painted before every type was painted from its scene, kept as the reference the scene's
/// pixels are compared with (`DiagramSceneParityTests`).
enum ReferenceQuadrantChartRenderer {
    static func draw(_ layout: QuadrantChartLayout, in context: CGContext, palette: DiagramPalette) {
        let parts = QuadrantChartDrawingParts(layout: layout)
        var text = DiagramTextDrawing(font: layout.font)
        context.saveGState()
        context.setFillColor(palette.surface)
        context.addPath(parts.quadrants)
        context.fillPath()
        context.setStrokeColor(palette.border)
        context.setLineWidth(QuadrantChartDrawingParts.lineWidth)
        context.addPath(parts.quadrants)
        context.strokePath()
        for quadrantText in parts.quadrantTexts { text.draw(quadrantText, color: palette.foreground, in: context) }
        for axisText in parts.axisTexts { text.draw(axisText, color: palette.muted, in: context) }
        for turnedText in parts.turnedAxisTexts {
            context.saveGState()
            context.translateBy(x: turnedText.center.x, y: turnedText.center.y)
            context.rotate(by: -.pi / 2)
            var atOrigin = turnedText
            atOrigin.center = .zero
            text.draw(atOrigin, color: palette.muted, in: context)
            context.restoreGState()
        }
        for group in parts.pointGroups { paint(group, palette: palette, in: context) }
        for pointText in parts.pointTexts { text.draw(pointText, color: palette.foreground, in: context) }
        if let title = parts.title { text.draw(title, color: palette.foreground, isBold: true, in: context) }
        context.restoreGState()
    }

    /// The color a point's paint stands for in `palette`.
    static func color(_ paint: QuadrantChartPaint, in palette: DiagramPalette) -> CGColor {
        switch paint {
        case .firstSeries: palette.seriesColor(at: 0)
        case .written(let color):
            CGColor(srgbRed: CGFloat(color.red) / 255, green: CGFloat(color.green) / 255, blue: CGFloat(color.blue) / 255, alpha: 1)
        }
    }

    private static func paint(_ group: QuadrantChartDrawingParts.PointGroup, palette: DiagramPalette, in context: CGContext) {
        context.setFillColor(color(group.fill, in: palette))
        context.addPath(group.circles)
        context.fillPath()
        guard let stroke = group.stroke else { return }
        context.setStrokeColor(color(stroke.paint, in: palette))
        context.setLineWidth(stroke.width)
        context.addPath(group.circles)
        context.strokePath()
    }
}
