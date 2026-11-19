/**
 * File: PlaneMapBenchmarks.swift
 * ------------------------------
 * Layer: Benchmark
 * Description: Runs the benchmarks of the diagrams drawn on a fixed plane: Venn diagrams, Cynefin frameworks and Wardley
 *              maps.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import MermaidDiagrams

/// The benchmarks of Venn diagrams, Cynefin frameworks and Wardley maps, in that order.
enum PlaneMapBenchmarks {
    static func run(typography: DiagramTypography) throws {
        try VennBenchmark.run(typography: typography)
        try CynefinBenchmark.run(typography: typography)
        try WardleyMapBenchmark.run(typography: typography)
    }
}
