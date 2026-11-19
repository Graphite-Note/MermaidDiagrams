/**
 * File: RailroadBenchmark.swift
 * -----------------------------
 * Layer: Benchmark
 * Description: Times reading, laying out and drawing railroad diagrams on Mermaid's documentation examples and
 *              generated grammars.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics
import MermaidDiagrams

/// Times reading, laying out and drawing railroad diagrams on `RailroadCorpus`, with the median and the 99th percentile per diagram,
/// and the memory a layout holds, as the flowchart's benchmark does; the narrow layout is the tight one for a column of 280 points.
enum RailroadBenchmark {
    static func run(typography: DiagramTypography) throws {
        let cases: [(name: String, sources: [String])] = [
            ("railroad documentation examples", try RailroadCorpus.documentationExamples()),
            ("railroad, 20 rules", [RailroadCorpus.generated(ruleCount: 20)]),
            ("railroad, 200 rules", [RailroadCorpus.generated(ruleCount: 200)]),
        ]
        for (name, sources) in cases { try report(name, sources: sources, typography: typography) }
        let generated = try read(RailroadCorpus.generated(ruleCount: 20))
        let bytes = BenchmarkHeap.growth { RailroadLayoutEngine.layout(generated, typography: typography) }
        print("memory of one laid-out railroad diagram, 20 rules: \(bytes) bytes")
    }

    private static func report(_ name: String, sources: [String], typography: DiagramTypography) throws {
        let diagrams = try sources.map(read)
        let layouts = diagrams.map { diagram in RailroadLayoutEngine.layout(diagram, typography: typography) }
        let count = sources.count
        let measure = MermaidDiagramsBenchmark.measure
        let reading = measure(count) { for source in sources { _ = try? read(source) } } // Each read above.
        let layingOut = measure(count) { for diagram in diagrams { _ = RailroadLayoutEngine.layout(diagram, typography: typography) } }
        let narrow = measure(count) { for diagram in diagrams { _ = RailroadLayoutEngine.layout(diagram, typography: typography, columnWidth: 280) } }
        let both = measure(count) {
            for source in sources { _ = (try? read(source)).map { diagram in RailroadLayoutEngine.layout(diagram, typography: typography) } } // Read above.
        }
        let parts = measure(count) { for layout in layouts { _ = RailroadDrawingParts(layout: layout) } }
        let contexts = layouts.map { layout in MermaidDiagramsBenchmark.bitmapContext(size: layout.size) }
        let painting = measure(count) {
            for (layout, context) in zip(layouts, contexts) {
                if let context { RailroadRenderer.draw(layout, in: context, palette: MermaidDiagramsBenchmark.palette) }
            }
        }
        print("\(name): read \(reading); layout \(layingOut); narrow layout \(narrow); read and layout \(both); drawing parts \(parts); painting \(painting)")
    }

    private static func read(_ source: String) throws -> RailroadDiagram {
        guard case .railroad(let diagram) = try MermaidDiagramReader.read(source, limits: .standard) else { throw NotARailroad() }
        return diagram
    }

    /// A text of the corpus that reads as another type.
    struct NotARailroad: Error {}
}
