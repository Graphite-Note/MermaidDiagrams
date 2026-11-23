/**
 * File: LayoutMemoryBenchmark.swift
 * ---------------------------------
 * Layer: Benchmark
 * Description: Measures, per case of the comparison with Pele, the heap a diagram's layout holds and the heap its whole
 *              preparation holds, with and without its narrow scene, per diagram: the median and the largest.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import CoreGraphics
import Foundation
import MermaidDiagrams

/// `--layout-memory`: for each case of `PeleComparisonBenchmark` (Pele's benchmark and every type's documentation
/// examples), each input read once is laid out `keptCount` times and every layout kept, and the heap's growth divided by
/// `keptCount` is what one layout holds (Graphite's target: at most 64 kB of layout data for a typical diagram); then the
/// same for the whole preparation without and with the narrow scene for Graphite's narrowest column (scenes and what a
/// screen reader says). Each prints the median and the largest over the case's inputs, in kB; a refused input is left out.
enum LayoutMemoryBenchmark {
    static let keptCount = 100
    /// Graphite's target for the layout data of a typical diagram.
    static let targetBytes = 64 * 1_024

    static func run(typography: DiagramTypography) throws {
        print("heap held per diagram, median / largest in kB, \(keptCount) of each kept: layout; prepared without the narrow scene; "
              + "prepared with it (narrowest column \(Int(PreparedMermaidDiagram.standardNarrowestColumnWidth)) points)")
        for comparisonCase in try PeleComparisonBenchmark.cases() {
            var layoutBytes: [Int] = []
            var preparedBytes: [Int] = []
            var preparedWithNarrowBytes: [Int] = []
            for source in comparisonCase.sources {
                guard let diagram = try? MermaidDiagramReader.read(source, limits: .standard),
                      DiagramSceneBenchmark.laidOut(diagram, typography: typography) != nil else { continue }
                layoutBytes.append(heapGrowthPerKept { DiagramSceneBenchmark.laidOut(diagram, typography: typography) })
                let prepared = { (narrowestColumnWidth: CGFloat?) in
                    heapGrowthPerKept {
                        try? MermaidDiagramPreparation.prepare(diagram, typography: typography, narrowestColumnWidth: narrowestColumnWidth,
                                                               now: GanttChartCorpus.now, timeZone: GanttChartCorpus.timeZone)
                    }
                }
                preparedBytes.append(prepared(nil))
                preparedWithNarrowBytes.append(prepared(PreparedMermaidDiagram.standardNarrowestColumnWidth))
            }
            guard !layoutBytes.isEmpty else { continue }
            let over = layoutBytes.filter { bytes in bytes > targetBytes }.count
            print("\(comparisonCase.name) (\(layoutBytes.count)): layout \(kilobytes(layoutBytes)); prepared \(kilobytes(preparedBytes)); "
                  + "with the narrow scene \(kilobytes(preparedWithNarrowBytes)); layouts over 64 kB: \(over)")
        }
    }

    /// The heap's growth while `keptCount` results of `make` are kept, per result.
    private static func heapGrowthPerKept<Result>(_ make: () -> Result) -> Int {
        var kept: [Result] = []
        kept.reserveCapacity(keptCount)
        let before = MermaidDiagramsBenchmark.heapBytesInUse()
        for _ in 0..<keptCount { kept.append(make()) }
        let growth = MermaidDiagramsBenchmark.heapBytesInUse() - before
        return withExtendedLifetime(kept) { growth / keptCount }
    }

    private static func kilobytes(_ bytes: [Int]) -> String {
        let sorted = bytes.sorted()
        return String(format: "%.1f / %.1f", Double(sorted[sorted.count / 2]) / 1_024, Double(sorted[sorted.count - 1]) / 1_024)
    }
}
