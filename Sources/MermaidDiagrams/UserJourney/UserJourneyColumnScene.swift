/**
 * File: UserJourneyColumnScene.swift
 * ----------------------------------
 * Layer: Core
 * Description: A user journey laid out as a column of cards, as a scene in the colors' roles, as Pele paints it.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import CoreGraphics

extension DiagramScene {
    /// The column's painting: the lines between the cards, the cards in the surface and border colors with their text, the
    /// faces in the line color on the background with their scores, the actors' dots in their series colors with their
    /// names, the sections' headings, the title.
    public init(layout: UserJourneyColumnLayout) {
        var builder = DiagramSceneBuilder()
        let roundJoin = DiagramStroke(lineWidth: UserJourneyDrawingParts.lineWidth, lineJoin: .round)
        var connectors = DiagramScenePath()
        for connector in layout.connectors { connectors.addEdgePath(connector) }
        builder.stroke(connectors, .line, DiagramStroke(lineWidth: UserJourneyDrawingParts.lineWidth), part: .edge)
        var cards = DiagramScenePath()
        var faces = DiagramScenePath()
        var eyes = DiagramScenePath()
        var mouths = DiagramScenePath()
        var dotsBySeries = (0..<UserJourneyDrawingParts.seriesColorCount).map { _ in DiagramScenePath() }
        for step in layout.steps {
            cards.addPathOfRoundedRect(step.frame, cornerWidth: UserJourneyDrawingParts.cornerRadius,
                                 cornerHeight: UserJourneyDrawingParts.cornerRadius)
            UserJourneyFaceShape.add(step.mood, at: step.faceCenter, circles: &faces, eyes: &eyes, mouths: &mouths)
            for actor in step.actors {
                let radius = UserJourneyGeometry.dotRadius
                dotsBySeries[actor.dot.seriesIndex % UserJourneyDrawingParts.seriesColorCount].addEllipse(
                    in: CGRect(x: actor.dot.center.x - radius, y: actor.dot.center.y - radius, width: 2 * radius, height: 2 * radius))
            }
        }
        builder.fillAndStroke(cards, fill: .surface, stroke: .border, roundJoin, part: .node)
        builder.texts(layout.steps.map(\.text), .foreground, part: .label)
        builder.fillAndStroke(faces, fill: .background, stroke: .line, roundJoin, part: .node)
        builder.fill(eyes, .line, part: .node)
        builder.stroke(mouths, .line, .rounded(lineWidth: UserJourneyDrawingParts.lineWidth), part: .node)
        builder.texts(layout.steps.compactMap(\.score), .foreground, part: .label)
        for (index, dots) in dotsBySeries.enumerated() where !dots.isEmpty { builder.fill(dots, .series(index), part: .marker) }
        builder.texts(layout.steps.flatMap { step in step.actors.map(\.text) }, .foreground, part: .label)
        builder.texts(layout.headings, .foreground, isBold: true, part: .clusterLabel)
        builder.title(layout.title)
        self = builder.scene(size: layout.size, font: layout.font)
    }
}
