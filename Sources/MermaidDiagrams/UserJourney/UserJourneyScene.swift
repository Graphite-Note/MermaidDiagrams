/**
 * File: UserJourneyScene.swift
 * ----------------------------
 * Layer: Core
 * Description: A laid-out user journey's scene: its drawing parts back to front in the colors' roles, as Pele paints
 *              them.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 25/11/2026
 */

import CoreGraphics

extension DiagramScene {
    /// The user journey's painting: the scale in the second surface with its numbers muted, the dashed stems, the line
    /// and the faces in the line color on the background, the bands in the second surface, the cards in the surface and
    /// border colors with their text, the actors' dots in their series colors, the legend, the title. The paths are
    /// recorded into lanes of the thread's scene workspace.
    public init(layout: UserJourneyLayout) {
        self.init(layout: layout, limits: .standard)
    }

    /// The scene with each of its lanes bounded as `limits` bound them (`DiagramSceneWorkspace.elementLimit(for:)`): a
    /// lane past its limit is emptied and the scene says so (`exceededPathElementLimit`), which the preparation refuses.
    public init(layout: UserJourneyLayout, limits: MermaidDiagramLimits) {
        self = DiagramSceneWorkspace.withRecording(limits: limits) { workspace in
            var builder = DiagramSceneBuilder(workspace: workspace)
            UserJourneySceneRecording.add(layout, paths: UserJourneyDrawingPaths(layout: layout, making: workspace), to: &builder)
            return builder.scene(size: layout.size, font: layout.font)
        }
    }
}

/// Adds a user journey's painting to a scene from its layout and its paths, recorded into lanes.
enum UserJourneySceneRecording {
    /// Every line is one point wide; the scale and the stems have mitred joins, the rest round ones, and only the mouths
    /// round caps.
    static func add(_ layout: UserJourneyLayout, paths: UserJourneyDrawingPaths<DiagramPathLane>, to builder: inout DiagramSceneBuilder) {
        let lineWidth = UserJourneyDrawingParts.lineWidth
        let roundJoin = DiagramStroke(lineWidth: lineWidth, lineJoin: .round)
        builder.stroke(paths.scaleLines, .alternateSurface, DiagramStroke(lineWidth: lineWidth), part: .axis)
        for level in layout.scaleLevels { builder.text(level.text, .muted, part: .axisLabel) }
        builder.stroke(paths.stems, .border, DiagramStroke(lineWidth: lineWidth, dashLengths: UserJourneyDrawingParts.stemDashLengths), part: .edge)
        builder.stroke(paths.scoreLine, .line, roundJoin, part: .edge)
        builder.fillAndStroke(paths.faces, fill: .background, stroke: .line, roundJoin, part: .node)
        builder.fill(paths.eyes, .line, part: .node)
        builder.stroke(paths.mouths, .line, .rounded(lineWidth: lineWidth), part: .node)
        builder.fill(paths.sectionBands, .alternateSurface, part: .cluster)
        for section in layout.sections { builder.text(section.text, .foreground, isBold: true, part: .clusterLabel) }
        builder.fillAndStroke(paths.cards, fill: .surface, stroke: .border, roundJoin, part: .node)
        for task in layout.tasks { builder.text(task.text, .foreground, part: .label) }
        for (index, dots) in paths.cardDotsBySeries.enumerated() { builder.fillAndStroke(dots, fill: .series(index), stroke: .surface, roundJoin, part: .marker) }
        for (index, dots) in paths.legendDotsBySeries.enumerated() { builder.fill(dots, .series(index), part: .legend) }
        for entry in layout.legend { builder.text(entry.text, .foreground, part: .legend) }
        builder.title(layout.title)
    }
}
