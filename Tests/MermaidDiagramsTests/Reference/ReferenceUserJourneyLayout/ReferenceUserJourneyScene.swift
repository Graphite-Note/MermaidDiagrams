/**
 * File: ReferenceUserJourneyScene.swift
 * -------------------------------------
 * Layer: Tests
 * Description: 0.7.0's user journey scene, frozen as main ba176e5 recorded it from a layout of placed tasks with their
 *              paths, which the scene of the flat user journey layout is compared with.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// Adds a user journey's painting to a scene from its layout and its paths, recorded into lanes.
enum ReferenceUserJourneySceneRecording {
    /// The scene of `layout`, made as 0.7.0's `DiagramScene(layout:limits:)` made it.
    static func scene(_ layout: ReferenceUserJourneyLayout, limits: MermaidDiagramLimits = .standard) -> DiagramScene {
        DiagramSceneWorkspace.withRecording(limits: limits) { workspace in
            var builder = DiagramSceneBuilder(workspace: workspace)
            add(layout, paths: ReferenceUserJourneyDrawingPaths(layout: layout, making: workspace), to: &builder)
            return builder.scene(size: layout.size, font: layout.font)
        }
    }

    /// Every line is one point wide; the scale and the stems have mitred joins, the rest round ones, and only the mouths
    /// round caps.
    static func add(_ layout: ReferenceUserJourneyLayout, paths: ReferenceUserJourneyDrawingPaths<DiagramPathLane>, to builder: inout DiagramSceneBuilder) {
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

/// A user journey's paths, grouped as `UserJourneyDrawingParts` groups them, recorded into the paths a maker makes:
/// Core Graphics paths for the drawing parts, lanes of the thread's scene workspace for the scene, the same elements.
struct ReferenceUserJourneyDrawingPaths<Path: DiagramCurvedPathRecording> {
    let scaleLines: Path
    let stems: Path
    let scoreLine: Path
    let faces: Path
    let eyes: Path
    let mouths: Path
    let sectionBands: Path
    let cards: Path
    let cardDotsBySeries: [Path]
    let legendDotsBySeries: [Path]

    init<Maker: DiagramPathMaking>(layout: ReferenceUserJourneyLayout, making maker: Maker) where Maker.Path == Path {
        faces = maker.makePath()
        eyes = maker.makePath()
        mouths = maker.makePath()
        stems = maker.makePath()
        cards = maker.makePath()
        let seriesCount = UserJourneyDrawingParts.seriesColorCount
        let usedSeriesCount = min(layout.legend.count, seriesCount)
        cardDotsBySeries = (0..<usedSeriesCount).map { _ in maker.makePath() }
        legendDotsBySeries = (0..<usedSeriesCount).map { _ in maker.makePath() }
        let radius = UserJourneyDrawingParts.cornerRadius
        // A stem and a scale line are a move and a line each, so that recording them straight into their group adds the
        // elements adding each through a path of its own would (`addEdgeLine`): no group ends with a move another follows.
        for task in layout.tasks {
            UserJourneyFaceShape.add(task.mood, at: task.faceCenter, circles: faces, eyes: eyes, mouths: mouths)
            DiagramEdgeDrawing.record(task.stem, into: stems)
            maker.addMadeRoundedRectangle(task.frame, cornerWidth: radius, cornerHeight: radius, to: cards)
            for dot in task.actorDots { Self.add(dot, to: cardDotsBySeries) }
        }
        for entry in layout.legend { Self.add(entry.dot, to: legendDotsBySeries) }
        scaleLines = maker.makePath()
        for level in layout.scaleLevels { DiagramEdgeDrawing.record(level.line, into: scaleLines) }
        sectionBands = maker.makePath()
        for section in layout.sections { maker.addMadeRoundedRectangle(section.frame, cornerWidth: radius, cornerHeight: radius, to: sectionBands) }
        scoreLine = maker.makePath()
        if let line = layout.scoreLine { DiagramEdgeDrawing.record(line, into: scoreLine) }
    }

    /// An actor's dot, in the paths of its series color.
    static func add(_ dot: UserJourneyActorDot, to dotsBySeries: [Path]) {
        let radius = UserJourneyGeometry.dotRadius
        dotsBySeries[dot.seriesIndex % UserJourneyDrawingParts.seriesColorCount].addEllipse(
            in: CGRect(x: dot.center.x - radius, y: dot.center.y - radius, width: 2 * radius, height: 2 * radius))
    }
}
