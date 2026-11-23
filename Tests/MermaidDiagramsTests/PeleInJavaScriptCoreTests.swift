/**
 * File: PeleInJavaScriptCoreTests.swift
 * -------------------------------------
 * Layer: Tests
 * Description: Pele's one script (pele-bundle.js) in a JSContext draws every documentation example as Pele's modules
 *              drew it in Deno, so the device benchmark times the same Pele; and its timed case renders what it is given.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

@testable import MermaidDiagramsBenchmark
import XCTest

final class PeleInJavaScriptCoreTests: XCTestCase {
    @MainActor
    func testTheScriptDrawsEveryDocumentationExampleAsPeleInDeno() async throws {
        let pele = try PeleInJavaScriptCore()
        XCTAssertEqual(pele.version, "1.13.0")
        XCTAssertTrue(pele.textMeasuredWithTable, "a JSContext has no canvas: Pele measures with its table, as in Deno")
        let differing = try await PeleJavaScriptCoreComparison.differingDrawings { sources in
            try sources.map { source in try pele.drawing(of: source, now: GanttChartCorpus.now) }
        }
        XCTAssertEqual(differing, [])
    }

    func testATimedCaseCountsTheInputsPeleDraws() throws {
        let pele = try PeleInJavaScriptCore()
        let (timing, renderedCount) = try pele.timing(of: ["flowchart LR\n  A --> B", "pie\n  \"one\" : 1", "not a diagram"])
        XCTAssertEqual(renderedCount, 2, "the input Pele refuses is counted out, as in Pele's benchmark")
        XCTAssertGreaterThanOrEqual(timing.runCount, MermaidDiagramsBenchmark.minimumRunCount)
        XCTAssertGreaterThan(timing.medianMicroseconds, 0)
    }

    func testTheURLClassWritesLinksAsTheURLStandardDoes() throws {
        let pele = try PeleInJavaScriptCore()
        // Pele makes a URL of a link whose only colon ends its http or https scheme; Pele in Deno writes this one so.
        let svg = try pele.svg(of: "flowchart LR\n  A --> B\n  click B \"HTTPS://Example.COM/a/../b c?d e#f g\"", now: GanttChartCorpus.now)
        XCTAssertTrue(svg.contains("href=\"https://example.com/b%20c?d%20e#f%20g\""), "the link as Deno's and WebKit's URL write it")
    }
}
