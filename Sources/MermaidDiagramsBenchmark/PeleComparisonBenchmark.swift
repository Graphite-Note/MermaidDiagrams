/**
 * File: PeleComparisonBenchmark.swift
 * -----------------------------------
 * Layer: Benchmark
 * Description: Times the package on the inputs of Pele's own benchmark and on every type's documentation examples,
 *              counted as Pele counts them, prints its times beside Pele's (pele-bench.json) and names each target of
 *              Graphite's plan a median misses.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics
import Foundation
import MermaidDiagrams

/// The median and the 99th percentile of one run per diagram, in microseconds, and how many runs were timed.
struct BenchmarkTiming {
    let medianMicroseconds: Double
    let percentile99Microseconds: Double
    let runCount: Int
}

/// Pele's benchmark (`scripts/bench.mjs`: Mermaid's flowchart examples, trees and meshes of 50 and 500 nodes) and each
/// type's documentation examples, timed as Pele's runner times them (`scripts/pele/pele-runner.ts`): every input of a
/// case per run, refused ones included, the case's median and 99th percentile divided by its inputs. Two times per case:
/// reading and layout (Graphite's target: "parse + layout"), and the whole preparation with its SVG, which is what
/// Pele's `render` does (read, lay out, write the SVG). The targets of Graphite's plan (`Docs/Native-diagrams-todo.md`,
/// Performance targets) are checked on the documentation examples: reading and layout at most 30 µs a diagram, and
/// ten times faster than Pele on the same inputs.
enum PeleComparisonBenchmark {
    /// The upper end of the plan's 5 to 30 µs a diagram for parse and layout.
    static let targetMicroseconds = 30.0
    /// Ten times faster than Pele's measured time on the same input.
    static let targetSpeedUp = 10.0

    /// Prints the comparison and returns a line for each target a median misses.
    static func run(typography: DiagramTypography) throws -> [String] {
        let pele = try PeleResults.bench()
        print("Pele \(pele.run.pele) in Deno \(pele.run.deno) (\(pele.run.os) \(pele.run.arch), \(pele.run.date ?? "undated"), text measured with "
              + "\(pele.run.measurer)) beside this package, per diagram: median / 99th percentile in µs")
        let flowchartExamples = try FlowchartCorpus.documentationExamples()
        let generated = PeleResults.generatedBenchmarkInputs
        var missed: [String] = []
        for peleCase in pele.cases {
            let sources = peleCase.name == "docs: all examples" ? flowchartExamples : generated.filter { input in input.name == peleCase.name }.map(\.source)
            missed += compare(peleCase, sources: sources, checksTargets: peleCase.name == "docs: all examples", typography: typography)
        }
        for peleCase in pele.perType {
            missed += compare(peleCase, sources: try PeleResults.sources(ofCorpus: peleCase.name), checksTargets: true, typography: typography)
        }
        return missed
    }

    private static func compare(_ peleCase: PeleTimedCase, sources: [String], checksTargets: Bool, typography: DiagramTypography) -> [String] {
        guard sources.count == peleCase.diagramCount else {
            return ["\(peleCase.name): \(sources.count) inputs here, \(peleCase.diagramCount) in Pele's run"]
        }
        let readingAndLayout = MermaidDiagramsBenchmark.timing(perDiagramOf: sources.count) {
            for source in sources {
                _ = (try? MermaidDiagramReader.read(source, limits: .standard)).map { diagram in
                    DiagramSceneBenchmark.laidOut(diagram, typography: typography)
                }
            }
        }
        let preparedWithSVG = MermaidDiagramsBenchmark.timing(perDiagramOf: sources.count) {
            for source in sources {
                _ = try? MermaidDiagramPreparation.prepare(source: source, typography: typography, narrowestColumnWidth: nil, now: GanttChartCorpus.now,
                                                           timeZone: GanttChartCorpus.timeZone).svgDocument()
            }
        }
        let speedUp = peleCase.medianMicrosecondsPerDiagram / readingAndLayout.medianMicroseconds
        print(String(format: "%@ (%d): Pele %.2f / %.2f; read and layout %.2f / %.2f (%.1f× Pele); prepared with SVG %.2f / %.2f (%.1f× Pele)",
                     peleCase.name, sources.count, peleCase.medianMicrosecondsPerDiagram, peleCase.percentile99MicrosecondsPerDiagram,
                     readingAndLayout.medianMicroseconds, readingAndLayout.percentile99Microseconds, speedUp, preparedWithSVG.medianMicroseconds,
                     preparedWithSVG.percentile99Microseconds, peleCase.medianMicrosecondsPerDiagram / preparedWithSVG.medianMicroseconds))
        guard checksTargets else { return [] }
        var missed: [String] = []
        if readingAndLayout.medianMicroseconds > targetMicroseconds {
            missed.append(String(format: "%@: read and layout %.2f µs a diagram, over %.0f µs", peleCase.name, readingAndLayout.medianMicroseconds,
                                 targetMicroseconds))
        }
        if speedUp < targetSpeedUp {
            missed.append(String(format: "%@: read and layout %.1f× faster than Pele's %.2f µs, under %.0f×", peleCase.name, speedUp,
                                 peleCase.medianMicrosecondsPerDiagram, targetSpeedUp))
        }
        return missed
    }
}
