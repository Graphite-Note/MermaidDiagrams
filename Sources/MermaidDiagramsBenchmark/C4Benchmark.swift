/**
 * File: C4Benchmark.swift
 * -----------------------
 * Layer: Benchmark
 * Description: Times reading, laying out and painting C4 diagrams on their documentation examples and generated
 *              diagrams, with the memory a layout holds.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics
import MermaidDiagrams

/// Times reading, laying out and painting C4 diagrams on `C4Corpus`, with the median and the 99th percentile per
/// diagram, and the memory a layout holds, as the other types' benchmarks do.
enum C4Benchmark {
    static func run(typography: DiagramTypography) throws {
        let cases: [(name: String, sources: [String])] = [
            ("c4 documentation examples", try C4Corpus.documentationExamples()),
            ("c4, 20 systems in 3 boundaries, 30 relations", [C4Corpus.generated(shapeCount: 20, boundaryCount: 3, relationCount: 30)]),
            ("c4, 200 systems in 10 boundaries, 300 relations", [C4Corpus.generated(shapeCount: 200, boundaryCount: 10, relationCount: 300)]),
        ]
        for (name, sources) in cases { try report(name, sources: sources, typography: typography) }
        let generated = try read(C4Corpus.generated(shapeCount: 20, boundaryCount: 3, relationCount: 30))
        let bytes = BenchmarkHeap.growth { _ = try? C4LayoutEngine.layout(generated, typography: typography) }
        print("memory of one laid-out C4 diagram, 20 systems: \(bytes) bytes")
    }

    private static func report(_ name: String, sources: [String], typography: DiagramTypography) throws {
        let diagrams = try sources.map(read)
        let layouts = try diagrams.map { diagram in try C4LayoutEngine.layout(diagram, typography: typography) }
        let count = sources.count
        let measure = MermaidDiagramsBenchmark.measure
        let reading = measure(count) { for source in sources { _ = try? read(source) } }
        let layingOut = measure(count) { for diagram in diagrams { _ = try? C4LayoutEngine.layout(diagram, typography: typography) } }
        let scenes = measure(count) { for layout in layouts { _ = DiagramScene(layout: layout) } }
        let contexts = layouts.map { layout in MermaidDiagramsBenchmark.bitmapContext(size: layout.size) }
        let painting = measure(count) {
            for (layout, context) in zip(layouts, contexts) {
                if let context { C4Renderer.draw(layout, in: context, palette: MermaidDiagramsBenchmark.palette) }
            }
        }
        print("\(name): read \(reading); layout \(layingOut); scene \(scenes); painting \(painting)")
    }

    private static func read(_ source: String) throws -> C4Diagram {
        guard case .c4(let diagram) = try MermaidDiagramReader.read(source, limits: .standard) else { throw NotAC4Diagram() }
        return diagram
    }

    /// A text of the C4 corpus that reads as another type.
    struct NotAC4Diagram: Error {}
}
