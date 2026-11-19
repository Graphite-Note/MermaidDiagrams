/**
 * File: GridDiagramBenchmarks.swift
 * ---------------------------------
 * Layer: Benchmark
 * Description: Times reading, laying out, making the scene of and painting block diagrams and architecture diagrams
 *              on their corpora, with the median and 99th percentile per diagram and the memory a layout holds.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics
import MermaidDiagrams

/// Times block diagrams on `BlockCorpus`, as the other types' benchmarks do.
enum BlockBenchmark {
    static func run(typography: DiagramTypography) throws {
        let cases: [(name: String, sources: [String])] = [
            ("block documentation examples", try BlockCorpus.documentationExamples()),
            ("block, 60 blocks", [BlockCorpus.grid(blockCount: 60)]),
            ("block, 600 blocks", [BlockCorpus.grid(blockCount: 600)]),
        ]
        for (name, sources) in cases {
            let diagrams = try sources.map(read)
            let layOut = { (diagram: BlockDiagram) in try? BlockLayoutEngine.layout(diagram, typography: typography) }
            let layouts = diagrams.compactMap(layOut)
            GridDiagramTiming.report(name, count: sources.count, reading: { for source in sources { _ = try? read(source) } },
                                     layingOut: { for diagram in diagrams { _ = layOut(diagram) } },
                                     scenes: layouts.map { layout in { DiagramScene(layout: layout) } }, sizes: layouts.map(\.size))
        }
        let generated = try read(BlockCorpus.grid(blockCount: 60))
        let bytes = BenchmarkHeap.growth { try? BlockLayoutEngine.layout(generated, typography: typography) }
        print("memory of one laid-out block diagram, 60 blocks: \(bytes) bytes")
    }

    private static func read(_ source: String) throws -> BlockDiagram {
        guard case .block(let diagram) = try MermaidDiagramReader.read(source, limits: .standard) else { throw GridDiagramTiming.OtherType() }
        return diagram
    }
}

/// The timings the grid types' benchmarks print.
enum GridDiagramTiming {
    /// A text of a grid corpus that reads as another type.
    struct OtherType: Error {}

    static func report(_ name: String, count: Int, reading: () -> Void, layingOut: () -> Void, scenes: [() -> DiagramScene], sizes: [CGSize]) {
        let measure = MermaidDiagramsBenchmark.measure
        let readTime = measure(count) { reading() }
        let layoutTime = measure(count) { layingOut() }
        let sceneTime = measure(count) { for scene in scenes { _ = scene() } }
        let made = scenes.map { scene in scene() }
        let contexts = sizes.map { size in MermaidDiagramsBenchmark.bitmapContext(size: size) }
        let painting = measure(count) {
            for (scene, context) in zip(made, contexts) {
                if let context { DiagramSceneRenderer.draw(scene, in: context, palette: MermaidDiagramsBenchmark.palette) }
            }
        }
        print("\(name): read \(readTime); layout \(layoutTime); scene \(sceneTime); painting \(painting)")
    }
}
