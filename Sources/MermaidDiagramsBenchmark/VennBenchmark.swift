/**
 * File: VennBenchmark.swift
 * -------------------------
 * Layer: Benchmark
 * Description: Times reading, laying out and painting Venn diagrams on their documentation examples and generated
 *              diagrams, with the memory a layout holds.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics
import MermaidDiagrams

/// Times reading, laying out and painting Venn diagrams on `VennCorpus`, with the median and the 99th percentile per
/// diagram, and the memory a layout holds, as the other types' benchmarks do.
enum VennBenchmark {
    static func run(typography: DiagramTypography) throws {
        let cases: [(name: String, sources: [String])] = [
            ("venn documentation examples", try VennCorpus.documentationExamples()),
            ("venn, 6 sets", [VennCorpus.generated(setCount: 6)]),
            ("venn, 40 sets", [VennCorpus.generated(setCount: 40)]),
            ("venn, 200 sets", [VennCorpus.generated(setCount: 200)]),
        ]
        for (name, sources) in cases { try report(name, sources: sources, typography: typography) }
        let generated = try read(VennCorpus.generated(setCount: 6))
        let bytes = BenchmarkHeap.growth { try? VennLayoutEngine.layout(generated, typography: typography) }
        print("memory of one laid-out Venn diagram, 6 sets: \(bytes) bytes")
    }

    private static func report(_ name: String, sources: [String], typography: DiagramTypography) throws {
        let diagrams = try sources.map(read)
        let layouts = try diagrams.map { diagram in try VennLayoutEngine.layout(diagram, typography: typography) }
        let count = sources.count
        let measure = MermaidDiagramsBenchmark.measure
        let reading = measure(count) { for source in sources { _ = try? read(source) } } // Each read above.
        let layingOut = measure(count) { for diagram in diagrams { _ = try? VennLayoutEngine.layout(diagram, typography: typography) } }
        let scenes = measure(count) { for layout in layouts { _ = DiagramScene(layout: layout) } }
        let contexts = layouts.map { layout in MermaidDiagramsBenchmark.bitmapContext(size: layout.size) }
        let painting = measure(count) {
            for (layout, context) in zip(layouts, contexts) {
                if let context { VennRenderer.draw(layout, in: context, palette: MermaidDiagramsBenchmark.palette) }
            }
        }
        print("\(name): read \(reading); layout \(layingOut); scene \(scenes); painting \(painting)")
    }

    private static func read(_ source: String) throws -> VennDiagram {
        guard case .venn(let diagram) = try MermaidDiagramReader.read(source, limits: .standard) else { throw NotAVennDiagram() }
        return diagram
    }

    /// A text of the Venn corpus that reads as another type.
    struct NotAVennDiagram: Error {}
}
