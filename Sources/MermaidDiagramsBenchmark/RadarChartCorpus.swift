/**
 * File: RadarChartCorpus.swift
 * -------------------------
 * Layer: Benchmark
 * Description: The radar charts the benchmark times: Mermaid's documentation examples and generated charts.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import Foundation

/// The radar charts the benchmark times: Mermaid's three documentation examples, as Pele's corpus collects them
/// (`tests/corpus/radar-docs.json`), and charts of many axes and curves with values from 1 to 100, with the seed of Pele's
/// generated graphs.
enum RadarChartCorpus {
    static func documentationExamples() throws -> [String] {
        guard let location = Bundle.module.url(forResource: "radar-docs", withExtension: "json", subdirectory: "BenchmarkResources") else {
            throw FlowchartCorpus.MissingResource()
        }
        return try JSONDecoder().decode([String].self, from: Data(contentsOf: location))
    }

    /// A chart of `axisCount` axes and `curveCount` curves with a value for every axis, and a polygonal graticule.
    static func generated(axisCount: Int, curveCount: Int) -> String {
        var seed: UInt32 = 7
        var source = "radar-beta\ntitle Generated curves\naxis " + (0..<axisCount).map { axis in "a\(axis)[\"Axis \(axis + 1)\"]" }.joined(separator: ", ") + "\n"
        for curve in 0..<curveCount {
            let values = (0..<axisCount).map { _ -> String in
                seed = seed &* 1_664_525 &+ 1_013_904_223
                return String(1 + Int(Double(seed) / 4_294_967_296 * 100))
            }
            source += "curve c\(curve)[\"Curve \(curve + 1)\"]{" + values.joined(separator: ", ") + "}\n"
        }
        return source + "max 100\ngraticule polygon\n"
    }
}
