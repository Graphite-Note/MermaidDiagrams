/**
 * File: UseCaseBenchmark.swift
 * ----------------------------
 * Layer: Benchmark
 * Description: Times reading, laying out and painting use case diagrams, with the memory a layout holds.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics
import MermaidDiagrams

/// Times reading, laying out and painting use case diagrams on `UseCaseCorpus`, with the median and the 99th
/// percentile per diagram, and the memory a layout holds, as the other types' benchmarks do.
enum UseCaseBenchmark {
    static func run(typography: DiagramTypography) throws {
        let cases: [(name: String, sources: [String])] = [
            ("usecase documentation examples", try UseCaseCorpus.documentationExamples()),
            ("usecase, 5 actors, 20 use cases in 3 boundaries, 30 relationships",
             [UseCaseCorpus.generated(actorCount: 5, useCaseCount: 20, boundaryCount: 3, relationshipCount: 30)]),
            ("usecase, 20 actors, 200 use cases in 10 boundaries, 300 relationships",
             [UseCaseCorpus.generated(actorCount: 20, useCaseCount: 200, boundaryCount: 10, relationshipCount: 300)]),
        ]
        for (name, sources) in cases { try report(name, sources: sources, typography: typography) }
        let generated = try read(UseCaseCorpus.generated(actorCount: 5, useCaseCount: 20, boundaryCount: 3, relationshipCount: 30))
        let bytes = BenchmarkHeap.growth { _ = try? UseCaseLayoutEngine.layout(generated, typography: typography) }
        print("memory of one laid-out use case diagram, 25 elements: \(bytes) bytes")
    }

    private static func report(_ name: String, sources: [String], typography: DiagramTypography) throws {
        let diagrams = try sources.map(read)
        let layouts = try diagrams.map { diagram in try UseCaseLayoutEngine.layout(diagram, typography: typography) }
        let count = sources.count
        let measure = MermaidDiagramsBenchmark.measure
        let reading = measure(count) { for source in sources { _ = try? read(source) } }
        let layingOut = measure(count) { for diagram in diagrams { _ = try? UseCaseLayoutEngine.layout(diagram, typography: typography) } }
        let scenes = measure(count) { for layout in layouts { _ = DiagramScene(layout: layout) } }
        let contexts = layouts.map { layout in MermaidDiagramsBenchmark.bitmapContext(size: layout.size) }
        let painting = measure(count) {
            for (layout, context) in zip(layouts, contexts) {
                if let context { UseCaseRenderer.draw(layout, in: context, palette: MermaidDiagramsBenchmark.palette) }
            }
        }
        print("\(name): read \(reading); layout \(layingOut); scene \(scenes); painting \(painting)")
    }

    private static func read(_ source: String) throws -> UseCaseDiagram {
        guard case .useCase(let diagram) = try MermaidDiagramReader.read(source, limits: .standard) else { throw NotAUseCaseDiagram() }
        return diagram
    }

    /// A text of the use case corpus that reads as another type.
    struct NotAUseCaseDiagram: Error {}
}
