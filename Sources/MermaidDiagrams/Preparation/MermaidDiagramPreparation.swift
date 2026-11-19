/**
 * File: MermaidDiagramPreparation.swift
 * -------------------------------------
 * Layer: Core
 * Description: The one entry point that reads any diagram text, lays it out and makes its scenes and what a screen
 *              reader says of it, or says why it is not drawn.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 19/11/2026
 */

import CoreGraphics
import Foundation

/// Reads a diagram's text, lays it out and prepares its scene, whatever its type, so that a reader needs no code of its
/// own per type. A text that is not read, a layout that refuses what it holds, a diagram that declares nothing to draw,
/// and one longer than the limits' drawing side are refused with why (`MermaidDiagramPreparationFailure`), never an empty
/// or a giant scene. Adding a type means its parser, its layout, its scene, and one case in `prepare(_:)`'s switch.
public enum MermaidDiagramPreparation {
    /// `source` read and prepared. `typography` is the text the diagram is measured in; `narrowestColumnWidth` the
    /// narrowest column it may be shown in, past which it is laid out a second time to run down (nil for none); `now` and
    /// `timeZone` place a Gantt chart's today and its dates.
    public static func prepare(source: String, typography: DiagramTypography, limits: MermaidDiagramLimits = .standard,
                               narrowestColumnWidth: CGFloat? = PreparedMermaidDiagram.standardNarrowestColumnWidth, now: Date = Date(),
                               timeZone: TimeZone = .current) throws(MermaidDiagramPreparationFailure) -> PreparedMermaidDiagram {
        let diagram: MermaidDiagram
        do {
            diagram = try MermaidDiagramReader.read(source, limits: limits)
        } catch {
            throw .reading(error)
        }
        return try prepare(diagram, typography: typography, limits: limits, narrowestColumnWidth: narrowestColumnWidth, now: now, timeZone: timeZone)
    }

    /// A diagram already read, prepared. A layout's own refusal says more than "nothing to draw", so it is kept. A diagram
    /// that is refused anyway, as it has nothing to draw or as its regular scene is beyond the drawing limit, is never laid
    /// out a second time for a narrow column.
    public static func prepare(_ diagram: MermaidDiagram, typography: DiagramTypography, limits: MermaidDiagramLimits = .standard,
                               narrowestColumnWidth: CGFloat? = PreparedMermaidDiagram.standardNarrowestColumnWidth, now: Date = Date(),
                               timeZone: TimeZone = .current) throws(MermaidDiagramPreparationFailure) -> PreparedMermaidDiagram {
        let context = MermaidDiagramPreparationContext(typography: typography, limits: limits,
                                                       narrowestColumnWidth: diagram.hasNothingToDraw ? nil : narrowestColumnWidth, now: now,
                                                       timeZone: timeZone)
        let prepared = try context.prepared(diagram)
        if diagram.hasNothingToDraw { throw .nothingToDraw }
        guard limits.allowsDrawing(prepared.scene.size) else { throw .tooLargeToDraw(maximumSideLength: limits.maximumDrawingSideLength) }
        return prepared
    }
}

/// What every type's preparation is given.
struct MermaidDiagramPreparationContext {
    let typography: DiagramTypography
    let limits: MermaidDiagramLimits
    let narrowestColumnWidth: CGFloat?
    let now: Date
    let timeZone: TimeZone

    /// The one switch over the types: a new type is one more case.
    func prepared(_ diagram: MermaidDiagram) throws(MermaidDiagramPreparationFailure) -> PreparedMermaidDiagram {
        switch diagram {
        case .flowchart(let flowchart): try prepared(flowchart)
        case .stateDiagram(let stateDiagram): try prepared(stateDiagram)
        case .classDiagram(let classDiagram): try prepared(classDiagram)
        case .sequence(let sequence): try prepared(sequence)
        case .entityRelationship(let entityRelationship): try prepared(entityRelationship)
        case .gitGraph(let gitGraph): try prepared(gitGraph)
        case .mindmap(let mindmap): prepared(mindmap)
        case .timeline(let timeline): prepared(timeline)
        case .pieChart(let chart): prepared(chart)
        case .ganttChart(let chart): try prepared(chart)
        case .userJourney(let journey): prepared(journey)
        case .quadrantChart(let chart): prepared(chart)
        case .xyChart(let chart): try prepared(chart)
        case .sankey(let sankey): try prepared(sankey)
        case .kanban(let board): prepared(board)
        case .treeView(let tree): prepared(tree)
        case .ishikawa(let ishikawa): prepared(ishikawa)
        case .info(let info): prepared(info)
        case .packet(let packet): prepared(packet)
        case .radar(let radar): prepared(radar)
        case .treemap(let treemap): prepared(treemap)
        case .venn(let venn): try prepared(venn)
        case .cynefin(let cynefin): prepared(cynefin)
        case .wardleyMap(let map): prepared(map)
        case .eventModel(let eventModel): prepared(eventModel)
        case .railroad(let railroad): prepared(railroad)
        case .c4(let c4): try prepared(c4)
        case .block(let block): try prepared(block)
        case .architecture(let architecture): prepared(architecture)
        }
    }

    /// The scene of `turned` (the diagram turned to run down) laid out for a narrow column, when the regular layout is
    /// within the drawing limit and wider than the narrowest column, and the turned one is narrower than it and within the
    /// limit; else nil, and nothing is laid out a second time. A regular layout beyond the limit is refused whatever the
    /// narrow one would be, so it is not laid out again. A turned diagram whose layout fails keeps its regular layout alone.
    func narrowScene<Diagram, Layout>(of turned: Diagram?, regularSize: CGSize, laidOut: (Diagram) throws -> Layout,
                                      scene: (Layout) -> DiagramScene) -> DiagramScene? {
        guard let narrowestColumnWidth, regularSize.width > narrowestColumnWidth, limits.allowsDrawing(regularSize), let turned,
              let layout = try? laidOut(turned) else { return nil }
        let narrow = scene(layout)
        guard narrow.size.width < regularSize.width, limits.allowsDrawing(narrow.size) else { return nil }
        return narrow
    }
}
