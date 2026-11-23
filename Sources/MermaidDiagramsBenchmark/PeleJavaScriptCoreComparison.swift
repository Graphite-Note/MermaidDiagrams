/**
 * File: PeleJavaScriptCoreComparison.swift
 * ----------------------------------------
 * Layer: Benchmark
 * Description: The comparison with Pele on the machine it runs on: Pele itself in JavaScriptCore (a JSContext, and on an
 *              iPad or an iPhone a WebKit page too), checked to draw every documentation example as in Deno, then timed
 *              beside the package on the cases of PeleComparisonBenchmark; the devices run it as an XCTest, the Mac with
 *              --pele-javascriptcore.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import Darwin
import Foundation
import MermaidDiagrams

/// What Pele 1.13.0 in Deno drew of each documentation example (`pele-bundle-drawings.json`, written by
/// scripts/pele/bundle.sh when it made `pele-bundle.js`).
struct PeleBundleDrawings: Decodable {
    struct Input: Decodable {
        let corpus: String
        let index: Int
        let sourceHash: String
        let drawing: String
    }

    let inputs: [Input]
}

/// One case: Pele in a JSContext, in a WebKit page where one was run, and the package. `comparison` holds the Pele the
/// targets are checked against: WebKit's where it ran (what Obsidian runs on a device), else the JSContext's.
public struct PeleJavaScriptCoreRow: Sendable {
    public let comparison: PeleComparisonRow
    public let peleInContext: BenchmarkTiming
    public let peleInWebKit: BenchmarkTiming?

    /// The row of the README's table: median / 99th percentile in µs.
    public var tableRow: String {
        let webKit = peleInWebKit.map { timing in String(format: "%.2f / %.2f", timing.medianMicroseconds, timing.percentile99Microseconds) } ?? "not run"
        return String(format: "| %@ | %d | %@ | %.2f / %.2f | %.2f / %.2f | %.1f× | %.2f / %.2f |", comparison.name, comparison.diagramCount, webKit,
                      peleInContext.medianMicroseconds, peleInContext.percentile99Microseconds, comparison.readingAndLayout.medianMicroseconds,
                      comparison.readingAndLayout.percentile99Microseconds, comparison.speedUp, comparison.preparedWithSVG.medianMicroseconds,
                      comparison.preparedWithSVG.percentile99Microseconds)
    }
}

/// The comparison's result: the machine, how Pele ran, the inputs Pele drew otherwise than in Deno, every case timed,
/// and the targets of Graphite's plan the package misses beside this Pele.
public struct PeleJavaScriptCoreReport: Sendable {
    /// The model identifier (`iPad13,6`, `Mac17,7`), the system and its version.
    public let machine: String
    public let pele: [String]
    public let differingDrawings: [String]
    public let rows: [PeleJavaScriptCoreRow]

    public var missedTargets: [String] { rows.flatMap(\.comparison.missedTargets) }

    /// The report as the README's "Beside Pele" section writes it, one line for each case.
    public var lines: [String] {
        [machine] + pele + ["drawings differing from Pele's in Deno: \(differingDrawings.count)"] + differingDrawings
            + ["| Inputs | Diagrams | Pele in WebKit, render | Pele in a JSContext, render | Package, read and layout | Speed-up | Package, prepared with SVG |",
               "|---|---:|---:|---:|---:|---:|---:|"] + rows.map(\.tableRow)
    }
}

/// Pele in JavaScriptCore beside the package, on the machine it runs on (`PeleComparisonBenchmark`'s cases, counted the
/// same way). Obsidian on the iPad and the iPhone runs Pele in a WebKit page, whose JavaScriptCore compiles hot code to
/// machine code; a JSContext in an app's own process is the same engine without those compilers (iOS keeps them to
/// WebKit's processes, and the Mac to processes allowed `com.apple.security.cs.allow-jit`), so it times Pele
/// interpreted. On iOS both are timed and the targets checked against WebKit's.
public enum PeleJavaScriptCoreComparison {
    /// WebKit's page runs on an iPad or an iPhone, in the XCTest's app; the Mac's benchmark is a tool with no app.
    static var runsWebKit: Bool {
        #if os(iOS)
        true
        #else
        false
        #endif
    }

    @MainActor
    public static func run() async throws -> PeleJavaScriptCoreReport {
        let typography = DiagramTypography(font: MermaidDiagramsBenchmark.font)
        let context = try PeleInJavaScriptCore()
        let measurer = context.textMeasuredWithTable ? "its table of Arial's advances" : "a canvas"
        var pele = ["Pele \(context.version) in a JSContext, text measured with \(measurer)"]
        var differing = try await differingDrawings { sources in
            try sources.map { source in try context.drawing(of: source, now: GanttChartCorpus.now) }
        }.map { drawing in "JSContext \(drawing)" }
        let webKit = runsWebKit ? try await PeleInWebKit() : nil
        defer { webKit?.close() }
        if let webKit {
            let webKitMeasurer = try await webKit.textMeasuredWithTable ? "its table of Arial's advances" : "the page's fonts"
            pele.append(String(format: "Pele %@ in WebKit, text measured with %@, the page's clock in steps of %.0f µs", try await webKit.version,
                               webKitMeasurer, webKit.clockResolutionMicroseconds))
            // Pele writes a Gantt chart's dates in the page's time zone, the device's, where Deno and the JSContext run in UTC.
            let offset = try await webKit.timeZoneOffsetMinutes(at: GanttChartCorpus.now)
            let leftOut: Set<String> = offset == 0 ? [] : ["gantt-docs"]
            if offset != 0 {
                pele.append(String(format: "WebKit's drawings of gantt-docs not compared: the page's time zone is %+.0f minutes from UTC", -offset))
            }
            differing += try await differingDrawings(leavingOut: leftOut) { sources in try await webKit.drawings(of: sources, now: GanttChartCorpus.now) }
                .map { drawing in "WebKit \(drawing)" }
        }
        var rows: [PeleJavaScriptCoreRow] = []
        for comparisonCase in try PeleComparisonBenchmark.cases() {
            let peleInContext = try context.timing(of: comparisonCase.sources).timing
            let peleInWebKit = try await webKit?.timing(of: comparisonCase.sources)
            let comparison = PeleComparisonBenchmark.timed(comparisonCase, pele: peleInWebKit ?? peleInContext, typography: typography)
            let row = PeleJavaScriptCoreRow(comparison: comparison, peleInContext: peleInContext, peleInWebKit: peleInWebKit)
            print(row.tableRow)
            rows.append(row)
        }
        return PeleJavaScriptCoreReport(machine: machine(), pele: pele, differingDrawings: differing, rows: rows)
    }

    /// Every documentation example drawn otherwise than Pele drew it in Deno: its page, its type or its SVG's hash.
    @MainActor
    static func differingDrawings(leavingOut leftOut: Set<String> = [], drawn: ([String]) async throws -> [PeleInJavaScriptCore.Drawing]) async throws
        -> [String] {
        let recorded = try JSONDecoder().decode(PeleBundleDrawings.self, from: PeleResults.resource(named: "pele-bundle-drawings", extension: "json"))
        var differing: [String] = []
        for corpus in Set(recorded.inputs.map(\.corpus)).subtracting(leftOut).sorted() {
            let sources = try PeleResults.sources(ofCorpus: corpus)
            let drawings = try await drawn(sources)
            for input in recorded.inputs where input.corpus == corpus {
                guard input.index < sources.count, PeleResults.sourceHash(of: sources[input.index]) == input.sourceHash else {
                    differing.append("\(corpus)#\(input.index): not the input Pele drew")
                    continue
                }
                if drawings[input.index] != input.drawing { differing.append("\(corpus)#\(input.index): \(drawings[input.index]), in Deno \(input.drawing)") }
            }
        }
        return differing
    }

    /// The machine's model identifier and its system, as `sysctl hw.machine` (a device) or `hw.model` (a Mac) names it.
    static func machine() -> String {
        func value(of name: String) -> String {
            var size = 0
            guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "" }
            var bytes = [CChar](repeating: 0, count: size)
            guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { return "" }
            return String(decoding: bytes.prefix { byte in byte != 0 }.map { byte in UInt8(bitPattern: byte) }, as: UTF8.self)
        }
        let model = value(of: "hw.machine").hasPrefix("arm64") ? value(of: "hw.model") : value(of: "hw.machine")
        return "\(model), \(ProcessInfo.processInfo.operatingSystemVersionString)"
    }
}
