/**
 * File: MindmapScene.swift
 * ------------------------
 * Layer: Core
 * Description: A laid-out mindmap's scene: its drawing parts back to front in the colors' roles, as Pele paints them.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 25/11/2026
 */

import CoreGraphics

extension DiagramScene {
    /// The mindmap's painting: each branch's links and then its nodes in its series color, the root in the surface and
    /// border colors, the text, the title; its shapes recorded into lanes of the thread's scene workspace.
    public init(layout: MindmapLayout) {
        self.init(layout: layout, limits: .standard)
    }

    /// The same painting recorded under `limits`: a scene one of whose lanes goes past their element limit says so
    /// (`exceededPathElementLimit`), and the preparation refuses it.
    public init(layout: MindmapLayout, limits: MermaidDiagramLimits) {
        self = DiagramSceneWorkspace.withRecording(limits: limits) { workspace in
            var builder = DiagramSceneBuilder(workspace: workspace)
            MindmapPaths(layout: layout, making: workspace).addScene(of: layout, to: &builder)
            return builder.scene(size: layout.size, font: layout.font, seriesColors: layout.seriesColors)
        }
    }
}

extension MindmapPaths where Path == DiagramPathLane {
    func addScene(of layout: MindmapLayout, to builder: inout DiagramSceneBuilder) {
        let outline = DiagramStroke(lineWidth: MindmapDrawingParts.outlineLineWidth)
        for branchIndex in 0..<MindmapNode.branchCount where hasPaint(branchIndex: branchIndex) {
            let paint = DiagramPaint.series(branchIndex)
            builder.stroke(links[branchIndex], paint, DiagramStroke(lineWidth: MindmapDrawingParts.linkLineWidth), part: .edge)
            builder.fillAndStroke(outlines[branchIndex], fill: paint.atOpacity(MindmapDrawingParts.nodeFillOpacity), stroke: paint, outline, part: .node)
        }
        builder.fillAndStroke(rootOutline, fill: .surface, stroke: .border, outline, part: .node)
        for node in layout.nodes {
            if node.isTextLeftAligned {
                builder.texts(node.text.leftAlignedLines(), .foreground, part: .label)
            } else {
                builder.text(node.text, .foreground, part: .label)
            }
        }
        builder.title(layout.title)
    }
}
