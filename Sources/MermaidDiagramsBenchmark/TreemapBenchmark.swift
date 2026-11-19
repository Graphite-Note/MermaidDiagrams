/**
 * File: TreemapBenchmark.swift
 * ----------------------------
 * Layer: Benchmark
 * Description: Times reading, laying out and drawing treemaps, and the memory a layout holds.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics
import MermaidDiagrams

/// Times reading, laying out and drawing treemaps on `TreemapCorpus`, with the median and the 99th percentile per diagram,
/// and the memory a layout holds, as the flowchart's benchmark does.
enum TreemapBenchmark {
    static func run(typography: DiagramTypography) throws {
        let cases: [(name: String, sources: [String])] = [
            ("treemap documentation examples", try TreemapCorpus.documentationExamples()),
            ("treemap, 64 leaves", [TreemapCorpus.generated(leafCount: 64)]),
            ("treemap, 500 leaves", [TreemapCorpus.generated(leafCount: 500)]),
            ("treemap, 2,000 leaves", [TreemapCorpus.generated(leafCount: 2_000)]),
        ]
        for (name, sources) in cases { try report(name, sources: sources, typography: typography) }
        let generated = try read(TreemapCorpus.generated(leafCount: 64))
        let bytes = BenchmarkHeap.growth { TreemapLayoutEngine.layout(generated, typography: typography) }
        print("memory of one laid-out treemap, 64 leaves: \(bytes) bytes")
    }

    private static func report(_ name: String, sources: [String], typography: DiagramTypography) throws {
        let diagrams = try sources.map(read)
        let layouts = diagrams.map { diagram in TreemapLayoutEngine.layout(diagram, typography: typography) }
        let count = sources.count
        let measure = MermaidDiagramsBenchmark.measure
        let reading = measure(count) { for source in sources { _ = try? read(source) } } // Each read above.
        let layingOut = measure(count) { for diagram in diagrams { _ = TreemapLayoutEngine.layout(diagram, typography: typography) } }
        let both = measure(count) {
            for source in sources { _ = (try? read(source)).map { diagram in TreemapLayoutEngine.layout(diagram, typography: typography) } } // Read above.
        }
        let parts = measure(count) { for layout in layouts { _ = TreemapDrawingParts(layout: layout) } }
        let contexts = layouts.map { layout in MermaidDiagramsBenchmark.bitmapContext(size: layout.size) }
        let painting = measure(count) {
            for (layout, context) in zip(layouts, contexts) {
                if let context { TreemapRenderer.draw(layout, in: context, palette: MermaidDiagramsBenchmark.palette) }
            }
        }
        print("\(name): read \(reading); layout \(layingOut); read and layout \(both); drawing parts \(parts); painting \(painting)")
    }

    private static func read(_ source: String) throws -> TreemapDiagram {
        guard case .treemap(let diagram) = try MermaidDiagramReader.read(source, limits: .standard) else { throw NotATreemap() }
        return diagram
    }

    /// A text of the treemap corpus that reads as another type.
    struct NotATreemap: Error {}
}
