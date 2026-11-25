/**
 * File: VennScene.swift
 * ---------------------
 * Layer: Core
 * Description: A laid-out Venn diagram's scene, as Pele paints it: the title, the circles in their series colors at a
 *              fifth of their opacity, the overlaps a style outlines, then each region's text, the shapes recorded into
 *              lanes of the thread's scene workspace without a Core Graphics path.
 *
 * Authors: Bahey Shalash
 * Version: 0.5
 * Date: 25/11/2026
 */

import CoreGraphics

extension DiagramScene {
    /// The Venn diagram's painting, back to front as Pele writes it: the title, each circle filled in its series color at
    /// a fifth of its opacity and outlined in it (or in its style's colors), the overlaps a style gives a look, and each
    /// region's lines, a set's label in the text color and its texts in the muted color unless a color is given.
    public init(layout: VennLayout) {
        self.init(layout: layout, limits: .standard)
    }

    /// The same painting recorded under `limits`: a scene one of whose lanes goes past their element limit says so
    /// (`exceededPathElementLimit`), and the preparation refuses it.
    public init(layout: VennLayout, limits: MermaidDiagramLimits) {
        self = DiagramSceneWorkspace.withRecording(limits: limits) { workspace in
            var builder = DiagramSceneBuilder(workspace: workspace)
            builder.title(layout.title)
            for set in layout.sets {
                let madeCount = workspace.madePathCount
                defer { workspace.givePathsBack(downTo: madeCount) }
                let circle = workspace.ellipse(in: CGRect(x: set.center.x - set.radius, y: set.center.y - set.radius, width: 2 * set.radius,
                                                          height: 2 * set.radius))
                let appearance = set.appearance
                builder.fillAndStroke(circle, fill: VennScenePaint.fill(appearance, usual: .series(set.seriesIndex), usualOpacity: VennScenePaint.setFillOpacity),
                                      stroke: VennScenePaint.stroke(appearance, usual: .series(set.seriesIndex)), VennScenePaint.stroke(of: appearance),
                                      part: .vennSet)
            }
            for overlap in layout.overlaps where overlap.appearance.fill != nil || overlap.appearance.stroke != nil {
                let madeCount = workspace.madePathCount
                defer { workspace.givePathsBack(downTo: madeCount) }
                let outline = workspace.makeLane()
                overlap.outline.record(into: outline)
                let appearance = overlap.appearance
                if appearance.fill != nil { builder.fill(outline, VennScenePaint.fill(appearance, usual: .background, usualOpacity: 1), part: .vennOverlap) }
                if appearance.stroke != nil {
                    builder.stroke(outline, VennScenePaint.stroke(appearance, usual: .line), VennScenePaint.stroke(of: appearance), part: .vennOverlap)
                }
            }
            for region in layout.regions {
                for line in region.lines {
                    let usual: DiagramPaint = line.isRegionText ? .muted : .foreground
                    let paint = (line.color.map(DiagramPaint.color) ?? usual).atOpacity(CGFloat(line.opacity ?? 1))
                    builder.text(line.text, paint, isBold: line.isBold, isItalic: line.isItalic, part: line.isRegionText ? .vennText : .label)
                }
            }
            return builder.scene(size: layout.size, font: layout.font, seriesColors: layout.seriesColors)
        }
    }
}

/// The paints a Venn diagram's styles give its shapes.
enum VennScenePaint {
    /// A circle's fill is its color at a fifth of its opacity, unless its style sets a fill opacity.
    static let setFillOpacity = 0.2
    static let lineWidth: CGFloat = 1

    /// The style's fill at its fill opacity and opacity, else `usual` at `usualOpacity`.
    static func fill(_ appearance: VennAppearance, usual: DiagramPaint, usualOpacity: Double) -> DiagramPaint {
        (appearance.fill.map(DiagramPaint.color) ?? usual).atOpacity(CGFloat((appearance.fillOpacity ?? usualOpacity) * (appearance.opacity ?? 1)))
    }

    /// The style's stroke at its stroke opacity and opacity, else `usual`.
    static func stroke(_ appearance: VennAppearance, usual: DiagramPaint) -> DiagramPaint {
        (appearance.stroke.map(DiagramPaint.color) ?? usual).atOpacity(CGFloat((appearance.strokeOpacity ?? 1) * (appearance.opacity ?? 1)))
    }

    static func stroke(of appearance: VennAppearance) -> DiagramStroke {
        DiagramStroke(lineWidth: appearance.strokeWidth ?? lineWidth, dashLengths: appearance.strokeDashLengths ?? [])
    }
}
