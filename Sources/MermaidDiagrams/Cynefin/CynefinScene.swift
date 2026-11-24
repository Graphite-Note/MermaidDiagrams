/**
 * File: CynefinScene.swift
 * ------------------------
 * Layer: Core
 * Description: A laid-out Cynefin framework's scene, as Pele paints it: the title, the regions in their series colors,
 *              the dashed boundaries and the cliff, the confusion ellipse, the domains' blocks, then the transitions.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import CoreGraphics

extension DiagramScene {
    /// The Cynefin framework's painting, back to front as Pele writes it: the title; each quadrant's region in its series
    /// color at 14 percent; the boundaries dashed in the border color and the cliff two points wide in the line color; the
    /// ellipse over them in the background, then in confusion's series color at 18 percent, dashed in the border color;
    /// each domain's name in bold, its subtitles in muted italic and its items in rounded boxes; each transition's curve,
    /// arrow and label in the line and text colors.
    public init(layout: CynefinLayout) {
        var builder = DiagramSceneBuilder()
        builder.title(layout.title)
        for region in layout.regions {
            builder.fill(CynefinScenePaths.closed(region.outline), DiagramPaint.series(region.seriesIndex).atOpacity(CynefinScenePaths.regionOpacity),
                         part: .cynefinRegion)
        }
        var boundaries = DiagramScenePath()
        for boundary in layout.boundaries { boundaries.addEdgePath(boundary) }
        builder.stroke(boundaries, .border, DiagramStroke(lineWidth: 1, dashLengths: [6, 3]), part: .cynefinBoundary)
        builder.stroke(DiagramEdgeDrawing.path(layout.cliff), .line, DiagramStroke(lineWidth: 2, lineCap: .round), part: .cynefinCliff)
        let ellipse = DiagramScenePath(ellipseIn: layout.confusion)
        builder.fill(ellipse, .background, part: .cynefinRegion)
        builder.fillAndStroke(ellipse, fill: DiagramPaint.series(CynefinLayoutEngine.confusionSeriesIndex).atOpacity(CynefinScenePaths.confusionOpacity),
                              stroke: .border, DiagramStroke(lineWidth: 1, dashLengths: [4, 2]), part: .cynefinRegion)
        for block in layout.blocks { CynefinScenePaths.add(block, to: &builder) }
        for transition in layout.transitions {
            builder.stroke(DiagramEdgeDrawing.path(transition.path), .line, DiagramStroke(lineWidth: 1), part: .edge)
            var arrow = DiagramScenePath()
            DiagramEdgeDrawing.addMark(transition.arrow, filled: &arrow)
            builder.fill(arrow, .line, part: .marker)
            builder.text(transition.label, .foreground, part: .edgeLabel)
        }
        self = builder.scene(size: layout.size, font: layout.font)
    }
}

/// The shapes of a Cynefin framework's scene.
enum CynefinScenePaths {
    static let regionOpacity: CGFloat = 0.14
    static let confusionOpacity: CGFloat = 0.18
    /// Pele's `--pele-radius`.
    static let cornerRadius: CGFloat = 4

    /// A region's outline, closed.
    static func closed(_ outline: DiagramPath) -> DiagramScenePath {
        var path = DiagramScenePath()
        path.addEdgePath(outline)
        path.closeSubpath()
        return path
    }

    /// A block: its name, its subtitles, then each item's box and text in turn.
    static func add(_ block: CynefinLayoutBlock, to builder: inout DiagramSceneBuilder) {
        builder.text(block.name, .foreground, isBold: true, part: .label)
        for subtitle in block.subtitles { builder.text(subtitle, .muted, isItalic: true, part: .cynefinSubtitle) }
        for badge in block.badges {
            let box = DiagramScenePath(roundedRect: badge.frame, cornerWidth: cornerRadius, cornerHeight: cornerRadius)
            builder.fillAndStroke(box, fill: .background, stroke: .border, DiagramStroke(lineWidth: 1, dashLengths: badge.isOverflow ? [3, 2] : []), part: .node)
            builder.text(badge.text, badge.isOverflow ? .muted : .foreground, part: .label)
        }
    }
}
