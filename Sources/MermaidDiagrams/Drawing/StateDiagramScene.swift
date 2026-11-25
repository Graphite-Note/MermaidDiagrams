/**
 * File: StateDiagramScene.swift
 * -----------------------------
 * Layer: Core
 * Description: A laid-out state diagram's scene: its drawing parts back to front in the colors' roles, as Pele paints
 *              them, its paths recorded into lanes of the scene's workspace.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 25/11/2026
 */

import CoreGraphics

extension DiagramScene {
    /// The state diagram's painting: the composite states' boxes with the lines under their names and the dashed lines between their regions, the
    /// transitions, the dashed lines to the notes and the arrows, the names of boxes transitions cross, the patches behind
    /// transition text and that text, the states and their text, the notes and their text, the title.
    public init(layout: StateDiagramLayout) {
        self.init(layout: layout, limits: .standard)
    }

    /// The same painting, each of its paths holding at most the elements `limits` allow
    /// (`DiagramSceneWorkspace.elementLimit(for:)`): past them the scene says so, and its preparation refuses it.
    public init(layout: StateDiagramLayout, limits: MermaidDiagramLimits) {
        self = DiagramSceneWorkspace.withRecording(limits: limits) { workspace in
            var builder = DiagramSceneBuilder(workspace: workspace)
            StateDiagramSceneRecording.add(layout, to: &builder, workspace: workspace)
            return builder.scene(size: layout.size, font: layout.font)
        }
    }
}

/// Adds a state diagram's painting to a scene, its paths recorded into lanes of `workspace`, grouped as
/// `StateDiagramDrawingParts` groups them.
enum StateDiagramSceneRecording {
    /// A note's text: between the background and the text (`DiagramPalette.noteText`).
    static let noteTextPaint = DiagramPaint.betweenBackgroundAndForeground(share: DiagramPalette.noteTextShare)

    /// Every line is drawn with round caps and joins.
    static func add(_ layout: StateDiagramLayout, to builder: inout DiagramSceneBuilder, workspace: DiagramSceneWorkspace) {
        let line = DiagramStroke.rounded(lineWidth: StateDiagramDrawingParts.lineWidth)
        let dashed = DiagramStroke.rounded(lineWidth: StateDiagramDrawingParts.lineWidth, dashLengths: StateDiagramDrawingParts.noteConnectorDashLengths)
        let composites = FlowchartClusterPaths(clusters: layout.composites, making: workspace)
        FlowchartSceneRecording.addBoxes(of: composites, to: &builder)
        let paths = StateDiagramPaths(layout: layout, making: workspace)
        builder.stroke(paths.compositeTitleRules, .border, line, part: .cluster)
        builder.stroke(paths.regionDividers, .border, dashed, part: .cluster)
        builder.stroke(paths.transitionLines, .line, line, part: .edge)
        builder.stroke(paths.noteConnectors, .border, dashed, part: .edge)
        builder.fill(paths.arrows, .line, part: .marker)
        FlowchartSceneRecording.addCrossedTitles(of: composites, to: &builder)
        builder.fill(paths.transitionTextPatches, .background, part: .labelBackground)
        for transition in layout.transitions { builder.text(transition.text, .foreground, part: .edgeLabel) }
        builder.fill(paths.stateFills, .surface, part: .node)
        builder.stroke(paths.stateOutlines, .border, line, part: .node)
        builder.fillAndStroke(paths.endRings, fill: .background, stroke: .line, line, part: .node)
        builder.fill(paths.solidMarks, .line, part: .node)
        for state in layout.states {
            builder.text(state.name, .foreground, part: .label)
            builder.text(state.details, .foreground, part: .label)
        }
        builder.fillAndStroke(paths.noteSheets, fill: .background, stroke: .border, line, part: .note)
        builder.stroke(paths.noteFolds, .border, line, part: .note)
        for note in layout.notes { builder.text(note.text, noteTextPaint, part: .note) }
        builder.title(layout.title)
    }
}
