/**
 * File: GitGraphScene.swift
 * -------------------------
 * Layer: Core
 * Description: A laid-out Git graph's scene: its drawing parts back to front in the colors' roles, as Pele paints them.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 23/11/2026
 */

import CoreGraphics

extension DiagramScene {
    /// The Git graph's painting: the lanes and their names' boxes in the lanes' series colors, the names, the lines
    /// between lanes, to cherry-picks and along lanes, the rings and symbols and their marks, the ids turned on their
    /// patches, the tags with their text, the title.
    public init(layout: GitGraphLayout) {
        var builder = DiagramSceneBuilder()
        GitGraphDrawingParts(layout: layout).addScene(to: &builder)
        self = builder.scene(size: layout.size, font: layout.font, seriesColors: layout.seriesColors)
    }
}

extension GitGraphDrawingParts {
    func addScene(to builder: inout DiagramSceneBuilder) {
        for group in colorGroups {
            let paint = DiagramPaint.series(group.seriesIndex)
            builder.stroke(group.laneLinesScenePath, paint, DiagramStroke(lineWidth: Self.laneLineWidth, dashLengths: Self.laneDashLengths), part: .cluster)
            builder.fill(group.nameBoxesScenePath, paint, part: .cluster)
        }
        for (name, paint) in zip(names, namePaints) { builder.text(name, paint, part: .clusterLabel) }
        let connector = DiagramStroke(lineWidth: Self.connectorLineWidth, lineCap: .round)
        for group in colorGroups { builder.stroke(group.curvesScenePath, .series(group.seriesIndex), connector, part: .edge) }
        for group in colorGroups {
            builder.stroke(group.cherryPickCurvesScenePath, .series(group.seriesIndex),
                           DiagramStroke(lineWidth: Self.connectorLineWidth, dashLengths: Self.cherryPickDashLengths, lineCap: .round), part: .edge)
        }
        for group in colorGroups { builder.stroke(group.straightLinesScenePath, .series(group.seriesIndex), connector, part: .edge) }
        for group in colorGroups {
            let paint = DiagramPaint.series(group.seriesIndex)
            builder.fillAndStroke(group.ringsScenePath, fill: .background, stroke: paint, DiagramStroke(lineWidth: Self.ringLineWidth), part: .node)
            builder.fill(group.symbolsScenePath, paint, part: .node)
        }
        builder.stroke(reverseCrossesScenePath, .background, DiagramStroke(lineWidth: Self.crossLineWidth, lineCap: .round), part: .marker)
        builder.stroke(cherryStemsScenePath, .background, DiagramStroke(lineWidth: Self.cherryStemLineWidth, lineJoin: .round), part: .marker)
        builder.fill(cherryFruitsScenePath, .background, part: .marker)
        builder.fill(labelPatchesScenePath, .background, part: .labelBackground)
        for label in labels { builder.text(label.text, .muted, rotation: label.angle, part: .label) }
        builder.fillAndStroke(tagBoxesScenePath, fill: .surface, stroke: .border, DiagramStroke(lineWidth: Self.tagLineWidth, lineJoin: .round), part: .marker)
        builder.fill(tagHolesScenePath, .border, part: .marker)
        builder.texts(tagTexts, .foreground, part: .label)
        builder.title(title)
    }
}
