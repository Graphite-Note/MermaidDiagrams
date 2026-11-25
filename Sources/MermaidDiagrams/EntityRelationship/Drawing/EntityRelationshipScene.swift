/**
 * File: EntityRelationshipScene.swift
 * -----------------------------------
 * Layer: Core
 * Description: A laid-out entity relationship diagram's scene: its drawing parts back to front in the colors' roles, as
 *              Pele paints them, its paths recorded into lanes of the scene's workspace.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 24/11/2026
 */

import CoreGraphics

extension DiagramScene {
    /// The entity relationship diagram's painting: the groups' boxes and titles, the lines and their marks, the labels on their patches, the boxes
    /// with their striped rows, outlines and header dividers, the boxes' text, the title. Types, keys and comments are
    /// in the foreground at `EntityRelationshipDrawingParts.mutedTextOpacity`.
    public init(layout: EntityRelationshipLayout) {
        self = DiagramSceneWorkspace.withRecording { workspace in
            var builder = DiagramSceneBuilder(workspace: workspace)
            EntityRelationshipSceneRecording.add(layout, to: &builder, workspace: workspace)
            return builder.scene(size: layout.size, font: layout.font)
        }
    }
}

/// Adds an entity relationship diagram's painting to a scene, its paths recorded into lanes of `workspace`, grouped as
/// `EntityRelationshipDrawingParts` groups them.
enum EntityRelationshipSceneRecording {
    /// Every line is drawn one point wide with round caps and joins.
    static func add(_ layout: EntityRelationshipLayout, to builder: inout DiagramSceneBuilder, workspace: DiagramSceneWorkspace) {
        let lineWidth = EntityRelationshipDrawingParts.lineWidth
        let line = DiagramStroke.rounded(lineWidth: lineWidth)
        let subgraphs = FlowchartClusterPaths(clusters: layout.subgraphs, making: workspace)
        FlowchartSceneRecording.addBoxes(of: subgraphs, to: &builder)
        let paths = EntityRelationshipPaths(layout: layout, making: workspace)
        builder.stroke(paths.identifyingLines, .line, line, part: .edge)
        builder.stroke(paths.nonIdentifyingLines, .line, .rounded(lineWidth: lineWidth, dashLengths: EntityRelationshipDrawingParts.nonIdentifyingDashLengths),
                       part: .edge)
        builder.fill(paths.markFills, .background, part: .marker)
        builder.stroke(paths.markOutlines, .line, line, part: .marker)
        builder.fill(paths.labelPatches, .background, part: .labelBackground)
        for relationship in layout.relationships { builder.text(relationship.label, .foreground, part: .edgeLabel) }
        builder.fill(paths.boxFills, .surface, part: .node)
        builder.fill(paths.rowStripes, .background, part: .node)
        builder.stroke(paths.boxOutlines, .border, line, part: .node)
        for entity in layout.entities {
            builder.text(entity.name, .foreground, part: .label)
            for row in entity.rows {
                for cell in row.texts where !EntityRelationshipDrawingParts.isInMutedColor(cell.column) { builder.text(cell.text, .foreground, part: .label) }
            }
        }
        let muted = DiagramPaint.foreground.atOpacity(EntityRelationshipDrawingParts.mutedTextOpacity)
        for entity in layout.entities {
            for row in entity.rows {
                for cell in row.texts where EntityRelationshipDrawingParts.isInMutedColor(cell.column) { builder.text(cell.text, muted, part: .label) }
            }
        }
        builder.title(layout.title)
    }
}
