/**
 * File: ReferenceUserJourneyRenderer.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: UserJourneyRenderer's Core Graphics painting as it was before the scene, the reference
 *              DiagramSceneParityTests compares the scene's pixels with.
 *
 * Authors: Félix Chevalier
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// The UserJourneyRenderer as it painted before every type was painted from its scene, kept as the reference the scene's
/// pixels are compared with (`DiagramSceneParityTests`).
enum ReferenceUserJourneyRenderer {
    static func draw(_ layout: UserJourneyLayout, in context: CGContext, palette: DiagramPalette) {
        let parts = UserJourneyDrawingParts(layout: layout)
        var text = DiagramTextDrawing(font: layout.font)
        context.saveGState()
        context.setLineWidth(UserJourneyDrawingParts.lineWidth)
        stroke(parts.scaleLines, color: palette.alternateSurface, in: context)
        for scaleText in parts.scaleTexts { text.draw(scaleText, color: palette.muted, in: context) }
        context.saveGState()
        context.setLineDash(phase: 0, lengths: UserJourneyDrawingParts.stemDashLengths)
        stroke(parts.stems, color: palette.border, in: context)
        context.restoreGState()
        context.setLineJoin(.round)
        stroke(parts.scoreLine, color: palette.line, in: context)
        fill(parts.faces, color: palette.background, in: context)
        stroke(parts.faces, color: palette.line, in: context)
        fill(parts.eyes, color: palette.line, in: context)
        context.setLineCap(.round)
        stroke(parts.mouths, color: palette.line, in: context)
        context.setLineCap(.butt)
        fill(parts.sectionBands, color: palette.alternateSurface, in: context)
        for sectionText in parts.sectionTexts { text.draw(sectionText, color: palette.foreground, isBold: true, in: context) }
        fill(parts.cards, color: palette.surface, in: context)
        stroke(parts.cards, color: palette.border, in: context)
        for taskText in parts.taskTexts { text.draw(taskText, color: palette.foreground, in: context) }
        for (index, dots) in parts.cardDotsBySeries.enumerated() {
            fill(dots, color: palette.seriesColor(at: index), in: context)
            stroke(dots, color: palette.surface, in: context)
        }
        for (index, dots) in parts.legendDotsBySeries.enumerated() { fill(dots, color: palette.seriesColor(at: index), in: context) }
        for legendText in parts.legendTexts { text.draw(legendText, color: palette.foreground, in: context) }
        if let title = parts.title { text.draw(title, color: palette.foreground, isBold: true, in: context) }
        context.restoreGState()
    }

    private static func stroke(_ path: CGPath, color: CGColor, in context: CGContext) {
        guard !path.isEmpty else { return }
        context.setStrokeColor(color)
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
