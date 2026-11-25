/**
 * File: UserJourneyColumnScene.swift
 * ----------------------------------
 * Layer: Core
 * Description: A user journey laid out as a column of cards, as a scene in the colors' roles, as Pele paints it.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

import CoreGraphics

extension DiagramScene {
    /// The column's painting: the lines between the cards, the cards in the surface and border colors with their text, the
    /// faces in the line color on the background with their scores, the actors' dots in their series colors with their
    /// names, the sections' headings, the title. The paths are recorded into lanes of the thread's scene workspace.
    public init(layout: UserJourneyColumnLayout) {
        self = DiagramSceneWorkspace.withRecording { workspace in
            var builder = DiagramSceneBuilder(workspace: workspace)
            UserJourneyColumnSceneRecording.add(layout, to: &builder, making: workspace)
            return builder.scene(size: layout.size, font: layout.font)
        }
    }
}

/// Adds a user journey column's painting to a scene, its paths recorded into lanes of the workspace.
enum UserJourneyColumnSceneRecording {
    static func add(_ layout: UserJourneyColumnLayout, to builder: inout DiagramSceneBuilder, making workspace: DiagramSceneWorkspace) {
        let lineWidth = UserJourneyDrawingParts.lineWidth
        let roundJoin = DiagramStroke(lineWidth: lineWidth, lineJoin: .round)
        let connectors = workspace.makePath()
        for connector in layout.connectors { workspace.addEdgeLine(connector, to: connectors) }
        builder.stroke(connectors, .line, DiagramStroke(lineWidth: lineWidth), part: .edge)
        let cards = workspace.makePath()
        let faces = workspace.makePath()
        let eyes = workspace.makePath()
        let mouths = workspace.makePath()
        let dotsBySeries = (0..<UserJourneyDrawingParts.seriesColorCount).map { _ in workspace.makePath() }
        let radius = UserJourneyDrawingParts.cornerRadius
        for step in layout.steps {
            workspace.addMadeRoundedRectangle(step.frame, cornerWidth: radius, cornerHeight: radius, to: cards)
            UserJourneyFaceShape.add(step.mood, at: step.faceCenter, circles: faces, eyes: eyes, mouths: mouths)
            for actor in step.actors { UserJourneyDrawingPaths.add(actor.dot, to: dotsBySeries) }
        }
        builder.fillAndStroke(cards, fill: .surface, stroke: .border, roundJoin, part: .node)
        for step in layout.steps { builder.text(step.text, .foreground, part: .label) }
        builder.fillAndStroke(faces, fill: .background, stroke: .line, roundJoin, part: .node)
        builder.fill(eyes, .line, part: .node)
        builder.stroke(mouths, .line, .rounded(lineWidth: lineWidth), part: .node)
        for step in layout.steps { builder.text(step.score, .foreground, part: .label) }
        for (index, dots) in dotsBySeries.enumerated() where !dots.isEmpty { builder.fill(dots, .series(index), part: .marker) }
        for step in layout.steps {
            for actor in step.actors { builder.text(actor.text, .foreground, part: .label) }
        }
        for heading in layout.headings { builder.text(heading, .foreground, isBold: true, part: .clusterLabel) }
        builder.title(layout.title)
    }
}
