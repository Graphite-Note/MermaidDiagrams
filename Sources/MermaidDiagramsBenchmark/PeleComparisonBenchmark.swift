/**
 * File: PeleComparisonBenchmark.swift
 * -----------------------------------
 * Layer: Benchmark
 * Description: Times the package on the inputs of Pele's own benchmark and on every type's documentation examples,
 *              counted as Pele counts them, prints its times beside Pele's (pele-bench.json) and names each target of
 *              Graphite's plan a median misses.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import CoreGraphics
import Foundation
import MermaidDiagrams

/// The median and the 99th percentile of one run per diagram, in microseconds, and how many runs were timed.
public struct BenchmarkTiming: Sendable {
    public let medianMicroseconds: Double
    public let percentile99Microseconds: Double
    public let runCount: Int
}

/// One case of the comparison: a name of Pele's benchmark (`tree: 500 nodes`) or a documentation corpus
/// (`treemap-docs`), its inputs, and whether the plan's targets are checked on it.
struct PeleComparisonCase {
    let name: String
    let sources: [String]
    let checksTargets: Bool
}

/// One case timed: Pele's time and the package's two, per diagram.
public struct PeleComparisonRow: Sendable {
    public let name: String
    public let diagramCount: Int
    public let pele: BenchmarkTiming
    /// Reading and layout (Graphite's target: "parse + layout").
    public let readingAndLayout: BenchmarkTiming
    /// The whole preparation with its SVG, which is what Pele's `render` does.
    public let preparedWithSVG: BenchmarkTiming
    let checksTargets: Bool

    /// How many times faster than Pele the package reads and lays out.
    public var speedUp: Double { pele.medianMicroseconds / readingAndLayout.medianMicroseconds }

    /// The row of the README's table: median / 99th percentile in µs.
    public var tableRow: String {
        String(format: "| %@ | %d | %.2f / %.2f | %.2f / %.2f | %.1f× | %.2f / %.2f |", name, diagramCount, pele.medianMicroseconds,
               pele.percentile99Microseconds, readingAndLayout.medianMicroseconds, readingAndLayout.percentile99Microseconds, speedUp,
               preparedWithSVG.medianMicroseconds, preparedWithSVG.percentile99Microseconds)
    }

    func line(peleName: String) -> String {
        String(format: "%@ (%d): %@ %.2f / %.2f; read and layout %.2f / %.2f (%.1f× Pele); prepared with SVG %.2f / %.2f (%.1f× Pele)", name,
               diagramCount, peleName, pele.medianMicroseconds, pele.percentile99Microseconds, readingAndLayout.medianMicroseconds,
               readingAndLayout.percentile99Microseconds, speedUp, preparedWithSVG.medianMicroseconds, preparedWithSVG.percentile99Microseconds,
               pele.medianMicroseconds / preparedWithSVG.medianMicroseconds)
    }

    /// A line for each target of the plan its median misses.
    var missedTargets: [String] {
        guard checksTargets else { return [] }
        var missed: [String] = []
        if readingAndLayout.medianMicroseconds > PeleComparisonBenchmark.targetMicroseconds {
            missed.append(String(format: "%@: read and layout %.2f µs a diagram, over %.0f µs", name, readingAndLayout.medianMicroseconds,
                                 PeleComparisonBenchmark.targetMicroseconds))
        }
        if speedUp < PeleComparisonBenchmark.targetSpeedUp {
            missed.append(String(format: "%@: read and layout %.1f× faster than Pele's %.2f µs, under %.0f×", name, speedUp, pele.medianMicroseconds,
                                 PeleComparisonBenchmark.targetSpeedUp))
        }
        return missed
    }
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

    /// Prints the comparison with Pele's run on the Mac (`pele-bench.json`) and returns a line for each target a median
    /// misses.
    static func run(typography: DiagramTypography) throws -> [String] {
        let pele = try PeleResults.bench()
        print("Pele \(pele.run.pele) in Deno \(pele.run.deno) (\(pele.run.os) \(pele.run.arch), \(pele.run.date ?? "undated"), text measured with "
              + "\(pele.run.measurer)) beside this package, per diagram: median / 99th percentile in µs")
        let recorded = Dictionary((pele.cases + pele.perType).map { peleCase in (peleCase.name, peleCase) }, uniquingKeysWith: { first, _ in first })
        var missed: [String] = []
        for comparisonCase in try cases() {
            guard let peleCase = recorded[comparisonCase.name], peleCase.diagramCount == comparisonCase.sources.count else {
                let peleCount = recorded[comparisonCase.name]?.diagramCount ?? 0
                missed.append("\(comparisonCase.name): \(comparisonCase.sources.count) inputs here, \(peleCount) in Pele's run")
                continue
            }
            let peleTiming = BenchmarkTiming(medianMicroseconds: peleCase.medianMicrosecondsPerDiagram,
                                             percentile99Microseconds: peleCase.percentile99MicrosecondsPerDiagram, runCount: peleCase.runs)
            let row = timed(comparisonCase, pele: peleTiming, typography: typography)
            print(row.line(peleName: "Pele"))
            missed += row.missedTargets
        }
        return missed
    }

    /// The cases of Pele's benchmark run (`pele-bench.json`), in its order: its own cases, then each type's
    /// documentation examples, the targets checked on those and on Mermaid's flowchart examples.
    static func cases() throws -> [PeleComparisonCase] {
        let pele = try PeleResults.bench()
        let flowchartExamples = try FlowchartCorpus.documentationExamples()
        let generated = PeleResults.generatedBenchmarkInputs
        let benchmarkCases = pele.cases.map { peleCase in
            let isExamples = peleCase.name == "docs: all examples"
            let sources = isExamples ? flowchartExamples : generated.filter { input in input.name == peleCase.name }.map(\.source)
            return PeleComparisonCase(name: peleCase.name, sources: sources, checksTargets: isExamples)
        }
        let typeCases = try pele.perType.map { peleCase in
            PeleComparisonCase(name: peleCase.name, sources: try PeleResults.sources(ofCorpus: peleCase.name), checksTargets: true)
        }
        return benchmarkCases + typeCases
    }

    /// The package's two times on a case, beside Pele's.
    static func timed(_ comparisonCase: PeleComparisonCase, pele: BenchmarkTiming, typography: DiagramTypography) -> PeleComparisonRow {
        let sources = comparisonCase.sources
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
        return PeleComparisonRow(name: comparisonCase.name, diagramCount: sources.count, pele: pele, readingAndLayout: readingAndLayout,
                                 preparedWithSVG: preparedWithSVG, checksTargets: comparisonCase.checksTargets)
    }
}
