/**
 * File: MermaidDiagramsBenchmark.swift
 * ------------------------------------
 * Layer: Benchmark
 * Description: Times reading, laying out and drawing every diagram type on Pele's benchmark inputs and Mermaid's
 *              documentation examples, the memory a layout holds, what each type's scene and SVG add, and the same
 *              inputs beside Pele's own times, checking the targets of Graphite's plan when asked; paints the README's
 *              pictures.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.11
 * Date: 23/11/2026
 */

import CoreGraphics
import Darwin
import Foundation
import MermaidDiagrams

/// Times reading, laying out and drawing flowcharts on the inputs of Pele's benchmark (`FlowchartCorpus`), and
/// sequence diagrams on Mermaid's documentation examples as Pele collects them (`SequenceCorpus`), and the memory a
/// layout holds; then every other type, what each type's scene and SVG add (`DiagramSceneBenchmark`), and last the
/// same inputs as Pele's own run on this Mac (`PeleComparisonBenchmark`). Each measurement repeats its work until about
/// 300 ms have passed (at least 5 and at most 2,000 runs, as Pele's benchmark does) and prints the median and the 99th percentile of one run, per diagram:
/// `swift run -c release --package-path Packages/MermaidDiagrams MermaidDiagramsBenchmark`.
@main
struct MermaidDiagramsBenchmark {
    static let timeBudget = Duration.milliseconds(300)
    static let minimumRunCount = 5
    static let maximumRunCount = 2_000
    /// Pele's text size.
    static let font = DiagramFont(postScriptName: nil, size: 16)
    /// How many layouts are kept while the heap's growth is measured.
    static let keptLayoutCount = 1_000

    /// `--pele-comparison` times only the comparison with Pele; `--pele-javascriptcore` times it beside Pele run in
    /// JavaScriptCore on this machine instead of Pele's run in Deno (`PeleJavaScriptCoreComparison`, what the iPad and
    /// iPhone run as an XCTest); `--check-targets` exits with status 1, after a line naming each, when a median misses a
    /// target of Graphite's plan (`PeleComparisonBenchmark`); `--profile` repeats one case for a sampler (`ProfilingLoop`);
    /// `--output-digest [folder]` prints a digest of every corpus input's output to compare two builds (`OutputDigest`);
    /// `--layout-memory` measures the heap a layout and a preparation hold per case (`LayoutMemoryBenchmark`); `--scenes`
    /// times only what each type's scene, preparation and SVG add (`DiagramSceneBenchmark`); `--readme-pictures` paints
    /// the README's pictures of every type (`ReadmePictures`).
    static func main() async throws {
        let typography = DiagramTypography(font: font)
        if let profileIndex = CommandLine.arguments.firstIndex(of: "--profile") {
            return try ProfilingLoop.run(arguments: Array(CommandLine.arguments[(profileIndex + 1)...]), typography: typography)
        }
        if let digestIndex = CommandLine.arguments.firstIndex(of: "--output-digest") {
            return try OutputDigest.run(arguments: Array(CommandLine.arguments[(digestIndex + 1)...]), typography: typography)
        }
        if let picturesIndex = CommandLine.arguments.firstIndex(of: "--readme-pictures") {
            return try ReadmePictures.run(arguments: Array(CommandLine.arguments[(picturesIndex + 1)...]), typography: typography)
        }
        let arguments = Set(CommandLine.arguments.dropFirst())
        if arguments.contains("--layout-memory") { return try LayoutMemoryBenchmark.run(typography: typography) }
        if arguments.contains("--scenes") { return try DiagramSceneBenchmark.run(typography: typography) }
        let missedTargets: [String]
        if arguments.contains("--pele-javascriptcore") {
            let report = try await PeleJavaScriptCoreComparison.run()
            for line in report.lines { print(line) }
            // A drawing unlike Deno's is not Pele's run on the Mac: the comparison does not hold.
            if !report.differingDrawings.isEmpty { exit(1) }
            missedTargets = report.missedTargets
        } else {
            if !arguments.contains("--pele-comparison") { try runEveryType(typography: typography) }
            missedTargets = try PeleComparisonBenchmark.run(typography: typography)
        }
        if arguments.contains("--check-targets") {
            for missed in missedTargets { print("missed target: \(missed)") }
            if !missedTargets.isEmpty { exit(1) }
        }
    }

