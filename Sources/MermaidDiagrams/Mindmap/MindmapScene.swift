/**
 * File: MindmapScene.swift
 * ------------------------
 * Layer: Core
 * Description: A laid-out mindmap's scene: its drawing parts back to front in the colors' roles, as Pele paints them.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import CoreGraphics

extension DiagramScene {
    /// The mindmap's painting: each branch's links and then its nodes in its series color, the root in the surface and
    /// border colors, the text, the title.
    public init(layout: MindmapLayout) {
        var builder = DiagramSceneBuilder()
        MindmapDrawingParts(layout: layout).addScene(to: &builder)
        self = builder.scene(size: layout.size, font: layout.font, seriesColors: layout.seriesColors)
    }
}

extension MindmapDrawingParts {
    func addScene(to builder: inout DiagramSceneBuilder) {
        let outline = DiagramStroke(lineWidth: Self.outlineLineWidth)
        for branch in branches {
            let paint = DiagramPaint.series(branch.branchIndex)
            builder.stroke(branch.links, paint, DiagramStroke(lineWidth: Self.linkLineWidth), part: .edge)
            builder.fillAndStroke(branch.nodeOutlines, fill: paint.atOpacity(Self.nodeFillOpacity), stroke: paint, outline, part: .node)
        }
        builder.fillAndStroke(rootOutline, fill: .surface, stroke: .border, outline, part: .node)
        builder.texts(nodeTexts, .foreground, part: .label)
        builder.title(title)
    }
}
