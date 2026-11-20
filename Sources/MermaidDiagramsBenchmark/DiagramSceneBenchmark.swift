/**
 * File: DiagramSceneBenchmark.swift
 * ---------------------------------
 * Layer: Benchmark
 * Description: Times, per diagram type on its documentation examples, reading and laying out, making the scene from the
 *              layout, the whole preparation with and without its narrow layout, painting the scene and writing its SVG.
 *
 * Authors: Bahey Shalash
 * Version: 0.7
 * Date: 19/11/2026
 */

import CoreGraphics
import Foundation
import MermaidDiagrams

/// Times what the scene adds to reading and laying out, per type on its documentation examples (and the Sankey energy
/// flows): read and layout once, the scene made from a kept layout, the whole preparation (read, layout, scene and what a
/// screen reader says) without a narrow layout and with the default narrowest column, as Graphite calls it, the scene painted into a bitmap at two pixels per point, and its SVG
/// written with Pele's variables.
enum DiagramSceneBenchmark {
    /// One diagram laid out, and how to make its scene from that layout.
    struct LaidOut {
        let scene: () -> DiagramScene
    }

    static func run(typography: DiagramTypography) throws {
        let corpora: [(MermaidDiagramKind, [String])] = [
            (.flowchart, try FlowchartCorpus.documentationExamples()), (.stateDiagram, try StateDiagramCorpus.documentationExamples()),
            (.classDiagram, try ClassDiagramCorpus.documentationExamples()), (.sequence, try SequenceCorpus.documentationExamples()),
            (.entityRelationship, try EntityRelationshipCorpus.documentationExamples()), (.mindmap, try MindmapCorpus.documentationExamples()),
            (.timeline, try TimelineCorpus.documentationExamples()), (.pieChart, try PieChartCorpus.documentationExamples()),
            (.ganttChart, try GanttChartCorpus.documentationExamples()), (.gitGraph, try GitGraphCorpus.documentationExamples()),
            (.userJourney, try UserJourneyCorpus.documentationExamples()), (.quadrantChart, try QuadrantChartCorpus.documentationExamples()),
            (.xyChart, try XYChartCorpus.documentationExamples()),
            (.sankey, try SankeyCorpus.documentationExamples() + ["sankey-beta\n\n " + SankeyCorpus.energyRows()]),
            (.kanban, try KanbanCorpus.documentationExamples()), (.treeView, try TreeViewCorpus.documentationExamples()),
            (.ishikawa, try IshikawaCorpus.documentationExamples()),
            (.info, try InfoDiagramCorpus.documentationExamples()), (.packet, try PacketDiagramCorpus.documentationExamples()),
            (.radar, try RadarChartCorpus.documentationExamples()), (.treemap, try TreemapCorpus.documentationExamples()),
            (.venn, try VennCorpus.documentationExamples()),
            (.cynefin, try CynefinCorpus.documentationExamples()),
            (.wardleyMap, try WardleyMapCorpus.documentationExamples()),
            (.eventModel, try EventModelCorpus.documentationExamples()),
            (.railroad, try RailroadCorpus.documentationExamples()),
            (.c4, try C4Corpus.documentationExamples()),
            (.block, try BlockCorpus.documentationExamples()),
            (.architecture, try ArchitectureCorpus.documentationExamples()),
            (.requirement, try RequirementCorpus.documentationExamples()),
            (.swimlane, try SwimlaneCorpus.documentationExamples()),
            (.agentFlow, try AgentFlowCorpus.documentationExamples()),
        ]
        for (kind, sources) in corpora { report(kind, sources: sources, typography: typography) }
    }