    /// The flowchart's cases and memory, then every other type, the scenes and the narrow columns.
    private static func runEveryType(typography: DiagramTypography) throws {
        print("typography for one font: \(measure(perDiagramOf: 1) { _ = DiagramTypography(font: font) })")
        let documentationExamples = try FlowchartCorpus.documentationExamples()
        let drawable = documentationExamples.filter { source in (try? layout(source, typography)) != nil } // An example the layout refuses is left out.
        print("documentation examples drawn: \(drawable.count) of \(documentationExamples.count)")
        let cases: [(name: String, sources: [String])] = [
            ("documentation examples without subgraphs", drawable.filter { source in !source.contains("subgraph") }),
            ("documentation examples with subgraphs", drawable.filter { source in source.contains("subgraph") }),
            ("groups, 4 pairs of nested boxes of 5 nodes", [FlowchartCorpus.groups(pairCount: 4, nodesPerGroup: 5)]),
            ("7-node flowchart", [FlowchartCorpus.sevenNodeFlowchart]),
            ("fourteen shapes in a row", [FlowchartCorpus.fourteenShapesInARow]),
            ("fourteen shapes in a row, written to run down", [FlowchartCorpus.fourteenShapesInARow.replacingOccurrences(of: "flowchart LR", with: "flowchart TD")]),
            ("tree, 50 nodes", [FlowchartCorpus.tree(nodeCount: 50)]),
            ("mesh, 50 nodes and 20 labelled edges", [FlowchartCorpus.mesh(nodeCount: 50, extraEdgeCount: 20)]),
            ("tree, 500 nodes", [FlowchartCorpus.tree(nodeCount: 500)]),
            ("mesh, 500 nodes and 200 labelled edges", [FlowchartCorpus.mesh(nodeCount: 500, extraEdgeCount: 200)]),
        ]
        for (name, sources) in cases { try report(name, sources: sources, typography: typography) }
        for (name, source) in [("7-node flowchart", FlowchartCorpus.sevenNodeFlowchart), ("tree, 50 nodes", FlowchartCorpus.tree(nodeCount: 50)),
                               ("groups, 4 pairs", FlowchartCorpus.groups(pairCount: 4, nodesPerGroup: 5))] {
            print("memory of one laid-out \(name): \(try heapGrowthPerLayout(of: source, typography: typography)) bytes")
        }
        try runTheOtherTypes(typography: typography)
        try DiagramSceneBenchmark.run(typography: typography)
        try NarrowColumnBenchmark.run(typography: typography)
    }

    /// The benchmark of every type but the flowchart, each on its own inputs.
    private static func runTheOtherTypes(typography: DiagramTypography) throws {
        try StateDiagramBenchmark.run(typography: typography)
        try reportClassDiagrams(typography: typography)
        try reportSequenceDiagrams(typography: typography)
        try EntityRelationshipBenchmark.run(typography: typography)
        try MindmapBenchmark.run(typography: typography)
        try TimelineBenchmark.run(typography: typography)
        try PieChartBenchmark.run(typography: typography)
        try GanttChartBenchmark.run(typography: typography)
        try GitGraphBenchmark.run(typography: typography)
        try UserJourneyBenchmark.run(typography: typography)
        try QuadrantChartBenchmark.run(typography: typography)
        try XYChartBenchmark.run(typography: typography)
        try SankeyBenchmark.run(typography: typography)
        try OutlineDiagramBenchmarks.run(typography: typography)
        try SimpleChartBenchmark.run(typography: typography)
        try PlaneMapBenchmarks.run(typography: typography)
        try EventModelBenchmark.run(typography: typography)
        try RailroadBenchmark.run(typography: typography)
        try C4Benchmark.run(typography: typography)
        try BlockBenchmark.run(typography: typography)
        try ArchitectureBenchmark.run(typography: typography)
        try LayeredDiagramBenchmarks.run(typography: typography)
        try UseCaseBenchmark.run(typography: typography)
        try AgentFlowBenchmark.run(typography: typography)
    }

