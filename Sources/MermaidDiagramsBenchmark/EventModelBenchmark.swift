/**
 * File: EventModelBenchmark.swift
 * -------------------------------
 * Layer: Benchmark
 * Description: Times reading, laying out and drawing event models on Mermaid's documentation examples and generated
 *              models.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics
import MermaidDiagrams

/// Times reading, laying out and drawing event models on `EventModelCorpus`, with the median and the 99th percentile per diagram,
/// and the memory a layout holds, as the flowchart's benchmark does; the narrow layout is the model down a column of 280 points.
enum EventModelBenchmark {
    static func run(typography: DiagramTypography) throws {
        let cases: [(name: String, sources: [String])] = [
            ("event model documentation examples", try EventModelCorpus.documentationExamples()),
            ("event model, 50 frames", [EventModelCorpus.generated(frameCount: 50)]),
            ("event model, 500 frames", [EventModelCorpus.generated(frameCount: 500)]),
        ]
        for (name, sources) in cases { try report(name, sources: sources, typography: typography) }
        let generated = try read(EventModelCorpus.generated(frameCount: 50))
        let bytes = BenchmarkHeap.growth { EventModelLayoutEngine.layout(generated, typography: typography) }
        print("memory of one laid-out event model, 50 frames: \(bytes) bytes")
    }

    private static func report(_ name: String, sources: [String], typography: DiagramTypography) throws {
        let diagrams = try sources.map(read)
        let layouts = diagrams.map { diagram in EventModelLayoutEngine.layout(diagram, typography: typography) }
        let count = sources.count
        let measure = MermaidDiagramsBenchmark.measure
        let reading = measure(count) { for source in sources { _ = try? read(source) } } // Each read above.
        let layingOut = measure(count) { for diagram in diagrams { _ = EventModelLayoutEngine.layout(diagram, typography: typography) } }
        let narrow = measure(count) { for diagram in diagrams { _ = EventModelLayoutEngine.layout(diagram, typography: typography, columnWidth: 280) } }
        let both = measure(count) {
            for source in sources { _ = (try? read(source)).map { diagram in EventModelLayoutEngine.layout(diagram, typography: typography) } } // Read above.
        }
        let parts = measure(count) { for layout in layouts { _ = EventModelDrawingParts(layout: layout) } }
        let contexts = layouts.map { layout in MermaidDiagramsBenchmark.bitmapContext(size: layout.size) }
        let painting = measure(count) {
            for (layout, context) in zip(layouts, contexts) {
                if let context { EventModelRenderer.draw(layout, in: context, palette: MermaidDiagramsBenchmark.palette) }
            }
        }
        print("\(name): read \(reading); layout \(layingOut); narrow layout \(narrow); read and layout \(both); drawing parts \(parts); painting \(painting)")
    }

    private static func read(_ source: String) throws -> EventModelDiagram {
        guard case .eventModel(let diagram) = try MermaidDiagramReader.read(source, limits: .standard) else { throw NotAEventModel() }
        return diagram
    }

    /// A text of the corpus that reads as another type.
    struct NotAEventModel: Error {}
}