    private static func report(_ kind: MermaidDiagramKind, sources allSources: [String], typography: DiagramTypography) {
        let sources = allSources.filter { source in (try? read(source)).flatMap { diagram in laidOut(diagram, typography: typography) } != nil }
        guard !sources.isEmpty else { return }
        let diagrams = sources.compactMap { source in try? read(source) }
        let laidOutDiagrams = diagrams.compactMap { diagram in laidOut(diagram, typography: typography) }
        let scenes = laidOutDiagrams.map { diagram in diagram.scene() }
        let count = sources.count
        let measure = MermaidDiagramsBenchmark.measure
        let readingAndLayout = measure(count) {
            for source in sources { _ = (try? read(source)).map { diagram in laidOut(diagram, typography: typography) } }
        }
        let scene = measure(count) { for diagram in laidOutDiagrams { _ = diagram.scene() } }
        let prepare = { (narrowestColumnWidth: CGFloat?) in
            measure(count) {
                for source in sources {
                    _ = try? MermaidDiagramPreparation.prepare(source: source, typography: typography, narrowestColumnWidth: narrowestColumnWidth,
                                                               now: GanttChartCorpus.now, timeZone: GanttChartCorpus.timeZone)
                }
            }
        }
        let preparation = prepare(nil)
        let preparationWithNarrowScene = prepare(PreparedMermaidDiagram.standardNarrowestColumnWidth)
        let contexts = scenes.map { scene in MermaidDiagramsBenchmark.bitmapContext(size: scene.size) }
        let painting = measure(count) {
            for (scene, context) in zip(scenes, contexts) {
                if let context { DiagramSceneRenderer.draw(scene, in: context, palette: MermaidDiagramsBenchmark.palette) }
            }
        }
        let writer = DiagramSVGWriter()
        let svg = measure(count) { for scene in scenes { _ = writer.document(of: scene, diagramType: kind.peleName) } }
        let svgBytes = scenes.map { scene in writer.document(of: scene, diagramType: kind.peleName).utf8.count }.reduce(0, +) / count
        let itemCount = scenes.map(\.items.count).reduce(0, +) / count
        print("\(kind.peleName) scenes (\(count) examples, \(itemCount) items each): read and layout \(readingAndLayout); scene from layout \(scene); "
              + "prepared \(preparation), with the narrow layout as Graphite asks for it \(preparationWithNarrowScene); scene painting \(painting); SVG \(svg), \(svgBytes) bytes")
    }

    private static func read(_ source: String) throws -> MermaidDiagram {
        try MermaidDiagramReader.read(source, limits: .standard)
    }

    /// The diagram laid out once, or nil when its layout refuses it (also what `PeleComparisonBenchmark` times as reading
    /// and layout).
    static func laidOut(_ diagram: MermaidDiagram, typography: DiagramTypography) -> LaidOut? {
        switch diagram {
        case .flowchart(let flowchart):
            let layOut = { try FlowchartLayoutEngine.layout(flowchart, typography: typography, limits: .standard) }
            return (try? layOut()).map { layout in LaidOut { DiagramScene(layout: layout) } }
        case .stateDiagram(let state):
            let layOut = { try StateDiagramLayoutEngine.layout(state, typography: typography, limits: .standard) }
            return (try? layOut()).map { layout in LaidOut { DiagramScene(layout: layout) } }
        case .classDiagram(let classes):
            let layOut = { try ClassDiagramLayoutEngine.layout(classes, typography: typography, limits: .standard) }
            return (try? layOut()).map { layout in LaidOut { DiagramScene(layout: layout) } }
        case .sequence(let sequence):
            let layOut = { try SequenceLayoutEngine.layout(sequence, typography: typography) }
            return (try? layOut()).map { layout in LaidOut { DiagramScene(layout: layout) } }
        case .entityRelationship(let entityRelationship):
            let layOut = { try EntityRelationshipLayoutEngine.layout(entityRelationship, typography: typography, limits: .standard) }
            return (try? layOut()).map { layout in LaidOut { DiagramScene(layout: layout) } }
        case .gitGraph(let gitGraph):
            let layOut = { try GitGraphLayoutEngine.layout(gitGraph, typography: typography) }
            return (try? layOut()).map { layout in LaidOut { DiagramScene(layout: layout) } }
        case .mindmap, .timeline, .pieChart, .ganttChart, .userJourney, .quadrantChart, .xyChart, .sankey, .kanban, .treeView, .ishikawa,
             .info, .packet, .radar, .treemap, .eventModel, .railroad:
            return laidOutChart(diagram, typography: typography)
        case .venn, .cynefin, .wardleyMap:
            return laidOutPlaneMap(diagram, typography: typography)
        case .c4(let c4):
            let layOut = { try C4LayoutEngine.layout(c4, typography: typography) }
            return (try? layOut()).map { layout in LaidOut { DiagramScene(layout: layout) } }
        case .block, .architecture:
            return laidOutGridDiagram(diagram, typography: typography)
        case .requirement, .swimlane, .useCase, .agentFlow:
            return laidOutLayeredDiagram(diagram, typography: typography)
        }
    }

