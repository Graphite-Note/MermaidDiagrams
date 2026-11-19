/**
 * File: SwimlaneDrawingParts.swift
 * --------------------------------
 * Layer: Core
 * Description: A laid-out swimlane diagram's geometry grouped by how it is painted, its scene in Pele's order and roles,
 *              and its renderer.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// A laid-out swimlane diagram's geometry grouped by how Pele paints it: the lanes, each an outline in the border color with
/// a band at its start filled with the alternate surface and outlined, its title muted in the band (turned a quarter turn
/// counterclockwise where the flow runs across); then the flowchart inside them (`FlowchartDrawingParts`): the groups inside
/// lanes, the edges, their texts, the nodes and the title.
public struct SwimlaneDrawingParts {
    /// The lanes' outlines, stroked one point wide in the border color.
    public let laneOutlines: CGPath
    /// The lanes' title bands, filled with the alternate surface and outlined in the border color.
    public let titleBands: CGPath
    public let titles: [DiagramTextBlock]
    /// Whether the titles are turned a quarter turn counterclockwise.
    public let areTitlesTurned: Bool
    public let flowchart: FlowchartDrawingParts

    /// The turn of a title in a flow that runs across: a quarter turn counterclockwise on the page.
    public static let turnedTitleRotation: CGFloat = -.pi / 2

    public init(layout: SwimlaneLayout) {
        let outlines = CGMutablePath()
        let bands = CGMutablePath()
        for lane in layout.lanes {
            outlines.addRect(lane.frame)
            bands.addRect(lane.titleBand)
        }
        laneOutlines = outlines
        titleBands = bands
        titles = layout.lanes.compactMap(\.title)
        areTitlesTurned = layout.lanes.first?.isTitleTurned ?? false
        flowchart = FlowchartDrawingParts(layout: layout.flowchart)
    }
}

extension DiagramScene {
    /// The swimlane diagram's painting: the lanes behind the flowchart's painting (`DiagramScene(layout:)` of a flowchart).
    public init(layout: SwimlaneLayout) {
        var builder = DiagramSceneBuilder()
        SwimlaneDrawingParts(layout: layout).addScene(to: &builder)
        self = builder.scene(size: layout.size, font: layout.flowchart.font)
    }
}

extension SwimlaneDrawingParts {
    func addScene(to builder: inout DiagramSceneBuilder) {
        let line = DiagramStroke(lineWidth: FlowchartDrawingParts.lineWidth)
        builder.stroke(laneOutlines, .border, line, part: .cluster)
        builder.fillAndStroke(titleBands, fill: .alternateSurface, stroke: .border, line, part: .cluster)
        for title in titles { builder.text(title, .muted, rotation: areTitlesTurned ? Self.turnedTitleRotation : nil, part: .clusterLabel) }
        flowchart.addScene(to: &builder)
    }
}

/// Draws a laid-out swimlane diagram into a Core Graphics context whose origin is the layout's top left and whose y runs
/// down, by painting its scene with `DiagramSceneRenderer`.
public enum SwimlaneRenderer {
    public static func draw(_ layout: SwimlaneLayout, in context: CGContext, palette: DiagramPalette) {
        DiagramSceneRenderer.draw(DiagramScene(layout: layout), in: context, palette: palette)
    }
}
