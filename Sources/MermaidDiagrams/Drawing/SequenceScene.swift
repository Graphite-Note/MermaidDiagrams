/**
 * File: SequenceScene.swift
 * -------------------------
 * Layer: Core
 * Description: A laid-out sequence diagram's scene: its drawing parts back to front in the colors' roles, as Pele paints
 *              them.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

import CoreGraphics

extension DiagramScene {
    /// The sequence diagram's painting: the boxes, the highlights, the lifelines, the activations, the block frames, the messages
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

    /// Every line is drawn one point wide with round caps and joins, the crosses of destroyed lifelines 1.5 wide.
    func addScene(to builder: inout DiagramSceneBuilder) {
        addBackgrounds(to: &builder)
        addBlocks(to: &builder)
        addMessages(to: &builder)
        builder.fillAndStroke(notes, fill: Self.surfaceAlternatePaint, stroke: .border, Self.line, part: .note)
        builder.texts(noteTexts, .foreground, part: .note)
        builder.fillAndStroke(participantShapes, fill: .surface, stroke: .border, Self.line, part: .node)
        builder.stroke(participantFigureLines, .border, Self.line, part: .node)
        builder.fillAndStroke(participantFrontShapes, fill: .surface, stroke: .border, Self.line, part: .node)
        for (text, ink) in zip(participantTexts, participantTextInks) { builder.text(text, Self.paint(ink, else: .foreground), part: .label) }
        builder.title(title)
    }

    private static let line = DiagramStroke.rounded(lineWidth: lineWidth)
    private static let dashed = DiagramStroke.rounded(lineWidth: lineWidth, dashLengths: dashLengths)

    /// The boxes with their titles, the highlights, the lifelines and the activations.
    private func addBackgrounds(to builder: inout DiagramSceneBuilder) {
        for box in boxes {
            let fill = box.color.map { color in Self.paint(color) } ?? Self.surfaceAlternatePaint.atOpacity(Self.defaultHighlightOpacity)
            builder.fillAndStroke(box.path, fill: fill, stroke: .border, Self.line, part: .cluster)
            builder.text(box.title, Self.paint(box.titleInk, else: Self.mutedPaint), part: .clusterLabel)
        }
        for highlight in highlights {
            let paint = highlight.color.map { color in Self.paint(color) } ?? Self.surfaceAlternatePaint.atOpacity(Self.defaultHighlightOpacity)
            builder.fill(highlight.path, paint, part: .cluster)
        }
        builder.stroke(lifelines, .border, Self.line, part: .axis)
        for activation in activations { builder.fillAndStroke(activation, fill: .surface, stroke: .border, Self.line, part: .node) }
    }

    /// The block frames, their section lines, their texts on their patches, and their tabs with their keywords.
    private func addBlocks(to builder: inout DiagramSceneBuilder) {
        builder.stroke(blockOutlines, .border, Self.line, part: .cluster)
        builder.stroke(blockSectionLines, .border, Self.dashed, part: .cluster)
        builder.fill(blockTextPatches, .background, part: .labelBackground)
        for (text, ink) in zip(blockTexts, blockTextInks) { builder.text(text, Self.paint(ink, else: Self.mutedPaint), part: .clusterLabel) }
        builder.fillAndStroke(blockTabs, fill: .surface, stroke: .border, Self.line, part: .cluster)
        builder.texts(blockKeywords, Self.mutedPaint, isBold: true, part: .clusterLabel)
    }

    /// The messages' lines, heads and circles in the line color, then those over colored backgrounds in their colors,
    /// the numbers, the crosses of destroyed lifelines, and the messages' texts on their patches.
    private func addMessages(to builder: inout DiagramSceneBuilder) {
        Self.addLines(solid: solidMessageLines, dotted: dottedMessageLines, filledHeads: filledHeads, strokedHeads: strokedHeads,
                      circles: centralConnections, paint: .line, to: &builder)
        for group in inkedMessageLines {
            Self.addLines(solid: group.solidLines, dotted: group.dottedLines, filledHeads: group.filledHeads, strokedHeads: group.strokedHeads,
                          circles: group.centralConnections, paint: Self.paint(group.ink, else: .line), to: &builder)
        }
        builder.fill(numberBadges, .line, part: .marker)
        builder.texts(numberTexts, .background, part: .marker)
        builder.stroke(destructions, .line, DiagramStroke.rounded(lineWidth: Self.destructionLineWidth), part: .marker)
        builder.fill(messageTextPatches, .background, part: .labelBackground)
        for (text, ink) in zip(messageTexts, messageTextInks) { builder.text(text, Self.paint(ink, else: .foreground), part: .edgeLabel) }
    }

    /// Messages' lines, heads and central connections' circles, in one paint.
    private static func addLines(solid: CGPath, dotted: CGPath, filledHeads: CGPath, strokedHeads: CGPath, circles: CGPath, paint: DiagramPaint,
                                 to builder: inout DiagramSceneBuilder) {
        builder.stroke(solid, paint, line, part: .edge)
        builder.stroke(dotted, paint, dashed, part: .edge)
        builder.fill(filledHeads, paint, part: .marker)
        builder.stroke(strokedHeads, paint, line, part: .marker)
        builder.fill(circles, paint, part: .marker)
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
