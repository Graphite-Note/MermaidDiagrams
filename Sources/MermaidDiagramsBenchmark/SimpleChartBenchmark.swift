/**
 * File: SimpleChartBenchmark.swift
 * --------------------------------
 * Layer: Benchmark
 * Description: Runs the benchmarks of the info diagram, the packet diagram, the radar chart and the treemap.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import MermaidDiagrams

/// Times the four simple charts one after the other: info diagrams, packet diagrams, radar charts and treemaps.
enum SimpleChartBenchmark {
    static func run(typography: DiagramTypography) throws {
        try InfoDiagramBenchmark.run(typography: typography)
        try PacketDiagramBenchmark.run(typography: typography)
        try RadarChartBenchmark.run(typography: typography)
        try TreemapBenchmark.run(typography: typography)
    }
}
