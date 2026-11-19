/**
 * File: ReferenceSankeyRenderer.swift
 * -----------------------------------
 * Layer: Tests
 * Description: SankeyRenderer's Core Graphics painting as it was before the scene, the reference
 *              DiagramSceneParityTests compares the scene's pixels with.
 *
 * Authors: Félix Chevalier
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// The SankeyRenderer as it painted before every type was painted from its scene, kept as the reference the scene's
/// pixels are compared with (`DiagramSceneParityTests`).
enum ReferenceSankeyRenderer {
    static func draw(_ layout: SankeyLayout, in context: CGContext, palette: DiagramPalette) {
        let parts = SankeyDrawingParts(layout: layout)
        var text = DiagramTextDrawing(font: layout.font)
        for band in parts.bands {
            let source = band.sourceColor?.cgColor ?? palette.seriesColor(at: band.sourceSeriesIndex)
            let target = band.targetColor?.cgColor ?? palette.seriesColor(at: band.targetSeriesIndex)
            switch parts.linkColor {
            case .gradient: fill(band, from: source, to: target, in: context)
            case .source: fill(band, solid: source, in: context)
            case .target: fill(band, solid: target, in: context)
            case .fixed(let color): fill(band, solid: color.cgColor, in: context)
            }
        }
        for (index, nodeFill) in parts.nodeFills.enumerated() where !nodeFill.isEmpty {
            context.setFillColor(palette.seriesColor(at: index))
            context.addPath(nodeFill)
            context.fillPath()
        }
        for colored in parts.coloredNodeFills {
            context.setFillColor(colored.color.cgColor)
            context.addPath(colored.path)
            context.fillPath()
        }
        let outline = parts.hasOutlinedLabels ? (color: palette.background, lineWidth: SankeyDrawingParts.labelOutlineWidth) : nil
        for name in parts.names { text.draw(name, color: palette.foreground, outline: outline, in: context) }
        for value in parts.values { text.draw(value, color: palette.muted, outline: outline, in: context) }
        if let title = parts.title { text.draw(title, color: palette.foreground, isBold: true, in: context) }
    }

    /// The band filled in one color at `SankeyDrawingParts.bandOpacity`.
    private static func fill(_ band: SankeyBandDrawing, solid color: CGColor, in context: CGContext) {
        context.setFillColor(color.copy(alpha: color.alpha * SankeyDrawingParts.bandOpacity) ?? color)
        context.addPath(band.outline)
        context.fillPath()
    }

    /// The band filled with its gradient at `SankeyDrawingParts.bandOpacity`, the colors carried on past its ends.
    private static func fill(_ band: SankeyBandDrawing, from sourceColor: CGColor, to targetColor: CGColor, in context: CGContext) {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let gradient = CGGradient(colorsSpace: space, colors: [sourceColor, targetColor] as CFArray, locations: [0, 1]) else { return }
        context.saveGState()
        context.addPath(band.outline)
        context.clip()
        context.setAlpha(SankeyDrawingParts.bandOpacity)
        context.drawLinearGradient(gradient, start: CGPoint(x: band.startX, y: 0), end: CGPoint(x: band.endX, y: 0),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        context.restoreGState()
    }
}
