/**
 * File: EntityRelationshipScene.swift
 * -----------------------------------
 * Layer: Core
 * Description: A laid-out entity relationship diagram's scene: its drawing parts back to front in the colors' roles, as
 *              Pele paints them.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

import CoreGraphics

extension DiagramScene {
    /// The entity relationship diagram's painting: the groups' boxes and titles, the lines and their marks, the labels on their patches, the boxes
    /// with their striped rows, outlines and header dividers, the boxes' text, the title. Types, keys and comments are
    /// in the foreground at `EntityRelationshipDrawingParts.mutedTextOpacity`.
    public init(layout: EntityRelationshipLayout) {
        var builder = DiagramSceneBuilder()
        EntityRelationshipDrawingParts(layout: layout).addScene(to: &builder)
        self = builder.scene(size: layout.size, font: layout.font)
    }
}

extension EntityRelationshipDrawingParts {
    /// Every line is drawn one point wide with round caps and joins.
    func addScene(to builder: inout DiagramSceneBuilder) {
        let line = DiagramStroke.rounded(lineWidth: Self.lineWidth)
        subgraphs.addBoxes(to: &builder)
        builder.stroke(identifyingLines, .line, line, part: .edge)
        builder.stroke(nonIdentifyingLines, .line, .rounded(lineWidth: Self.lineWidth, dashLengths: Self.nonIdentifyingDashLengths), part: .edge)
        builder.fill(markFills, .background, part: .marker)
        builder.stroke(markOutlines, .line, line, part: .marker)
        builder.fill(labelPatches, .background, part: .labelBackground)
        builder.texts(labels, .foreground, part: .edgeLabel)
        builder.fill(boxFills, .surface, part: .node)
        builder.fill(rowStripes, .background, part: .node)
        builder.stroke(boxOutlines, .border, line, part: .node)
        builder.texts(entityTexts, .foreground, part: .label)
        builder.texts(attributeDetails, DiagramPaint.foreground.atOpacity(Self.mutedTextOpacity), part: .label)
        builder.title(title)
    }
}