    /// A requirement diagram, a swimlane diagram, a use case diagram or an agent flow, the layered types added after the first graphs.
    private static func laidOutLayeredDiagram(_ diagram: MermaidDiagram, typography: DiagramTypography) -> LaidOut? {
        switch diagram {
        case .requirement(let requirement):
            let layOut = { try RequirementLayoutEngine.layout(requirement, typography: typography, limits: .standard) }
            return (try? layOut()).map { layout in LaidOut { DiagramScene(layout: layout) } }
        case .swimlane(let swimlane):
            let layout = SwimlaneLayoutEngine.layout(swimlane, typography: typography)
            return LaidOut { DiagramScene(layout: layout) }
        case .useCase(let useCase):
            let layOut = { try UseCaseLayoutEngine.layout(useCase, typography: typography) }
            return (try? layOut()).map { layout in LaidOut { DiagramScene(layout: layout) } }
        case .agentFlow(let agentFlow):
            let layOut = { try AgentFlowLayoutEngine.layout(agentFlow, typography: typography) }
            return (try? layOut()).map { layout in LaidOut { DiagramScene(layout: layout) } }
        default:
            return nil
        }
    }

    private static func laidOutChart(_ diagram: MermaidDiagram, typography: DiagramTypography) -> LaidOut? {
        switch diagram {
        case .mindmap(let mindmap):
            let layout = MindmapLayoutEngine.layout(mindmap, typography: typography)
            return LaidOut { DiagramScene(layout: layout) }
        case .timeline(let timeline):
            let layout = TimelineLayoutEngine.layout(timeline, typography: typography)
            return LaidOut { DiagramScene(layout: layout) }
        case .pieChart(let chart):
            let layout = PieChartLayoutEngine.layout(chart, typography: typography)
            return LaidOut { DiagramScene(layout: layout) }
        case .ganttChart(let chart):
            let layOut = { try GanttLayoutEngine.layout(chart, typography: typography, now: GanttChartCorpus.now, timeZone: GanttChartCorpus.timeZone,
                                                        limits: .standard) }
            return (try? layOut()).map { layout in LaidOut { DiagramScene(layout: layout) } }
        case .userJourney(let journey):
            let layout = UserJourneyLayoutEngine.layout(journey, typography: typography)
            return LaidOut { DiagramScene(layout: layout) }
        case .quadrantChart(let chart):
            let layout = QuadrantChartLayoutEngine.layout(chart, typography: typography)
            return LaidOut { DiagramScene(layout: layout) }
        case .xyChart(let chart):
            let layOut = { try XYChartLayoutEngine.layout(chart, typography: typography) }
            return (try? layOut()).map { layout in LaidOut { DiagramScene(layout: layout) } }
        case .sankey(let sankey):
            let layOut = { try SankeyLayoutEngine.layout(sankey, typography: typography) }
            return (try? layOut()).map { layout in LaidOut { DiagramScene(layout: layout) } }
        case .info, .packet, .radar, .treemap:
            return laidOutSimpleChart(diagram, typography: typography)
        case .kanban, .treeView, .ishikawa, .eventModel, .railroad:
            return laidOutOutlineOrTrackDiagram(diagram, typography: typography)
        case .flowchart, .stateDiagram, .classDiagram, .sequence, .entityRelationship, .gitGraph,
             .venn, .cynefin, .wardleyMap, .c4, .block, .architecture, .requirement, .swimlane, .useCase, .agentFlow:
            return nil
        }
    }

