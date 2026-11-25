/**
 * File: MermaidDiagramPreparation.swift
 * -------------------------------------
 * Layer: Core
 * Description: The one entry point that reads any diagram text, lays it out and makes its scenes and what a screen
 *              reader says of it, or says why it is not drawn.
 *
 * Authors: Bahey Shalash
 * Version: 0.8
 * Date: 24/11/2026
 */

import CoreGraphics
import Foundation

/// Reads a diagram's text, lays it out and prepares its scene, whatever its type, so that a reader needs no code of its
/// own per type. A text that is not read, a layout that refuses what it holds, a diagram that declares nothing to draw,
/// one longer than the limits' drawing side and one whose scene lost a path past its element limit are refused with why
/// (`MermaidDiagramPreparationFailure`), never an empty, a giant or an incomplete scene. Adding a type means its parser,
/// its layout, its scene, and one case in `prepare(_:)`'s switch.
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
        try refuseIncomplete(prepared.scene, limits: limits)
        return prepared
    }

    /// Refuses a scene beyond the limits' drawing side, or one that lost a path past its element limit.
    static func refuseIncomplete(_ scene: DiagramScene, limits: MermaidDiagramLimits) throws(MermaidDiagramPreparationFailure) {
        guard limits.allowsDrawing(scene.size) else { throw .tooLargeToDraw(maximumSideLength: limits.maximumDrawingSideLength) }
        if let limit = scene.exceededPathElementLimit { throw .tooManyPathElements(limit: limit) }
    }
}

/// What every type's preparation is given. Its values never change once made, and its typography's measurers read fonts
/// that never change through caches that lock (`CoreTextFontFaces`), so the work that lays a narrow scene out later, on
/// whatever thread first reads it, may hold it.
struct MermaidDiagramPreparationContext: @unchecked Sendable {
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
        case .requirement(let requirement): try prepared(requirement)
        case .swimlane(let swimlane): prepared(swimlane: swimlane)
        case .useCase(let useCase): try prepared(useCase)
        case .agentFlow(let agentFlow): try prepared(agentFlow)
        }
    }

    /// Whether a regular layout of `regularSize` may have a narrow scene: a narrowest column is asked for, the layout is
    /// wider than it and within the drawing limit. Each type asks it before it builds the work of `narrowScene`, so that a
    /// diagram with none builds no work (the closures and what they hold) either.
    func narrowSceneIsWanted(forRegularSize regularSize: CGSize) -> Bool {
        guard let narrowestColumnWidth else { return false }
        return regularSize.width > narrowestColumnWidth && limits.allowsDrawing(regularSize)
    }

    /// `narrowSceneIsWanted(forRegularSize:)` for a diagram Pele turns to run down only, which also needs the narrowest
    /// column under Pele's 640-point breakpoint (`turnedNarrowScene`).
    func turnedNarrowSceneIsWanted(forRegularSize regularSize: CGSize) -> Bool {
        guard let narrowestColumnWidth, narrowestColumnWidth < DiagramWidthFitting.defaultDirectionBreakpoint else { return false }
        return narrowSceneIsWanted(forRegularSize: regularSize)
    }

    /// The scene of `turned` (the diagram turned to run down) laid out for a narrow column, when the regular layout is
    /// within the drawing limit and wider than the narrowest column, and the turned one is narrower than it and within the
    /// limit; else nil. Nothing is laid out here: the store returned turns the diagram and lays it out the first time its
    /// scene is read (`PreparedMermaidDiagram.narrowScene`), and makes nil then where the turned layout fails or is not
    /// narrower, so a diagram whose narrow scene is never read costs no second layout. Nil (no store) when the regular
    /// layout is no wider than the narrowest column or beyond the drawing limit: a regular layout beyond the limit is
    /// refused whatever the narrow one would be. A turned diagram whose layout fails keeps its regular layout alone.
    func narrowScene<Diagram, Layout>(of turned: @autoclosure @escaping @Sendable () -> Diagram?, regularSize: CGSize,
                                      laidOut: @escaping @Sendable (Diagram) throws -> Layout,
                                      scene: @escaping @Sendable (Layout) -> DiagramScene) -> PreparedNarrowScene? {
        guard narrowSceneIsWanted(forRegularSize: regularSize) else { return nil }
        let limits = limits
        return PreparedNarrowScene {
            guard let turned = turned(), let layout = try? laidOut(turned) else { return nil }
            let narrow = scene(layout)
            guard narrow.size.width < regularSize.width, limits.allowsDrawing(narrow.size) else { return nil }
            return narrow
        }
    }

    /// The scene of `turned` for a diagram Pele turns to run down only (`turnToFit`): as `narrowScene`, and only for a
    /// column under Pele's 640-point breakpoint, past which Pele keeps a diagram across however wide it is.
    func turnedNarrowScene<Diagram, Layout>(of turned: @autoclosure @escaping @Sendable () -> Diagram?, regularSize: CGSize,
                                            laidOut: @escaping @Sendable (Diagram) throws -> Layout,
                                            scene: @escaping @Sendable (Layout) -> DiagramScene) -> PreparedNarrowScene? {
        guard turnedNarrowSceneIsWanted(forRegularSize: regularSize) else { return nil }
        return narrowScene(of: turned(), regularSize: regularSize, laidOut: laidOut, scene: scene)
    }
}
