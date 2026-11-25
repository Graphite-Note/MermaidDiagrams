/**
 * File: CynefinScene.swift
 * ------------------------
 * Layer: Core
 * Description: A laid-out Cynefin framework's scene, as Pele paints it: the title, the regions in their series colors,
 *              the dashed boundaries and the cliff, the confusion ellipse, the domains' blocks, then the transitions.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 25/11/2026
 */

import CoreGraphics

extension DiagramScene {
    /// The Cynefin framework's painting, back to front as Pele writes it: the title; each quadrant's region in its series
    /// color at 14 percent; the boundaries dashed in the border color and the cliff two points wide in the line color; the
    /// ellipse over them in the background, then in confusion's series color at 18 percent, dashed in the border color;
    /// each domain's name in bold, its subtitles in muted italic and its items in rounded boxes; each transition's curve,
    /// arrow and label in the line and text colors. Every shape is recorded into a lane of the thread's scene workspace,
    /// given back once the builder has copied it.
    public init(layout: CynefinLayout) {
        self.init(layout: layout, limits: .standard)
    }

    /// The same painting recorded under `limits`: a scene one of whose lanes goes past their element limit says so
    /// (`exceededPathElementLimit`), and the preparation refuses it.
    public init(layout: CynefinLayout, limits: MermaidDiagramLimits) {
        self = DiagramSceneWorkspace.withRecording(limits: limits) { workspace in
            var builder = DiagramSceneBuilder(workspace: workspace)
            let madeCount = workspace.madePathCount
            builder.title(layout.title)
            for region in layout.regions {
                let outline = CynefinScenePaths.line(region.outline, workspace: workspace)
                outline.closeSubpath()
                builder.fill(outline, DiagramPaint.series(region.seriesIndex).atOpacity(CynefinScenePaths.regionOpacity), part: .cynefinRegion)
                workspace.givePathsBack(downTo: madeCount)
            }
            let boundaries = workspace.makeLane()
            for boundary in layout.boundaries {
                boundaries.addPath(CynefinScenePaths.line(boundary, workspace: workspace))
                workspace.givePathsBack(downTo: madeCount + 1)
            }
            builder.stroke(boundaries, .border, DiagramStroke(lineWidth: 1, dashLengths: [6, 3]), part: .cynefinBoundary)
            builder.stroke(CynefinScenePaths.line(layout.cliff, workspace: workspace), .line, DiagramStroke(lineWidth: 2, lineCap: .round), part: .cynefinCliff)
            let ellipse = workspace.ellipse(in: layout.confusion)
            builder.fill(ellipse, .background, part: .cynefinRegion)
            builder.fillAndStroke(ellipse, fill: DiagramPaint.series(CynefinLayoutEngine.confusionSeriesIndex).atOpacity(CynefinScenePaths.confusionOpacity),
                                  stroke: .border, DiagramStroke(lineWidth: 1, dashLengths: [4, 2]), part: .cynefinRegion)
            workspace.givePathsBack(downTo: madeCount)
            for block in layout.blocks { CynefinScenePaths.add(block, to: &builder, workspace: workspace) }
            for transition in layout.transitions {
                builder.stroke(CynefinScenePaths.line(transition.path, workspace: workspace), .line, DiagramStroke(lineWidth: 1), part: .edge)
                let arrow = workspace.makeLane()
                DiagramEdgeDrawing.addMark(transition.arrow, filled: arrow, stroked: workspace.makeLane())
                builder.fill(arrow, .line, part: .marker)
                workspace.givePathsBack(downTo: madeCount)
                builder.text(transition.label, .foreground, part: .edgeLabel)
            }
            return builder.scene(size: layout.size, font: layout.font)
        }
    }
}

/// The shapes of a Cynefin framework's scene, recorded into lanes of the scene's workspace.
enum CynefinScenePaths {
    static let regionOpacity: CGFloat = 0.14
    static let confusionOpacity: CGFloat = 0.18
    /// Pele's `--pele-radius`.
    static let cornerRadius: CGFloat = 4

    /// A line in a lane of its own, which a drawing may add to: a region closes its outline.
    static func line(_ path: DiagramPath, workspace: DiagramSceneWorkspace) -> DiagramPathLane {
        let lane = workspace.makeLane()
        DiagramEdgeDrawing.record(path, into: lane)
        return lane
    }

    /// A block: its name, its subtitles, then each item's box and text in turn.
    static func add(_ block: CynefinLayoutBlock, to builder: inout DiagramSceneBuilder, workspace: DiagramSceneWorkspace) {
        builder.text(block.name, .foreground, isBold: true, part: .label)
        for subtitle in block.subtitles { builder.text(subtitle, .muted, isItalic: true, part: .cynefinSubtitle) }
        let madeCount = workspace.madePathCount
        for badge in block.badges {
            let box = workspace.roundedRectangle(badge.frame, cornerWidth: cornerRadius, cornerHeight: cornerRadius)
            builder.fillAndStroke(box, fill: .background, stroke: .border, DiagramStroke(lineWidth: 1, dashLengths: badge.isOverflow ? [3, 2] : []), part: .node)
            workspace.givePathsBack(downTo: madeCount)
            builder.text(badge.text, badge.isOverflow ? .muted : .foreground, part: .label)
        }
    }
}
