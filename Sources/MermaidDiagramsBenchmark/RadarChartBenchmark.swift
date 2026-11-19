/**
 * File: RadarChartBenchmark.swift
 * -------------------------------
 * Layer: Benchmark
 * Description: Times reading, laying out and drawing radar charts, and the memory a layout holds.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics
import MermaidDiagrams

/// Times reading, laying out and drawing radar charts on `RadarChartCorpus`, with the median and the 99th percentile per diagram,
/// and the memory a layout holds, as the flowchart's benchmark does.
enum RadarChartBenchmark {
    static func run(typography: DiagramTypography) throws {
        let cases: [(name: String, sources: [String])] = [
            ("radar chart documentation examples", try RadarChartCorpus.documentationExamples()),
            ("radar chart, 8 axes and 4 curves", [RadarChartCorpus.generated(axisCount: 8, curveCount: 4)]),
            ("radar chart, 60 axes and 20 curves", [RadarChartCorpus.generated(axisCount: 60, curveCount: 20)]),
            ("radar chart, 300 axes and 50 curves", [RadarChartCorpus.generated(axisCount: 300, curveCount: 50)]),
        ]
        for (name, sources) in cases { try report(name, sources: sources, typography: typography) }
        let generated = try read(RadarChartCorpus.generated(axisCount: 8, curveCount: 4))
        let bytes = BenchmarkHeap.growth { RadarChartLayoutEngine.layout(generated, typography: typography) }
        print("memory of one laid-out radar chart, 8 axes and 4 curves: \(bytes) bytes")
    }

    private static func report(_ name: String, sources: [String], typography: DiagramTypography) throws {
        let diagrams = try sources.map(read)
        let layouts = diagrams.map { diagram in RadarChartLayoutEngine.layout(diagram, typography: typography) }
        let count = sources.count
        let measure = MermaidDiagramsBenchmark.measure
        let reading = measure(count) { for source in sources { _ = try? read(source) } } // Each read above.
        let layingOut = measure(count) { for diagram in diagrams { _ = RadarChartLayoutEngine.layout(diagram, typography: typography) } }
        let both = measure(count) {
            for source in sources { _ = (try? read(source)).map { diagram in RadarChartLayoutEngine.layout(diagram, typography: typography) } } // Read above.
        }
        let parts = measure(count) { for layout in layouts { _ = RadarChartDrawingParts(layout: layout) } }
        let contexts = layouts.map { layout in MermaidDiagramsBenchmark.bitmapContext(size: layout.size) }
        let painting = measure(count) {
            for (layout, context) in zip(layouts, contexts) {
                if let context { RadarChartRenderer.draw(layout, in: context, palette: MermaidDiagramsBenchmark.palette) }
            }
        }
        print("\(name): read \(reading); layout \(layingOut); read and layout \(both); drawing parts \(parts); painting \(painting)")
    }

    private static func read(_ source: String) throws -> RadarChart {
        guard case .radar(let diagram) = try MermaidDiagramReader.read(source, limits: .standard) else { throw NotARadarChart() }
        return diagram
    }

    /// A text of the radar chart corpus that reads as another type.
    struct NotARadarChart: Error {}
}
