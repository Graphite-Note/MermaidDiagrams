/**
 * File: UserJourneyScene.swift
 * ----------------------------
 * Layer: Core
 * Description: A laid-out user journey's scene: its drawing parts back to front in the colors' roles, as Pele paints
 *              them.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import CoreGraphics

extension DiagramScene {
    /// The user journey's painting: the scale in the second surface with its numbers muted, the dashed stems, the line
    /// and the faces in the line color on the background, the bands in the second surface, the cards in the surface and
    /// border colors with their text, the actors' dots in their series colors, the legend, the title.
    public init(layout: UserJourneyLayout) {
        var builder = DiagramSceneBuilder()
        UserJourneyDrawingParts(layout: layout).addScene(to: &builder)
        self = builder.scene(size: layout.size, font: layout.font)
    }
}

extension UserJourneyDrawingParts {
    /// Every line is one point wide; the scale and the stems have mitred joins, the rest round ones, and only the mouths
    /// round caps.
    func addScene(to builder: inout DiagramSceneBuilder) {
        let roundJoin = DiagramStroke(lineWidth: Self.lineWidth, lineJoin: .round)
        builder.stroke(scaleLinesScenePath, .alternateSurface, DiagramStroke(lineWidth: Self.lineWidth), part: .axis)
        builder.texts(scaleTexts, .muted, part: .axisLabel)
        builder.stroke(stemsScenePath, .border, DiagramStroke(lineWidth: Self.lineWidth, dashLengths: Self.stemDashLengths), part: .edge)
        builder.stroke(scoreLineScenePath, .line, roundJoin, part: .edge)
        builder.fillAndStroke(facesScenePath, fill: .background, stroke: .line, roundJoin, part: .node)
        builder.fill(eyesScenePath, .line, part: .node)
        builder.stroke(mouthsScenePath, .line, .rounded(lineWidth: Self.lineWidth), part: .node)
        builder.fill(sectionBandsScenePath, .alternateSurface, part: .cluster)
        builder.texts(sectionTexts, .foreground, isBold: true, part: .clusterLabel)
        builder.fillAndStroke(cardsScenePath, fill: .surface, stroke: .border, roundJoin, part: .node)
        builder.texts(taskTexts, .foreground, part: .label)
        for (index, dots) in cardDotsBySeriesScenePaths.enumerated() { builder.fillAndStroke(dots, fill: .series(index), stroke: .surface, roundJoin, part: .marker) }
        for (index, dots) in legendDotsBySeriesScenePaths.enumerated() { builder.fill(dots, .series(index), part: .legend) }
        builder.texts(legendTexts, .foreground, part: .legend)
        builder.title(title)
    }
}
