/**
 * File: ReferenceSequenceRenderer.swift
 * -------------------------------------
 * Layer: Tests
 * Description: SequenceRenderer's Core Graphics painting as it was before the scene, the reference
 *              DiagramSceneParityTests compares the scene's pixels with, with the boxes, shapes, central connections and
 *              destructions painted the same way.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// The SequenceRenderer as it painted before every type was painted from its scene, kept as the reference the scene's
/// pixels are compared with (`DiagramSceneParityTests`).
enum ReferenceSequenceRenderer {
    static func draw(_ layout: SequenceLayout, in context: CGContext, palette: DiagramPalette) {
        let parts = SequenceDrawingParts(layout: layout)
        let muted = mixed(palette.background, palette.foreground, share: SequenceDrawingParts.mutedShare)
        let surfaceAlternate = mixed(palette.background, palette.foreground, share: SequenceDrawingParts.surfaceAlternateShare)
        var text = DiagramTextDrawing(font: layout.font)
        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        drawBoxes(parts, muted: muted, surfaceAlternate: surfaceAlternate, palette: palette, text: &text, in: context)
        for highlight in parts.highlights {
            let color = highlight.color.map { color in CGColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha) }
                ?? surfaceAlternate.copy(alpha: SequenceDrawingParts.defaultHighlightOpacity) ?? surfaceAlternate
            fill(highlight.path, color: color, in: context)
        }
        stroke(parts.lifelines, color: palette.border, in: context)
        for activation in parts.activations {
            fill(activation, color: palette.surface, in: context)
            stroke(activation, color: palette.border, in: context)
        }
        drawBlocks(parts, palette: palette, muted: muted, text: &text, in: context)
        stroke(parts.solidMessageLines, color: palette.line, in: context)
        context.setLineDash(phase: 0, lengths: SequenceDrawingParts.dashLengths)
        stroke(parts.dottedMessageLines, color: palette.line, in: context)
        context.setLineDash(phase: 0, lengths: [])
        fill(parts.filledHeads, color: palette.line, in: context)
        stroke(parts.strokedHeads, color: palette.line, in: context)
        fill(parts.centralConnections, color: palette.line, in: context)
        for group in parts.inkedMessageLines {
            let ink = group.ink.map(cgColor) ?? palette.line
            stroke(group.solidLines, color: ink, in: context)
            context.setLineDash(phase: 0, lengths: SequenceDrawingParts.dashLengths)
            stroke(group.dottedLines, color: ink, in: context)
            context.setLineDash(phase: 0, lengths: [])
            fill(group.filledHeads, color: ink, in: context)
            stroke(group.strokedHeads, color: ink, in: context)
            fill(group.centralConnections, color: ink, in: context)
        }
        fill(parts.numberBadges, color: palette.line, in: context)
        for number in parts.numberTexts { text.draw(number, color: palette.background, in: context) }
        stroke(parts.destructions, color: palette.line, lineWidth: SequenceDrawingParts.destructionLineWidth, in: context)
        fill(parts.messageTextPatches, color: palette.background, in: context)
        for (messageText, ink) in zip(parts.messageTexts, parts.messageTextInks) {
            text.draw(messageText, color: ink.map(cgColor) ?? palette.foreground, in: context)
        }
        fill(parts.notes, color: surfaceAlternate, in: context)
        stroke(parts.notes, color: palette.border, in: context)
        for noteText in parts.noteTexts { text.draw(noteText, color: palette.foreground, in: context) }
        fill(parts.participantShapes, color: palette.surface, in: context)
        stroke(parts.participantShapes, color: palette.border, in: context)
        stroke(parts.participantFigureLines, color: palette.border, in: context)
        fill(parts.participantFrontShapes, color: palette.surface, in: context)
        stroke(parts.participantFrontShapes, color: palette.border, in: context)
        for (participantText, ink) in zip(parts.participantTexts, parts.participantTextInks) {
            text.draw(participantText, color: ink.map(cgColor) ?? palette.foreground, in: context)
        }
        if let title = parts.title { text.draw(title, color: palette.foreground, isBold: true, in: context) }
        context.restoreGState()
    }

    /// The frames, their dashed section lines, the texts in them on their patches, and the tabs with their keywords.
    private static func drawBlocks(_ parts: SequenceDrawingParts, palette: DiagramPalette, muted: CGColor, text: inout DiagramTextDrawing,
                                   in context: CGContext) {
        stroke(parts.blockOutlines, color: palette.border, in: context)
        context.setLineDash(phase: 0, lengths: SequenceDrawingParts.dashLengths)
        stroke(parts.blockSectionLines, color: palette.border, in: context)
        context.setLineDash(phase: 0, lengths: [])
        fill(parts.blockTextPatches, color: palette.background, in: context)
        for (blockText, ink) in zip(parts.blockTexts, parts.blockTextInks) { text.draw(blockText, color: ink.map(cgColor) ?? muted, in: context) }
        fill(parts.blockTabs, color: palette.surface, in: context)
        stroke(parts.blockTabs, color: palette.border, in: context)
        for keyword in parts.blockKeywords { text.draw(keyword, color: muted, isBold: true, in: context) }
    }

    /// Each box filled with its color or the second surface at half opacity and outlined, its title on it.
    private static func drawBoxes(_ parts: SequenceDrawingParts, muted: CGColor, surfaceAlternate: CGColor, palette: DiagramPalette,
                                  text: inout DiagramTextDrawing, in context: CGContext) {
        for box in parts.boxes {
            let color = box.color.map { color in CGColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha) }
                ?? surfaceAlternate.copy(alpha: SequenceDrawingParts.defaultHighlightOpacity) ?? surfaceAlternate
            fill(box.path, color: color, in: context)
            stroke(box.path, color: palette.border, in: context)
            if let title = box.title { text.draw(title, color: box.titleInk.map(cgColor) ?? muted, in: context) }
        }
    }

    private static func cgColor(_ color: DiagramColor) -> CGColor {
        CGColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }

    /// The color `share` of the way from `start` to `end`, in sRGB.
    static func mixed(_ start: CGColor, _ end: CGColor, share: CGFloat) -> CGColor {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let startComponents = start.converted(to: space, intent: .defaultIntent, options: nil)?.components,
              let endComponents = end.converted(to: space, intent: .defaultIntent, options: nil)?.components,
              startComponents.count == 4, endComponents.count == 4 else { return end }
        let components = zip(startComponents, endComponents).map { from, to in from + (to - from) * share }
        return CGColor(srgbRed: components[0], green: components[1], blue: components[2], alpha: components[3])
    }

    private static func stroke(_ path: CGPath, color: CGColor, lineWidth: CGFloat = SequenceDrawingParts.lineWidth, in context: CGContext) {
        guard !path.isEmpty else { return }
        context.setStrokeColor(color)
        context.setLineWidth(lineWidth)
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
