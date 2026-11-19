/**
 * File: MermaidDiagramNarrowSafetyTests.swift
 * -------------------------------------------
 * Layer: Tests
 * Description: The documentation examples of the charts that narrow for a column, cut short and mutated, with options
 *              written in front of them, are laid out for narrow and tiny columns at a finite size or refused, never a crash.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class MermaidDiagramNarrowSafetyTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))

    /// Options written before a chart: in block form, in flow form, nested, and with values of the wrong kind or out of range.
    private static let optionBlocks = [
        "",
        "---\nconfig:\n  quadrantChart: {chartWidth: 120, titleFontSize: 40, quadrantPadding: 90, xAxisPosition: bottom, yAxisPosition: right, pointRadius: 30}\n"
            + "  xyChart:\n    width: 150\n    height: 4000\n    showDataLabel: true\n    chartOrientation: horizontal\n    xAxis: {showLabel: false}\n    yAxis:\n      showTick: false\n"
            + "  sankey:\n    labelStyle: outlined\n    linkColor: target\n    width: 50\n    nodeColors: {a: red, Coal: \"#123\"}\n"
            + "  gantt: {barHeight: 9000, barGap: -3, fontSize: 1, sectionFontSize: 80, numberSectionStyles: 0, leftPadding: 2000, useWidth: 5, topPadding: 500, gridLineStartPadding: 9}\n---\n",
        "---\nconfig: {\"quadrantChart\": {\"chartWidth\": -4, \"titleFontSize\": \"big\"}, \"xyChart\": {\"width\": 1e300, \"showTitle\": 0, \"xAxis\": [1]}, \"sankey\": {\"linkColor\": 5, \"nodeColors\": [1]}}\n---\n",
        "%%{init: {'gantt': {'topAxis': true, 'axisFormat': 5, 'tickInterval': '1day', 'barHeight': 1}, 'xyChart': {'width': 100000, 'showLegend': false, 'yAxis': {'showLabel': false}}, 'sankey': {'width': 300, 'linkColor': 'source'}, 'quadrantChart': {'chartHeight': 100}}}%%\n",
    ]

    private func layOutForNarrowColumns(_ source: String) -> Bool {
        guard let diagram = try? MermaidDiagramReader.read(source, limits: .standard) else { return false }
        for width in [CGFloat(300), 160, 40] as [CGFloat] {
            let size: CGSize?
            switch diagram {
            case .mindmap(let mindmap): size = MindmapLayoutEngine.layout(mindmap, typography: typography, availableWidth: width).size
            case .userJourney(let journey):
                size = UserJourneyLayoutEngine.columnLayout(journey, typography: typography, availableWidth: width)?.size
                    ?? UserJourneyLayoutEngine.layout(journey, typography: typography).size
            case .quadrantChart(let chart): size = QuadrantChartLayoutEngine.layout(chart, typography: typography, availableWidth: width).size
            case .xyChart(let chart): size = try? XYChartLayoutEngine.layout(chart, typography: typography, availableWidth: width).size
            case .sankey(let sankey): size = try? SankeyLayoutEngine.layout(sankey, typography: typography, availableWidth: width).size
            case .ganttChart(let chart):
                size = try? GanttLayoutEngine.layout(chart, typography: typography, now: GanttChartCorpus.now, timeZone: GanttChartCorpus.timeZone, limits: .standard,
                                                     availableWidth: width).size
            default: size = nil
            }
            if let size { XCTAssertTrue(size.width.isFinite && size.height.isFinite && size.width >= 0 && size.height >= 0, source) }
            if size == nil { return false }
        }
        return true
    }

    func testTheChartsThatNarrowAreLaidOutForNarrowColumnsWhateverIsCutOrMutated() throws {
        let examples = try [MindmapCorpus.documentationExamples(), UserJourneyCorpus.documentationExamples(), QuadrantChartCorpus.documentationExamples(),
                            XYChartCorpus.documentationExamples(), SankeyCorpus.documentationExamples(), GanttChartCorpus.documentationExamples()].flatMap { examples in examples }
        var generator = NarrowSafetyGenerator(seed: 0x70DE)
        let insertedBytes = Array("[]{}()|\"'-->:;%`<>#\\,".utf8)
        var laidOutCount = 0
        for example in examples {
            for options in Self.optionBlocks {
                let bytes = Array((options + example).utf8)
                var texts = [String(decoding: bytes, as: UTF8.self)]
                for cut in stride(from: 1, to: bytes.count, by: max(1, bytes.count / 12)) { texts.append(String(decoding: bytes[..<cut], as: UTF8.self)) }
                for _ in 0..<6 {
                    var mutated = bytes
                    let position = Int(generator.next() % UInt64(mutated.count))
                    switch generator.next() % 3 {
                    case 0: mutated.remove(at: position)
                    case 1: mutated.insert(insertedBytes[Int(generator.next() % UInt64(insertedBytes.count))], at: position)
                    default: mutated.insert(contentsOf: mutated[position...].prefix(30), at: position)
                    }
                    texts.append(String(decoding: mutated, as: UTF8.self))
                }
                for text in texts where layOutForNarrowColumns(text) { laidOutCount += 1 }
            }
        }
        XCTAssertGreaterThan(laidOutCount, 500)
    }

    func testHugeAndTinyPagesAndManyNodesAreBoundedForNarrowColumns() throws {
        let limits = MermaidDiagramLimits(maximumSourceBytes: 2_000_000, maximumNodeCount: 10_000, maximumEdgeCount: 10_000, maximumLayoutPointCount: 100_000)
        let rows = (0..<400).map { index in "n\(index),n\(index + 1),\(index + 1)" }.joined(separator: "\n")
        let start = Date()
        let sankey = try XCTUnwrap(try? SankeyLayoutEngine.layout(try SankeyReading.diagram("---\nconfig:\n  sankey: {width: 10000, height: 10000}\n---\nsankey\n" + rows, limits: limits),
                                                                  typography: typography, availableWidth: 200))
        XCTAssertTrue(sankey.size.width.isFinite)
        let nodes = (0..<3_000).map { index in String(repeating: "  ", count: index % 6 + 1) + "node number \(index) with some words to wrap" }.joined(separator: "\n")
        let mindmap = MindmapLayoutEngine.layout(try MindmapReading.mindmap("mindmap\n root\n" + nodes, limits: limits), typography: typography, availableWidth: 100)
        XCTAssertTrue(mindmap.size.height.isFinite)
        let tasks = (0..<2_000).map { index in "  Task \(index): \(index % 6): Actor \(index % 7), Other" }.joined(separator: "\n")
        let column = UserJourneyLayoutEngine.columnLayout(try UserJourneyReading.userJourney("journey\n  title T\n  section S\n" + tasks, limits: limits), typography: typography, availableWidth: 200)
        XCTAssertEqual(column?.steps.count, 2_000)
        XCTAssertLessThan(Date().timeIntervalSince(start), 20)
    }
}

/// A repeatable sequence of pseudo-random numbers (SplitMix64), so that a failure found by the mutations is found again.
private struct NarrowSafetyGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}
