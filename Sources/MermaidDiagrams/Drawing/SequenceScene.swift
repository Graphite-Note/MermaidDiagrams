/**
 * File: SequenceScene.swift
 * -------------------------
 * Layer: Core
 * Description: A laid-out sequence diagram's scene: its drawing parts back to front in the colors' roles, as Pele paints
 *              them.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 24/11/2026
 */

import CoreGraphics

extension DiagramScene {
    /// The sequence diagram's painting: the boxes, the highlights, the lifelines, the activations, the block frames, the messages
    /// and their numbers, the messages' texts, the notes, the participants, the title. Pele's muted text and second
    /// surface are mixtures of the background and the foreground (`SequenceDrawingParts.mutedShare`,
    /// `surfaceAlternateShare`). The paths are recorded into lanes of the thread's scene workspace.
    public init(layout: SequenceLayout) {
        self = DiagramSceneWorkspace.withRecording { workspace in
            var builder = DiagramSceneBuilder(workspace: workspace)
            SequenceSceneRecording(layout: layout, paths: SequenceDrawingPaths(layout: layout, making: workspace)).add(to: &builder)
            return builder.scene(size: layout.size, font: layout.font)
        }
    }
}

extension SequenceDrawingParts {
    static let mutedPaint = DiagramPaint.betweenBackgroundAndForeground(share: mutedShare)
    static let surfaceAlternatePaint = DiagramPaint.betweenBackgroundAndForeground(share: surfaceAlternateShare)
}

/// Adds a sequence diagram's painting to a scene from its layout and its paths, recorded into lanes.
struct SequenceSceneRecording {
    let layout: SequenceLayout
    let paths: SequenceDrawingPaths<DiagramPathLane>

    private typealias Parts = SequenceDrawingParts

    /// Every line is drawn one point wide with round caps and joins, the crosses of destroyed lifelines 1.5 wide.
    func add(to builder: inout DiagramSceneBuilder) {
        addBackgrounds(to: &builder)
        addBlocks(to: &builder)
        addMessages(to: &builder)
        builder.fillAndStroke(paths.notes, fill: Parts.surfaceAlternatePaint, stroke: .border, Self.line, part: .note)
        for note in layout.notes { builder.text(note.text, .foreground, part: .note) }
        builder.fillAndStroke(paths.participants.shapes, fill: .surface, stroke: .border, Self.line, part: .node)
        builder.stroke(paths.participants.lines, .border, Self.line, part: .node)
        builder.fillAndStroke(paths.participants.frontShapes, fill: .surface, stroke: .border, Self.line, part: .node)
        for participant in layout.participants {
            builder.text(participant.text, Self.paint(Parts.participantTextInk(participant), else: .foreground), part: .label)
        }
        builder.title(layout.title)
    }

    private static let line = DiagramStroke.rounded(lineWidth: Parts.lineWidth)
    private static let dashed = DiagramStroke.rounded(lineWidth: Parts.lineWidth, dashLengths: Parts.dashLengths)

    /// The boxes with their titles, the highlights, the lifelines and the activations.
    private func addBackgrounds(to builder: inout DiagramSceneBuilder) {
        for (box, path) in zip(layout.boxes, paths.boxes) {
            let fill = box.color.map { color in Self.paint(color) } ?? Parts.surfaceAlternatePaint.atOpacity(Parts.defaultHighlightOpacity)
            builder.fillAndStroke(path, fill: fill, stroke: .border, Self.line, part: .cluster)
            builder.text(box.title, Self.paint(SequenceTextInk.ink(on: box.color), else: Parts.mutedPaint), part: .clusterLabel)
        }
        for (highlight, path) in zip(layout.highlights, paths.highlights) {
            let paint = highlight.color.map { color in Self.paint(color) } ?? Parts.surfaceAlternatePaint.atOpacity(Parts.defaultHighlightOpacity)
            builder.fill(path, paint, part: .cluster)
        }
        builder.stroke(paths.lifelines, .border, Self.line, part: .axis)
        for activation in paths.activations { builder.fillAndStroke(activation, fill: .surface, stroke: .border, Self.line, part: .node) }
    }

    /// The block frames, their section lines, their texts on their patches, and their tabs with their keywords.
    private func addBlocks(to builder: inout DiagramSceneBuilder) {
        builder.stroke(paths.blockOutlines, .border, Self.line, part: .cluster)
        builder.stroke(paths.blockSectionLines, .border, Self.dashed, part: .cluster)
        builder.fill(paths.blockTextPatches, .background, part: .labelBackground)
        SequenceDrawingPaths<DiagramPathLane>.forEachBlockText(of: layout.blocks) { text, ink in
            builder.text(text, Self.paint(ink, else: Parts.mutedPaint), part: .clusterLabel)
        }
        builder.fillAndStroke(paths.blockTabs, fill: .surface, stroke: .border, Self.line, part: .cluster)
        for block in layout.blocks { builder.text(block.keyword, Parts.mutedPaint, isBold: true, part: .clusterLabel) }
    }

    /// The messages' lines, heads and circles in the line color, then those over colored backgrounds in their colors,
    /// the numbers, the crosses of destroyed lifelines, and the messages' texts on their patches.
    private func addMessages(to builder: inout DiagramSceneBuilder) {
        let messages = paths.messages
        Self.addLines(messages.lines, paint: .line, to: &builder)
        for group in messages.inkedLines { Self.addLines(group, paint: Self.paint(group.ink, else: .line), to: &builder) }
        builder.fill(messages.numberBadges, .line, part: .marker)
        for message in layout.messages { builder.text(message.number?.text, .background, part: .marker) }
        builder.stroke(paths.destructions, .line, DiagramStroke.rounded(lineWidth: Parts.destructionLineWidth), part: .marker)
        builder.fill(messages.textPatches, .background, part: .labelBackground)
        for message in layout.messages {
            guard let text = message.text else { continue }
            builder.text(text, Self.paint(SequenceTextInk.ink(on: message.textBackground), else: .foreground), part: .edgeLabel)
        }
    }

    /// Messages' lines, heads and central connections' circles, in one paint.
    private static func addLines(_ lines: SequenceMessageLinePaths<DiagramPathLane>, paint: DiagramPaint, to builder: inout DiagramSceneBuilder) {
        builder.stroke(lines.solidLines, paint, line, part: .edge)
        builder.stroke(lines.dottedLines, paint, dashed, part: .edge)
        builder.fill(lines.filledHeads, paint, part: .marker)
        builder.stroke(lines.strokedHeads, paint, line, part: .marker)
        builder.fill(lines.centralConnections, paint, part: .marker)
    }

    /// A text color Pele picks on a colored background, or `otherwise` when it picks none.
    private static func paint(_ ink: DiagramColor?, else otherwise: DiagramPaint) -> DiagramPaint {
        ink.map { color in DiagramPaint.color(color) } ?? otherwise
    }

    /// A color the diagram's text names, as a paint.
    private static func paint(_ color: SequenceHighlightColor) -> DiagramPaint {
        DiagramPaint.color(DiagramColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha))
    }
}
