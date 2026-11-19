/**
 * File: InfoDiagramBenchmark.swift
 * --------------------------------
 * Layer: Benchmark
 * Description: Times reading, laying out and drawing info diagrams, and the memory a layout holds.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics
import MermaidDiagrams

/// Times reading, laying out and drawing info diagrams on `InfoDiagramCorpus`, with the median and the 99th percentile per diagram,
/// and the memory a layout holds, as the flowchart's benchmark does.
enum InfoDiagramBenchmark {
    static func run(typography: DiagramTypography) throws {
        let cases: [(name: String, sources: [String])] = [
            ("info diagram documentation examples", try InfoDiagramCorpus.documentationExamples()),
            ("info diagram with titles", [InfoDiagramCorpus.titled]),
        ]
        for (name, sources) in cases { try report(name, sources: sources, typography: typography) }
        let generated = try read(InfoDiagramCorpus.titled)
        let bytes = BenchmarkHeap.growth { InfoDiagramLayoutEngine.layout(generated, typography: typography) }
        print("memory of one laid-out info diagram, with titles: \(bytes) bytes")
    }

    private static func report(_ name: String, sources: [String], typography: DiagramTypography) throws {
        let diagrams = try sources.map(read)
        let layouts = diagrams.map { diagram in InfoDiagramLayoutEngine.layout(diagram, typography: typography) }
        let count = sources.count
        let measure = MermaidDiagramsBenchmark.measure
        let reading = measure(count) { for source in sources { _ = try? read(source) } } // Each read above.
        let layingOut = measure(count) { for diagram in diagrams { _ = InfoDiagramLayoutEngine.layout(diagram, typography: typography) } }
        let both = measure(count) {
            for source in sources { _ = (try? read(source)).map { diagram in InfoDiagramLayoutEngine.layout(diagram, typography: typography) } } // Read above.
        }
        let contexts = layouts.map { layout in MermaidDiagramsBenchmark.bitmapContext(size: layout.size) }
        let painting = measure(count) {
            for (layout, context) in zip(layouts, contexts) {
                if let context { InfoDiagramRenderer.draw(layout, in: context, palette: MermaidDiagramsBenchmark.palette) }
            }
        }
        print("\(name): read \(reading); layout \(layingOut); read and layout \(both); painting \(painting)")
    }

    private static func read(_ source: String) throws -> InfoDiagram {
        guard case .info(let diagram) = try MermaidDiagramReader.read(source, limits: .standard) else { throw NotAnInfoDiagram() }
        return diagram
    }

    /// A text of the info diagram corpus that reads as another type.
    struct NotAnInfoDiagram: Error {}
}
