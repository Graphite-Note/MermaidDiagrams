/**
 * File: LayeredDiagramBenchmarks.swift
 * ------------------------------------
 * Layer: Benchmark
 * Description: Times reading, laying out and drawing requirement diagrams and swimlane diagrams on Mermaid's
 *              documentation examples and generated diagrams.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

import CoreGraphics
import MermaidDiagrams

/// Times requirement diagrams (`RequirementCorpus`) and swimlane diagrams (`SwimlaneCorpus`), with the median and the 99th
/// percentile per diagram, as the flowchart's benchmark does: reading, the layout, the narrow layout (a requirement diagram
/// turned to run down, a swimlane diagram turned and tight for a column of 280 points), the drawing parts and painting.
enum LayeredDiagramBenchmarks {
    static func run(typography: DiagramTypography) throws {
        let requirementCases: [(String, [String])] = [
            ("requirement documentation examples", try RequirementCorpus.documentationExamples()),
            ("requirement diagram, 30 requirements", [RequirementCorpus.generated(requirementCount: 30)]),
            ("requirement diagram, 200 requirements", [RequirementCorpus.generated(requirementCount: 200, direction: "LR")]),
        ]
        for (name, sources) in requirementCases { try reportRequirements(name, sources: sources, typography: typography) }
        let swimlaneCases: [(String, [String])] = [
            ("swimlane documentation examples", try SwimlaneCorpus.documentationExamples()),
            ("swimlane process, 4 lanes and 40 steps", [SwimlaneCorpus.process(laneCount: 4, stepCount: 40)]),
            ("swimlane process, 10 lanes and 400 steps", [SwimlaneCorpus.process(laneCount: 10, stepCount: 400)]),
        ]
        for (name, sources) in swimlaneCases { try reportSwimlanes(name, sources: sources, typography: typography) }
    }

    private static func reportRequirements(_ name: String, sources: [String], typography: DiagramTypography) throws {
        let diagrams: [RequirementDiagram] = try sources.map { source in
            guard case .requirement(let diagram) = try MermaidDiagramReader.read(source, limits: .standard) else { throw NotOfTheType() }
            return diagram
        }
        let layOut = { (diagram: RequirementDiagram) in try? RequirementLayoutEngine.layout(diagram, typography: typography, limits: .standard) }
        let layouts = diagrams.compactMap(layOut)
        let measure = MermaidDiagramsBenchmark.measure
        let count = sources.count
        let reading = measure(count) { for source in sources { _ = try? MermaidDiagramReader.read(source, limits: .standard) } }
        let layingOut = measure(count) { for diagram in diagrams { _ = layOut(diagram) } }
        let narrow = measure(count) { for diagram in diagrams { _ = layOut(diagram.turnedToRunDown ?? diagram) } }
        let parts = measure(count) { for layout in layouts { _ = RequirementDrawingParts(layout: layout) } }
        let painting = paint(layouts.map { layout in DiagramScene(layout: layout) })
        print("\(name): read \(reading); layout \(layingOut); narrow layout \(narrow); drawing parts \(parts); painting \(painting)")
    }

    private static func reportSwimlanes(_ name: String, sources: [String], typography: DiagramTypography) throws {
        let diagrams: [FlowchartDiagram] = try sources.map { source in
            guard case .swimlane(let diagram) = try MermaidDiagramReader.read(source, limits: .standard) else { throw NotOfTheType() }
            return diagram
        }
        let layouts = diagrams.map { diagram in SwimlaneLayoutEngine.layout(diagram, typography: typography) }
        let measure = MermaidDiagramsBenchmark.measure
        let count = sources.count
        let reading = measure(count) { for source in sources { _ = try? MermaidDiagramReader.read(source, limits: .standard) } }
        let layingOut = measure(count) { for diagram in diagrams { _ = SwimlaneLayoutEngine.layout(diagram, typography: typography) } }
        let narrow = measure(count) {
            for diagram in diagrams {
                _ = SwimlaneLayoutEngine.layout(diagram.swimlaneTurnedToRunDown ?? diagram, typography: typography, spacing: .compact, columnWidth: 280)
            }
        }
        let parts = measure(count) { for layout in layouts { _ = SwimlaneDrawingParts(layout: layout) } }
        let painting = paint(layouts.map { layout in DiagramScene(layout: layout) })
        print("\(name): read \(reading); layout \(layingOut); narrow layout \(narrow); drawing parts \(parts); painting \(painting)")
    }

    /// The time to paint each scene into a bitmap of its size.
    private static func paint(_ scenes: [DiagramScene]) -> String {
        let contexts = scenes.map { scene in MermaidDiagramsBenchmark.bitmapContext(size: scene.size) }
        return MermaidDiagramsBenchmark.measure(perDiagramOf: scenes.count) {
            for (scene, context) in zip(scenes, contexts) {
                if let context { DiagramSceneRenderer.draw(scene, in: context, palette: MermaidDiagramsBenchmark.palette) }
            }
        }
    }

    /// A text of the corpus that reads as another type.
    struct NotOfTheType: Error {}
}
