/**
 * File: DiagramSceneBenchmark.swift
 * ---------------------------------
 * Layer: Benchmark
 * Description: Times, per diagram type on its documentation examples, reading and laying out, making the scene from the
 *              layout, the whole preparation, painting the scene and writing its SVG.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics
import Foundation
import MermaidDiagrams

/// Times what the scene adds to reading and laying out, per type on its documentation examples (and the Sankey energy
/// flows): read and layout once, the scene made from a kept layout, the whole preparation (read, layout, scene and what a
/// screen reader says, without a narrow layout), the scene painted into a bitmap at two pixels per point, and its SVG
/// written with Pele's variables.
enum DiagramSceneBenchmark {
    /// One diagram laid out, and how to make its scene from that layout.
    private struct LaidOut {
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
        let preparation = measure(count) {
            for source in sources {
                _ = try? MermaidDiagramPreparation.prepare(source: source, typography: typography, narrowestColumnWidth: nil, now: GanttChartCorpus.now,
                                                           timeZone: GanttChartCorpus.timeZone)
            }
        }
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
              + "prepared \(preparation); scene painting \(painting); SVG \(svg), \(svgBytes) bytes")
    }

    private static func read(_ source: String) throws -> MermaidDiagram {
        try MermaidDiagramReader.read(source, limits: .standard)
    }

    /// The diagram laid out once, or nil when its layout refuses it.
    private static func laidOut(_ diagram: MermaidDiagram, typography: DiagramTypography) -> LaidOut? {
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
        case .mindmap, .timeline, .pieChart, .ganttChart, .userJourney, .quadrantChart, .xyChart, .sankey:
            return laidOutChart(diagram, typography: typography)
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
        case .flowchart, .stateDiagram, .classDiagram, .sequence, .entityRelationship, .gitGraph:
            return nil
        }
    }
}
