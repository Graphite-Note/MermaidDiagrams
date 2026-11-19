/**
 * File: ReferenceGanttRenderer.swift
 * ----------------------------------
 * Layer: Tests
 * Description: GanttRenderer's Core Graphics painting as it was before the scene, the reference
 *              DiagramSceneParityTests compares the scene's pixels with.
 *
 * Authors: Félix Chevalier
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// The GanttRenderer as it painted before every type was painted from its scene, kept as the reference the scene's
/// pixels are compared with (`DiagramSceneParityTests`).
enum ReferenceGanttRenderer {
    static func draw(_ layout: GanttLayout, in context: CGContext, palette: DiagramPalette) {
        let parts = GanttDrawingParts(layout: layout)
        var text = DiagramTextDrawing(font: layout.font)
        context.saveGState()
        context.setLineJoin(.round)
        fill(parts.sectionBands, color: palette.surface, in: context)
        fill(parts.excludedDays, color: palette.alternateSurface, in: context)
        context.setLineDash(phase: 0, lengths: GanttDrawingParts.gridDashLengths)
        stroke(parts.gridLines, width: GanttDrawingParts.lineWidth, color: palette.border, in: context)
        context.setLineDash(phase: 0, lengths: [])
        stroke(parts.axisLines, width: GanttDrawingParts.lineWidth, color: palette.border, in: context)
        stroke(parts.todayLine, width: GanttDrawingParts.todayLineWidth, color: palette.accent, in: context)
        fill(parts.todayMark, color: palette.accent, in: context)
        for (taskFill, path) in parts.taskFills { fill(path, color: color(of: taskFill, in: palette), in: context) }
        for (taskStroke, path) in parts.taskOutlines {
            stroke(path, width: GanttDrawingParts.lineWidth, color: color(of: taskStroke, in: palette), in: context)
        }
        for (labelColor, labels) in parts.taskTexts {
            for label in labels { text.draw(label, color: color(of: labelColor, in: palette), in: context) }
        }
        for name in parts.sectionNames { text.draw(name, color: palette.foreground, in: context) }
        for date in parts.axisDates { text.draw(date, color: palette.muted, in: context) }
        if let title = parts.title { text.draw(title, color: palette.foreground, isBold: true, in: context) }
        context.restoreGState()
    }

    static func color(of taskFill: GanttTaskFill, in palette: DiagramPalette) -> CGColor {
        switch taskFill {
        case .accent: palette.accent
        case .faintAccent: palette.accent.copy(alpha: GanttDrawingParts.faintFillOpacity) ?? palette.accent
        case .critical: palette.critical
        case .faintCritical: palette.critical.copy(alpha: GanttDrawingParts.faintFillOpacity) ?? palette.critical
        case .alternateSurface: palette.alternateSurface
        }
    }

    static func color(of taskStroke: GanttTaskStroke, in palette: DiagramPalette) -> CGColor {
        switch taskStroke {
        case .accent: palette.accent
        case .critical: palette.critical
        case .border: palette.border
        }
    }

    static func color(of labelColor: GanttLabelColor, in palette: DiagramPalette) -> CGColor {
        switch labelColor {
        case .background: palette.background
        case .foreground: palette.foreground
        case .muted: palette.muted
        }
    }

    private static func stroke(_ path: CGPath, width: CGFloat, color: CGColor, in context: CGContext) {
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
