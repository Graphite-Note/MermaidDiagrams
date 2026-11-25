/**
 * File: SankeyScene.swift
 * -----------------------
 * Layer: Core
 * Description: A laid-out Sankey diagram's scene: its bands and bars recorded into lanes of the thread's scene workspace
 *              and added back to front in the colors' roles, as Pele paints them, without a Core Graphics path.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 24/11/2026
 */

import CoreGraphics

extension DiagramScene {
    /// The Sankey diagram's painting: each band in a gradient across from its source's color to its target's (or in the
    /// source's, the target's or one color, as the options say) at `SankeyDrawingParts.bandOpacity`, the bars in their
    /// series colors or their own, the names, the values in the muted color (both outlined in the background color when
    /// the options say so), the title.
    public init(layout: SankeyLayout) {
        self = DiagramSceneWorkspace.withRecording { workspace in
            var builder = DiagramSceneBuilder(workspace: workspace)
            SankeySceneRecording.add(layout, to: &builder, workspace: workspace)
            return builder.scene(size: layout.size, font: layout.font)
        }
    }
}

/// Adds a Sankey diagram's painting to a scene in `SankeyDrawingParts`' order and paints, each band and each series
/// color's bars recorded into a lane of `workspace` given back once added.
enum SankeySceneRecording {
    static func add(_ layout: SankeyLayout, to builder: inout DiagramSceneBuilder, workspace: DiagramSceneWorkspace) {
        typealias Parts = SankeyDrawingParts
        for link in layout.links { addBand(of: link, layout: layout, to: &builder, workspace: workspace) }
        addBars(of: layout, to: &builder, workspace: workspace)
        let outline = layout.hasOutlinedLabels ? DiagramTextOutline(paint: .background, lineWidth: Parts.labelOutlineWidth) : nil
        for label in layout.labels { builder.text(label.name, .foreground, outline: outline, part: .label) }
        for label in layout.labels { builder.text(label.value, .muted, outline: outline, part: .label) }
        builder.title(layout.title)
    }

    /// A band in the options' one paint, or across from its source's paint to its target's, or in either's, at
    /// `SankeyDrawingParts.bandOpacity`.
    private static func addBand(of link: SankeyLayoutLink, layout: SankeyLayout, to builder: inout DiagramSceneBuilder, workspace: DiagramSceneWorkspace) {
        let opacity = SankeyDrawingParts.bandOpacity
        let madeCount = workspace.madePathCount
        defer { workspace.givePathsBack(downTo: madeCount) }
        let outline = workspace.makeLane()
        SankeyBandDrawing.addOutline(of: link, to: outline)
        if let fixedLinkPaint = layout.fixedLinkPaint { return builder.fill(outline, fixedLinkPaint.atOpacity(opacity), part: .edge) }
        let sourcePaint = layout.nodes[link.sourceSeriesIndex].paint ?? .series(link.sourceSeriesIndex)
        let targetPaint = layout.nodes[link.targetSeriesIndex].paint ?? .series(link.targetSeriesIndex)
        switch layout.linkColor {
        case .gradient:
            let gradient = DiagramLinearGradient(startPaint: sourcePaint, endPaint: targetPaint, startPoint: CGPoint(x: link.startX, y: 0),
                                                 endPoint: CGPoint(x: link.endX, y: 0), opacity: opacity)
            builder.fill(outline, gradient, part: .edge)
        case .source: builder.fill(outline, sourcePaint.atOpacity(opacity), part: .edge)
        case .target: builder.fill(outline, targetPaint.atOpacity(opacity), part: .edge)
        case .fixed(let color): builder.fill(outline, DiagramPaint.color(color).atOpacity(opacity), part: .edge)
        }
    }

    /// The bars: those in a series color, one fill a color, then those in a color of their own, then those in a paint of
    /// their own, each its own fill; corners rounded at most half the bar's height.
    private static func addBars(of layout: SankeyLayout, to builder: inout DiagramSceneBuilder, workspace: DiagramSceneWorkspace) {
        let seriesColorCount = SankeyDrawingParts.seriesColorCount
        func radius(of node: SankeyLayoutNode) -> CGFloat { min(SankeyDrawingParts.barCornerRadius, node.frame.height / 2) }
        for colorIndex in 0..<min(layout.nodes.count, seriesColorCount) {
            let madeCount = workspace.madePathCount
            let fill = workspace.makeLane()
            for node in layout.nodes where node.paint == nil && node.seriesIndex % seriesColorCount == colorIndex {
                fill.addRoundedRect(in: node.frame, cornerWidth: radius(of: node), cornerHeight: radius(of: node))
            }
            builder.fill(fill, .series(colorIndex), part: .node)
            workspace.givePathsBack(downTo: madeCount)
        }
        for node in layout.nodes where node.paint != nil {
            guard let color = node.color else { continue }
            addBar(node, radius: radius(of: node), paint: .color(color), to: &builder, workspace: workspace)
        }
        for node in layout.nodes where node.color == nil {
            guard let paint = node.paint else { continue }
            addBar(node, radius: radius(of: node), paint: paint, to: &builder, workspace: workspace)
        }
    }

    private static func addBar(_ node: SankeyLayoutNode, radius: CGFloat, paint: DiagramPaint, to builder: inout DiagramSceneBuilder,
                               workspace: DiagramSceneWorkspace) {
        let madeCount = workspace.madePathCount
        let bar = workspace.makeLane()
        bar.addRoundedRect(in: node.frame, cornerWidth: radius, cornerHeight: radius)
        builder.fill(bar, paint, part: .node)
        workspace.givePathsBack(downTo: madeCount)
    }
}
