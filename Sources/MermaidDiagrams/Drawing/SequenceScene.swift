/**
 * File: SequenceScene.swift
 * -------------------------
 * Layer: Core
 * Description: A laid-out sequence diagram's scene: its drawing parts back to front in the colors' roles, as Pele paints
 *              them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

extension DiagramScene {
    /// The sequence diagram's painting: the highlights, the lifelines, the activations, the block frames, the messages
    /// and their numbers, the messages' texts, the notes, the participants, the title. Pele's muted text and second
    /// surface are mixtures of the background and the foreground (`SequenceDrawingParts.mutedShare`,
    /// `surfaceAlternateShare`).
    public init(layout: SequenceLayout) {
        var builder = DiagramSceneBuilder()
        SequenceDrawingParts(layout: layout).addScene(to: &builder)
        self = builder.scene(size: layout.size, font: layout.font)
    }
}

extension SequenceDrawingParts {
    static let mutedPaint = DiagramPaint.betweenBackgroundAndForeground(share: mutedShare)
    static let surfaceAlternatePaint = DiagramPaint.betweenBackgroundAndForeground(share: surfaceAlternateShare)

    /// Every line is drawn one point wide with round caps and joins.
    func addScene(to builder: inout DiagramSceneBuilder) {
        let line = DiagramStroke.rounded(lineWidth: Self.lineWidth)
        let dashed = DiagramStroke.rounded(lineWidth: Self.lineWidth, dashLengths: Self.dashLengths)
        for highlight in highlights {
            let paint = highlight.color.map { color in DiagramPaint.color(DiagramColor(red: color.red, green: color.green, blue: color.blue,
                                                                                       alpha: color.alpha)) }
                ?? Self.surfaceAlternatePaint.atOpacity(Self.defaultHighlightOpacity)
            builder.fill(highlight.path, paint, part: .cluster)
        }
        builder.stroke(lifelines, .border, line, part: .axis)
        for activation in activations { builder.fillAndStroke(activation, fill: .surface, stroke: .border, line, part: .node) }
        builder.stroke(blockOutlines, .border, line, part: .cluster)
        builder.stroke(blockSectionLines, .border, dashed, part: .cluster)
        builder.fill(blockTextPatches, .background, part: .labelBackground)
        builder.texts(blockTexts, Self.mutedPaint, part: .clusterLabel)
        builder.fillAndStroke(blockTabs, fill: .surface, stroke: .border, line, part: .cluster)
        builder.texts(blockKeywords, Self.mutedPaint, isBold: true, part: .clusterLabel)
        builder.stroke(solidMessageLines, .line, line, part: .edge)
        builder.stroke(dottedMessageLines, .line, dashed, part: .edge)
        builder.fill(filledHeads, .line, part: .marker)
        builder.stroke(strokedHeads, .line, line, part: .marker)
        builder.fill(numberBadges, .line, part: .marker)
        builder.texts(numberTexts, .background, part: .marker)
        builder.fill(messageTextPatches, .background, part: .labelBackground)
        builder.texts(messageTexts, .foreground, part: .edgeLabel)
        builder.fillAndStroke(notes, fill: Self.surfaceAlternatePaint, stroke: .border, line, part: .note)
        builder.texts(noteTexts, .foreground, part: .note)
        builder.fillAndStroke(participantShapes, fill: .surface, stroke: .border, line, part: .node)
        builder.stroke(participantFigureLines, .border, line, part: .node)
        builder.texts(participantTexts, .foreground, part: .label)
        builder.title(title)
    }
}
