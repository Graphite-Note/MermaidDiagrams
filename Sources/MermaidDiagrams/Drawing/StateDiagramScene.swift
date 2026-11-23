/**
 * File: StateDiagramScene.swift
 * -----------------------------
 * Layer: Core
 * Description: A laid-out state diagram's scene: its drawing parts back to front in the colors' roles, as Pele paints
 *              them.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import CoreGraphics

extension DiagramScene {
    /// The state diagram's painting: the composite states' boxes with the lines under their names and the dashed lines between their regions, the
    /// transitions, the dashed lines to the notes and the arrows, the names of boxes transitions cross, the patches behind
    /// transition text and that text, the states and their text, the notes and their text, the title.
    public init(layout: StateDiagramLayout) {
        var builder = DiagramSceneBuilder()
        StateDiagramDrawingParts(layout: layout).addScene(to: &builder)
        self = builder.scene(size: layout.size, font: layout.font)
    }
}

extension StateDiagramDrawingParts {
    /// A note's text: between the background and the text (`DiagramPalette.noteText`).
    static let noteTextPaint = DiagramPaint.betweenBackgroundAndForeground(share: DiagramPalette.noteTextShare)

    /// Every line is drawn with round caps and joins.
    func addScene(to builder: inout DiagramSceneBuilder) {
        let line = DiagramStroke.rounded(lineWidth: Self.lineWidth)
        let dashed = DiagramStroke.rounded(lineWidth: Self.lineWidth, dashLengths: Self.noteConnectorDashLengths)
        composites.addBoxes(to: &builder)
        builder.stroke(compositeTitleRules, .border, line, part: .cluster)
        builder.stroke(regionDividers, .border, dashed, part: .cluster)
        builder.stroke(transitionLines, .line, line, part: .edge)
        builder.stroke(noteConnectors, .border, dashed, part: .edge)
        builder.fill(arrows, .line, part: .marker)
        composites.addCrossedTitles(to: &builder)
        builder.fill(transitionTextPatches, .background, part: .labelBackground)
        builder.texts(transitionTexts, .foreground, part: .edgeLabel)
        builder.fill(stateFills, .surface, part: .node)
        builder.stroke(stateOutlines, .border, line, part: .node)
        builder.fillAndStroke(endRings, fill: .background, stroke: .line, line, part: .node)
        builder.fill(solidMarks, .line, part: .node)
        builder.texts(stateTexts, .foreground, part: .label)
        builder.fillAndStroke(noteSheets, fill: .background, stroke: .border, line, part: .note)
        builder.stroke(noteFolds, .border, line, part: .note)
        builder.texts(noteTexts, Self.noteTextPaint, part: .note)
        builder.title(title)
    }
}