    /// A kanban board, tree view or Ishikawa diagram (an indented outline), or an event model or railroad diagram (tracks).
    private static func laidOutOutlineOrTrackDiagram(_ diagram: MermaidDiagram, typography: DiagramTypography) -> LaidOut? {
        switch diagram {
        case .kanban(let board):
            let layout = KanbanLayoutEngine.layout(board, typography: typography)
            return LaidOut { DiagramScene(layout: layout) }
        case .treeView(let tree):
            let layout = TreeViewLayoutEngine.layout(tree, typography: typography)
            return LaidOut { DiagramScene(layout: layout) }
        case .ishikawa(let diagram):
            let layout = IshikawaLayoutEngine.layout(diagram, typography: typography)
            return LaidOut { DiagramScene(layout: layout) }
        case .eventModel(let eventModel):
            let layout = EventModelLayoutEngine.layout(eventModel, typography: typography)
            return LaidOut { DiagramScene(layout: layout) }
        case .railroad(let railroad):
            let layout = RailroadLayoutEngine.layout(railroad, typography: typography)
            return LaidOut { DiagramScene(layout: layout) }
        default:
            return nil
        }
    }

    /// A diagram drawn on a fixed plane laid out once: a Venn diagram, a Cynefin framework or a Wardley map.
    private static func laidOutPlaneMap(_ diagram: MermaidDiagram, typography: DiagramTypography) -> LaidOut? {
        switch diagram {
        case .venn(let venn):
            let layOut = { try VennLayoutEngine.layout(venn, typography: typography) }
            return (try? layOut()).map { layout in LaidOut { DiagramScene(layout: layout) } }
        case .cynefin(let cynefin):
            let layout = CynefinLayoutEngine.layout(cynefin, typography: typography)
            return LaidOut { DiagramScene(layout: layout) }
        case .wardleyMap(let map):
            let layout = WardleyMapLayoutEngine.layout(map, typography: typography)
            return LaidOut { DiagramScene(layout: layout) }
        default:
            return nil
        }
    }

    /// A diagram laid out on a grid: a block diagram or an architecture diagram.
    private static func laidOutGridDiagram(_ diagram: MermaidDiagram, typography: DiagramTypography) -> LaidOut? {
        switch diagram {
        case .block(let block):
            let layOut = { try BlockLayoutEngine.layout(block, typography: typography) }
            return (try? layOut()).map { layout in LaidOut { DiagramScene(layout: layout) } }
        case .architecture(let architecture):
            let layout = ArchitectureLayoutEngine.layout(architecture, typography: typography)
            return LaidOut { DiagramScene(layout: layout) }
        default:
            return nil
        }
    }

    private static func laidOutSimpleChart(_ diagram: MermaidDiagram, typography: DiagramTypography) -> LaidOut? {
        switch diagram {
        case .info(let info):
            let layout = InfoDiagramLayoutEngine.layout(info, typography: typography)
            return LaidOut { DiagramScene(layout: layout) }
        case .packet(let packet):
            let layout = PacketDiagramLayoutEngine.layout(packet, typography: typography)
            return LaidOut { DiagramScene(layout: layout) }
        case .radar(let radar):
            let layout = RadarChartLayoutEngine.layout(radar, typography: typography)
            return LaidOut { DiagramScene(layout: layout) }
        case .treemap(let treemap):
            let layout = TreemapLayoutEngine.layout(treemap, typography: typography)
            return LaidOut { DiagramScene(layout: layout) }
        default:
            return nil
        }
    }
}
