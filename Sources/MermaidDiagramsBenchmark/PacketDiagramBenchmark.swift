/**
 * File: PacketDiagramBenchmark.swift
 * ----------------------------------
 * Layer: Benchmark
 * Description: Times reading, laying out and drawing packet diagrams, and the memory a layout holds.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics
import MermaidDiagrams

/// Times reading, laying out and drawing packet diagrams on `PacketDiagramCorpus`, with the median and the 99th percentile per diagram,
/// and the memory a layout holds, as the flowchart's benchmark does.
enum PacketDiagramBenchmark {
    static func run(typography: DiagramTypography) throws {
        let cases: [(name: String, sources: [String])] = [
            ("packet diagram documentation examples", try PacketDiagramCorpus.documentationExamples()),
            ("packet diagram, 20 fields", [PacketDiagramCorpus.generated(fieldCount: 20)]),
            ("packet diagram, 300 fields", [PacketDiagramCorpus.generated(fieldCount: 300)]),
            ("packet diagram, 1,000 fields", [PacketDiagramCorpus.generated(fieldCount: 1_000)]),
        ]
        for (name, sources) in cases { try report(name, sources: sources, typography: typography) }
        let generated = try read(PacketDiagramCorpus.generated(fieldCount: 20))
        let bytes = BenchmarkHeap.growth { PacketDiagramLayoutEngine.layout(generated, typography: typography) }
        print("memory of one laid-out packet diagram, 20 fields: \(bytes) bytes")
    }

    private static func report(_ name: String, sources: [String], typography: DiagramTypography) throws {
        let diagrams = try sources.map(read)
        let layouts = diagrams.map { diagram in PacketDiagramLayoutEngine.layout(diagram, typography: typography) }
        let count = sources.count
        let measure = MermaidDiagramsBenchmark.measure
        let reading = measure(count) { for source in sources { _ = try? read(source) } } // Each read above.
        let layingOut = measure(count) { for diagram in diagrams { _ = PacketDiagramLayoutEngine.layout(diagram, typography: typography) } }
        let both = measure(count) {
            for source in sources { _ = (try? read(source)).map { diagram in PacketDiagramLayoutEngine.layout(diagram, typography: typography) } } // Read above.
        }
        let parts = measure(count) { for layout in layouts { _ = PacketDiagramDrawingParts(layout: layout) } }
        let contexts = layouts.map { layout in MermaidDiagramsBenchmark.bitmapContext(size: layout.size) }
        let painting = measure(count) {
            for (layout, context) in zip(layouts, contexts) {
                if let context { PacketDiagramRenderer.draw(layout, in: context, palette: MermaidDiagramsBenchmark.palette) }
            }
        }
        print("\(name): read \(reading); layout \(layingOut); read and layout \(both); drawing parts \(parts); painting \(painting)")
    }

    private static func read(_ source: String) throws -> PacketDiagram {
        guard case .packet(let diagram) = try MermaidDiagramReader.read(source, limits: .standard) else { throw NotAPacketDiagram() }
        return diagram
    }

    /// A text of the packet diagram corpus that reads as another type.
    struct NotAPacketDiagram: Error {}
}
