/**
 * File: ReferenceGraphTypeScenes.swift
 * ------------------------------------
 * Layer: Tests
 * Description: 0.7.0's state diagram scene, frozen as main 2a0cc65 made it from Core Graphics paths (the public drawing
 *              parts and the builder's Core Graphics paths), which the scene recorded into lanes is compared with.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// 0.7.0's state diagram scene, made from the public drawing parts' Core Graphics paths.
enum ReferenceStateDiagramScene {
    static func scene(layout: StateDiagramLayout) -> DiagramScene {
        var builder = DiagramSceneBuilder()
        let parts = StateDiagramDrawingParts(layout: layout)
        let line = DiagramStroke.rounded(lineWidth: StateDiagramDrawingParts.lineWidth)
        let dashed = DiagramStroke.rounded(lineWidth: StateDiagramDrawingParts.lineWidth, dashLengths: StateDiagramDrawingParts.noteConnectorDashLengths)
        parts.composites.addBoxes(to: &builder)
        builder.stroke(parts.compositeTitleRules, .border, line, part: .cluster)
        builder.stroke(parts.regionDividers, .border, dashed, part: .cluster)
        builder.stroke(parts.transitionLines, .line, line, part: .edge)
        builder.stroke(parts.noteConnectors, .border, dashed, part: .edge)
        builder.fill(parts.arrows, .line, part: .marker)
        parts.composites.addCrossedTitles(to: &builder)
        builder.fill(parts.transitionTextPatches, .background, part: .labelBackground)
        builder.texts(parts.transitionTexts, .foreground, part: .edgeLabel)
        builder.fill(parts.stateFills, .surface, part: .node)
        builder.stroke(parts.stateOutlines, .border, line, part: .node)
        builder.fillAndStroke(parts.endRings, fill: .background, stroke: .line, line, part: .node)
        builder.fill(parts.solidMarks, .line, part: .node)
        builder.texts(parts.stateTexts, .foreground, part: .label)
        builder.fillAndStroke(parts.noteSheets, fill: .background, stroke: .border, line, part: .note)
        builder.stroke(parts.noteFolds, .border, line, part: .note)
        builder.texts(parts.noteTexts, DiagramPaint.betweenBackgroundAndForeground(share: DiagramPalette.noteTextShare), part: .note)
        builder.title(parts.title)
        return builder.scene(size: layout.size, font: layout.font)
    }
}
