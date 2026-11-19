/**
 * File: CynefinBenchmark.swift
 * ----------------------------
 * Layer: Benchmark
 * Description: Times reading, laying out and painting Cynefin frameworks on their documentation examples and generated
 *              frameworks, with the memory a layout holds.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics
import MermaidDiagrams

/// Times reading, laying out and painting Cynefin frameworks on `CynefinCorpus`, with the median and the 99th percentile
/// per diagram, and the memory a layout holds, as the other types' benchmarks do.
enum CynefinBenchmark {
    static func run(typography: DiagramTypography) throws {
        let cases: [(name: String, sources: [String])] = [
            ("cynefin documentation examples", try CynefinCorpus.documentationExamples()),
            ("cynefin, 12 items", [CynefinCorpus.generated(itemCount: 12)]),
            ("cynefin, 200 items", [CynefinCorpus.generated(itemCount: 200)]),
        ]
        for (name, sources) in cases { try report(name, sources: sources, typography: typography) }
        let generated = try read(CynefinCorpus.generated(itemCount: 12))
        let bytes = BenchmarkHeap.growth { CynefinLayoutEngine.layout(generated, typography: typography) }
        print("memory of one laid-out Cynefin framework, 12 items: \(bytes) bytes")
    }

    private static func report(_ name: String, sources: [String], typography: DiagramTypography) throws {
        let diagrams = try sources.map(read)
        let layouts = diagrams.map { diagram in CynefinLayoutEngine.layout(diagram, typography: typography) }
        let count = sources.count
        let measure = MermaidDiagramsBenchmark.measure
        let reading = measure(count) { for source in sources { _ = try? read(source) } } // Each read above.
        let layingOut = measure(count) { for diagram in diagrams { _ = CynefinLayoutEngine.layout(diagram, typography: typography) } }
        let scenes = measure(count) { for layout in layouts { _ = DiagramScene(layout: layout) } }
        let contexts = layouts.map { layout in MermaidDiagramsBenchmark.bitmapContext(size: layout.size) }
        let painting = measure(count) {
            for (layout, context) in zip(layouts, contexts) {
                if let context { CynefinRenderer.draw(layout, in: context, palette: MermaidDiagramsBenchmark.palette) }
            }
        }
        print("\(name): read \(reading); layout \(layingOut); scene \(scenes); painting \(painting)")
    }

    private static func read(_ source: String) throws -> CynefinDiagram {
        guard case .cynefin(let diagram) = try MermaidDiagramReader.read(source, limits: .standard) else { throw NotACynefinFramework() }
        return diagram
    }

    /// A text of the Cynefin corpus that reads as another type.
    struct NotACynefinFramework: Error {}
}