    private static func report(_ name: String, sources: [String], typography: DiagramTypography) throws {
        let diagrams = try sources.map(read)
        let layouts = try diagrams.map { diagram in try FlowchartLayoutEngine.layout(diagram, typography: typography, limits: .standard) }
        let count = sources.count
        let reading = measure(perDiagramOf: count) { for source in sources { _ = try? read(source) } } // Each read above.
        let layingOut = measure(perDiagramOf: count) {
            for diagram in diagrams { _ = try? FlowchartLayoutEngine.layout(diagram, typography: typography, limits: .standard) } // Laid out above.
        }
        let both = measure(perDiagramOf: count) { for source in sources { _ = try? layout(source, typography) } } // Laid out above.
        let parts = measure(perDiagramOf: count) { for layout in layouts { _ = FlowchartDrawingParts(layout: layout) } }
        let contexts = layouts.map(bitmapContext)
        let painting = measure(perDiagramOf: count) {
            for (layout, context) in zip(layouts, contexts) {
                if let context { FlowchartRenderer.draw(layout, in: context, palette: palette) }
            }
        }
        print("\(name): read \(reading); layout \(layingOut); read and layout \(both); drawing parts \(parts); painting \(painting)")
    }

    private static func read(_ source: String) throws -> FlowchartDiagram {
        guard case .flowchart(let diagram) = try MermaidDiagramReader.read(source, limits: .standard) else { throw UnexpectedDiagramType() }
        return diagram
    }

    /// A flowchart case read as another type.
    struct UnexpectedDiagramType: Error {}

    private static func layout(_ source: String, _ typography: DiagramTypography) throws -> FlowchartLayout {
        try FlowchartLayoutEngine.layout(read(source), typography: typography, limits: .standard)
    }

    /// Runs `work` until the time budget is spent, and gives the median and the 99th percentile of one run divided
    /// by `diagramCount`, in microseconds.
    static func measure(perDiagramOf diagramCount: Int, _ work: () -> Void) -> String {
        let timing = timing(perDiagramOf: diagramCount, work)
        return String(format: "median %.2f µs, p99 %.2f µs (%d runs)", timing.medianMicroseconds, timing.percentile99Microseconds, timing.runCount)
    }

    /// The median and the 99th percentile of one run of `work` divided by `diagramCount`, in microseconds, over runs until
    /// the time budget is spent, after one run not counted (Pele's benchmark loop).
    static func timing(perDiagramOf diagramCount: Int, _ work: () -> Void) -> BenchmarkTiming {
        let clock = ContinuousClock()
        var samples: [Duration] = []
        var spent = Duration.zero
        work()
        while (spent < timeBudget || samples.count < minimumRunCount) && samples.count < maximumRunCount {
            let elapsed = clock.measure(work)
            samples.append(elapsed)
            spent += elapsed
        }
        samples.sort()
        func microseconds(_ duration: Duration) -> Double {
            let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
            return seconds * 1e6 / Double(diagramCount)
        }
        let percentileIndex = min(samples.count - 1, Int((Double(samples.count) * 0.99).rounded(.up)) - 1)
        return BenchmarkTiming(medianMicroseconds: microseconds(samples[samples.count / 2]), percentile99Microseconds: microseconds(samples[percentileIndex]),
                               runCount: samples.count)
    }

    /// The growth of the heap's bytes in use while `keptLayoutCount` layouts of `source` are kept, per layout.
    private static func heapGrowthPerLayout(of source: String, typography: DiagramTypography) throws -> Int {
        let diagram = try read(source)
        var kept: [FlowchartLayout] = []
        kept.reserveCapacity(keptLayoutCount)
        let before = heapBytesInUse()
        for _ in 0..<keptLayoutCount { kept.append(try FlowchartLayoutEngine.layout(diagram, typography: typography, limits: .standard)) }
        let growth = heapBytesInUse() - before
        return kept.isEmpty ? 0 : growth / kept.count
    }

    static func heapBytesInUse() -> Int {
        var statistics = malloc_statistics_t()
        malloc_zone_statistics(nil, &statistics)
        return Int(statistics.size_in_use)
    }

    static let palette = DiagramPalette(background: CGColor(gray: 1, alpha: 1), foreground: CGColor(gray: 0.12, alpha: 1),
                                                line: CGColor(gray: 0.12, alpha: 1), surface: CGColor(gray: 0.95, alpha: 1),
                                                border: CGColor(gray: 0.54, alpha: 1))

    private static func bitmapContext(for layout: FlowchartLayout) -> CGContext? {
        bitmapContext(size: layout.size)
    }

    /// A bitmap at two pixels per point, its y running down as a layout's does.
    static func bitmapContext(size: CGSize) -> CGContext? {
        let scale: CGFloat = 2
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: 0, y: size.height * scale)
        context.scaleBy(x: scale, y: -scale)
        return context
    }
}
