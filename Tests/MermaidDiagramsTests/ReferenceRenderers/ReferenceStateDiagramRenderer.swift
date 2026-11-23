/**
 * File: ReferenceStateDiagramRenderer.swift
 * -----------------------------------------
 * Layer: Tests
 * Description: StateDiagramRenderer's Core Graphics painting as it was before the scene, the reference
 *              DiagramSceneParityTests compares the scene's pixels with.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// The StateDiagramRenderer as it painted before every type was painted from its scene, kept as the reference the scene's
/// pixels are compared with (`DiagramSceneParityTests`).
enum ReferenceStateDiagramRenderer {
    static func draw(_ layout: StateDiagramLayout, in context: CGContext, palette: DiagramPalette) {
        let parts = StateDiagramDrawingParts(layout: layout)
        var text = DiagramTextDrawing(font: layout.font)
        let lineWidth = StateDiagramDrawingParts.lineWidth
        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        ReferenceFlowchartRenderer.drawClusters(parts.composites, text: &text, in: context, palette: palette)
        stroke(parts.compositeTitleRules, width: lineWidth, color: palette.border, in: context)
        context.setLineDash(phase: 0, lengths: StateDiagramDrawingParts.noteConnectorDashLengths)
        stroke(parts.regionDividers, width: lineWidth, color: palette.border, in: context)
        context.setLineDash(phase: 0, lengths: [])
        stroke(parts.transitionLines, width: lineWidth, color: palette.line, in: context)
        context.setLineDash(phase: 0, lengths: StateDiagramDrawingParts.noteConnectorDashLengths)
        stroke(parts.noteConnectors, width: lineWidth, color: palette.border, in: context)
        context.setLineDash(phase: 0, lengths: [])
        fill(parts.arrows, color: palette.line, in: context)
        ReferenceFlowchartRenderer.drawCrossedClusterTitles(parts.composites, text: &text, in: context, palette: palette)
        fill(parts.transitionTextPatches, color: palette.background, in: context)
        for transitionText in parts.transitionTexts { text.draw(transitionText, color: palette.foreground, in: context) }
        fill(parts.stateFills, color: palette.surface, in: context)
        stroke(parts.stateOutlines, width: lineWidth, color: palette.border, in: context)
        fill(parts.endRings, color: palette.background, in: context)
        stroke(parts.endRings, width: lineWidth, color: palette.line, in: context)
        fill(parts.solidMarks, color: palette.line, in: context)
        for stateText in parts.stateTexts { text.draw(stateText, color: palette.foreground, in: context) }
        fill(parts.noteSheets, color: palette.background, in: context)
        stroke(parts.noteSheets, width: lineWidth, color: palette.border, in: context)
        stroke(parts.noteFolds, width: lineWidth, color: palette.border, in: context)
        for noteText in parts.noteTexts { text.draw(noteText, color: palette.noteText, in: context) }
        if let title = parts.title { text.draw(title, color: palette.foreground, isBold: true, in: context) }
        context.restoreGState()
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

