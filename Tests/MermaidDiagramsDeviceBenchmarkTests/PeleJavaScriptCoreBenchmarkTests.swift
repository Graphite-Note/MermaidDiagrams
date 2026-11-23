/**
 * File: PeleJavaScriptCoreBenchmarkTests.swift
 * --------------------------------------------
 * Layer: Benchmark
 * Description: Runs the comparison with Pele in JavaScriptCore as an XCTest, for the iPad and the iPhone
 *              (`xcodebuild test`), when MERMAID_DIAGRAMS_DEVICE_BENCHMARK is set; skipped otherwise, so the suite
 *              does not time anything.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import MermaidDiagramsBenchmark
import XCTest

/// `xcodebuild test -scheme MermaidDiagramsDeviceBenchmark -configuration Release -enableCodeCoverage NO
/// -destination id=<device> -allowProvisioningUpdates` (README, Beside Pele): the shared scheme sets
/// MERMAID_DIAGRAMS_DEVICE_BENCHMARK. With `TEST_RUNNER_MERMAID_DIAGRAMS_CHECK_TARGETS=1` before `xcodebuild`
/// (MERMAID_DIAGRAMS_CHECK_TARGETS in the test), each target of Graphite's plan a median misses fails the test, as
/// `--check-targets` makes the Mac's benchmark exit with status 1.
final class PeleJavaScriptCoreBenchmarkTests: XCTestCase {
    @MainActor
    func testPackageBesidePeleInJavaScriptCore() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["MERMAID_DIAGRAMS_DEVICE_BENCHMARK"] != nil else {
            throw XCTSkip("The benchmark runs when MERMAID_DIAGRAMS_DEVICE_BENCHMARK is set")
        }
        let report = try await PeleJavaScriptCoreComparison.run()
        for line in report.lines { print("benchmark: \(line)") }
        let attachment = XCTAttachment(string: report.lines.joined(separator: "\n"))
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(report.differingDrawings, [], "Pele in JavaScriptCore drew these inputs otherwise than in Deno: the comparison does not hold")
        guard environment["MERMAID_DIAGRAMS_CHECK_TARGETS"] != nil else { return }
        for missed in report.missedTargets { XCTFail("missed target: \(missed)") }
    }
}
