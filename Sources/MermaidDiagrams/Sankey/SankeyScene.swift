/**
 * File: SankeyScene.swift
 * -----------------------
 * Layer: Core
 * Description: A laid-out Sankey diagram's scene: its drawing parts back to front in the colors' roles, as Pele paints
 *              them.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 23/11/2026
 */

import CoreGraphics

extension DiagramScene {
    /// The Sankey diagram's painting: each band in a gradient across from its source's color to its target's (or in the
    /// source's, the target's or one color, as the options say) at `SankeyDrawingParts.bandOpacity`, the bars in their
    /// series colors or their own, the names, the values in the muted color (both outlined in the background color when
    /// the options say so), the title.
    public init(layout: SankeyLayout) {
        var builder = DiagramSceneBuilder()
        SankeyDrawingParts(layout: layout).addScene(to: &builder)
        self = builder.scene(size: layout.size, font: layout.font)
    }
}

extension SankeyDrawingParts {
    func addScene(to builder: inout DiagramSceneBuilder) {
        for band in bands {
            let sourcePaint = band.sourcePaint
            let targetPaint = band.targetPaint
            if let fixedLinkPaint {
                builder.fill(band.outlineScenePath, fixedLinkPaint.atOpacity(Self.bandOpacity), part: .edge)
                continue
            }
            switch linkColor {
            case .gradient:
                let gradient = DiagramLinearGradient(startPaint: sourcePaint, endPaint: targetPaint, startPoint: CGPoint(x: band.startX, y: 0),
                                                     endPoint: CGPoint(x: band.endX, y: 0), opacity: Self.bandOpacity)
                builder.fill(band.outlineScenePath, gradient, part: .edge)
            case .source: builder.fill(band.outlineScenePath, sourcePaint.atOpacity(Self.bandOpacity), part: .edge)
            case .target: builder.fill(band.outlineScenePath, targetPaint.atOpacity(Self.bandOpacity), part: .edge)
            case .fixed(let color): builder.fill(band.outlineScenePath, DiagramPaint.color(color).atOpacity(Self.bandOpacity), part: .edge)
            }
        }
        for (index, nodeFill) in nodeFillsScenePaths.enumerated() { builder.fill(nodeFill, .series(index), part: .node) }
        for colored in coloredNodeFills { builder.fill(colored.pathScenePath, .color(colored.color), part: .node) }
        for painted in paintedNodeFills { builder.fill(painted.pathScenePath, painted.paint, part: .node) }
        let outline = hasOutlinedLabels ? DiagramTextOutline(paint: .background, lineWidth: Self.labelOutlineWidth) : nil
        builder.texts(names, .foreground, outline: outline, part: .label)
        builder.texts(values, .muted, outline: outline, part: .label)
        builder.title(title)
    }
}
