/**
 * File: PeleNarrowLayoutTests.swift
 * ---------------------------------
 * Layer: Tests
 * Description: The narrow layouts Pele's fit-width helpers make, type by type: a packet's turned grid, a pie's and a
 *              radar's legend below, a class diagram's parts in rows, a tight sequence, the breakpoint past which a
 *              diagram is not turned, and every documentation example at hostile column widths.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class PeleNarrowLayoutTests: XCTestCase {
    private let typography = PeleComparison.typography

    private func prepared(_ source: String, columnWidth: CGFloat) throws -> PreparedMermaidDiagram {
        try MermaidDiagramPreparation.prepare(source: source, typography: typography, narrowestColumnWidth: columnWidth, now: GanttChartCorpus.now,
                                              timeZone: GanttChartCorpus.timeZone)
    }

    /// The diagram `source` reads as, taken out by `extract`.
    private func read<Diagram>(_ source: String, _ extract: (MermaidDiagram) -> Diagram?) throws -> Diagram {
        try XCTUnwrap(extract(try MermaidDiagramReader.read(source, limits: .standard)), source)
    }

    func testAPacketTurnsToAPowerOfTwoBitsARowAsWideAsTheContainerGives() throws {
        let packet = try SimpleChartReading.packet("packet\n0-15: \"Source Port\"\n16-31: \"Destination Port\"\n32-63: \"Sequence Number\"")
        // 280 less 16 of page holds 14 bits of 18 points: a byte to a row, each bit its own 32 points.
        XCTAssertEqual(PacketTurnedGrid(packet, availableWidth: 280, padding: 8), PacketTurnedGrid(bitsPerRow: 8, bitWidth: 32))
        // 390 holds 20: 16 bits to a row, each 374 / 16 points.
        XCTAssertEqual(PacketTurnedGrid(packet, availableWidth: 390, padding: 8), PacketTurnedGrid(bitsPerRow: 16, bitWidth: 23.375))
        let turned = PacketDiagramLayoutEngine.layout(packet, typography: typography, availableWidth: 390)
        XCTAssertEqual(turned.fields.count, 4, "Each 16-bit field fills a row; the 32-bit field takes two")
        XCTAssertTrue(turned.fields.allSatisfy { field in field.frame.maxX <= turned.size.width }, "Every box is on the page")
        XCTAssertLessThanOrEqual(turned.size.width, 390)
        XCTAssertEqual(PacketDiagramLayoutEngine.layout(packet, typography: typography, availableWidth: 700),
                       PacketDiagramLayoutEngine.layout(packet, typography: typography), "Past 640 points Pele keeps it across")
    }

    func testAPieTooWideForItsContainerPutsItsLegendBelowAndShrinks() throws {
        let chart = try read(PieChartCorpus.pie(sliceCount: 5)) { diagram in if case .pieChart(let chart) = diagram { chart } else { nil } }
        let tight = PieChartLayoutEngine.layout(chart, typography: typography, availableWidth: 240)
        XCTAssertLessThanOrEqual(tight.size.width, 240)
        XCTAssertGreaterThanOrEqual(tight.radius, PieChartLayoutEngine.narrowestDiameter / 2)
        for entry in tight.legend { XCTAssertGreaterThan(entry.swatch.minY, tight.center.y + tight.radius, "The legend is below the pie") }
        XCTAssertEqual(PieChartLayoutEngine.layout(chart, typography: typography, availableWidth: 2_000), PieChartLayoutEngine.layout(chart, typography: typography))
    }

    func testARadarChartTooWideForItsContainerPutsItsLegendBelowItsCircle() throws {
        let source = "radar-beta\n  axis A, B, C, D\n  curve first{1, 2, 3, 4}\n  curve second{4, 3, 2, 1}\n  showLegend true"
        let chart = try SimpleChartReading.radar(source)
        let tight = RadarChartLayoutEngine.layout(chart, typography: typography, availableWidth: 300)
        XCTAssertLessThan(tight.size.width, RadarChartLayoutEngine.layout(chart, typography: typography).size.width)
        for entry in tight.legend { XCTAssertGreaterThan(entry.swatch.minY, tight.center.y + tight.radius) }
    }

    func testAClassDiagramSetsItsUnjoinedPartsInRowsThatFitTheContainer() throws {
        let source = "classDiagram\n" + (0..<6).map { index in "  First\(index) <|-- Second\(index)" }.joined(separator: "\n")
        let diagram = try prepared(source, columnWidth: 390)
        let narrow = try XCTUnwrap(diagram.narrowScene)
        XCTAssertLessThanOrEqual(narrow.size.width, 400, "Six pairs side by side are set in rows")
        XCTAssertGreaterThan(narrow.size.height, diagram.scene.size.height)
        let classDiagram = try read(source) { diagram in if case .classDiagram(let classes) = diagram { classes } else { nil } }
        let layout = try ClassDiagramLayoutEngine.layout(classDiagram, typography: typography, limits: .standard, availableWidth: 390)
        let frames = layout.classes.map(\.frame)
        for (index, frame) in frames.enumerated() {
            XCTAssertTrue(CGRect(origin: .zero, size: layout.size).contains(frame))
            for other in frames[(index + 1)...] { XCTAssertFalse(frame.intersects(other), "No two classes overlap") }
        }
    }

    func testATightSequenceWrapsItsMessagesAndNarrowsItsParticipants() throws {
        let source = "sequenceDiagram\n" + (0..<5).map { index in
            "  Participant\(index)->>Participant\(index + 1): a message long enough to wrap between two lifelines"
        }.joined(separator: "\n")
        let diagram = try prepared(source, columnWidth: 390)
        let narrow = try XCTUnwrap(diagram.narrowScene)
        XCTAssertLessThan(narrow.size.width, diagram.scene.size.width)
        let tight = SequenceMeasurements.tight(participantCount: 6, availableWidth: 390)
        XCTAssertEqual(tight.wrappingWidth, 32, "374 / 6 less the gap and 24 is under 32")
        XCTAssertEqual(SequenceMeasurements.tight(participantCount: 2, availableWidth: 390).wrappingWidth, 155)
    }

    func testPastPelesBreakpointADiagramThatRunsAcrossIsNotTurned() throws {
        let source = "erDiagram\n  direction LR\n" + (0..<8).map { index in "  Entity\(index) ||--o{ Entity\(index + 1) : holds" }.joined(separator: "\n")
        let wide = try prepared(source, columnWidth: 700)
        XCTAssertGreaterThan(wide.scene.size.width, 700)
        XCTAssertNil(wide.narrowScene, "Pele keeps a diagram across in a container of 640 points or more")
        XCTAssertNotNil(try prepared(source, columnWidth: 600).narrowScene)
    }

    func testAFlowchartTurnedForANarrowContainerKeepsItsGroupsDirections() throws {
        let flowchart = try read("flowchart RL\n  subgraph inner\n    direction LR\n    a --> b\n  end") { diagram in
            if case .flowchart(let flowchart) = diagram { flowchart } else { nil }
        }
        let turned = try XCTUnwrap(flowchart.rootTurnedToRunDown)
        XCTAssertEqual(turned.direction, .topToBottom, "Pele draws a turned diagram from the top down, whichever way it ran")
        XCTAssertEqual(turned.subgraphs.map(\.direction), [.leftToRight])
    }

    func testATimelineRunningDownSharesTheContainerBetweenItsColumns() throws {
        let timeline = try read(TimelineCorpus.generated(periodCount: 6, isDown: true)) { diagram in
            if case .timeline(let timeline) = diagram { timeline } else { nil }
        }
        let measured = TimelineMeasurement(diagram: timeline, periodText: typography.nodeText, eventText: typography.edgeText, isDown: true, room: 264)
        // 264 less the axis, the spine and the paddings (96) leaves 168: 38 % of it, at least 80, for the periods.
        XCTAssertEqual(measured.textWidth, 80)
        XCTAssertEqual(measured.eventTextWidth, 110)
    }

    func testEveryDocumentationExampleIsLaidOutForHostileColumnWidthsAtAFiniteSize() throws {
        let corpora = Set(try PeleResults.narrow().inputs.map(\.rendered.corpus))
        for corpus in corpora.sorted() {
            for source in try PeleResults.sources(ofCorpus: corpus) {
                for width in [CGFloat(1), 0.5, 37, 639.5, 641, .greatestFiniteMagnitude, -10, .nan] {
                    guard let diagram = try? prepared(source, columnWidth: width) else { continue }
                    for scene in [diagram.scene, diagram.narrowScene].compactMap({ scene in scene }) {
                        XCTAssertTrue(scene.size.width.isFinite && scene.size.height.isFinite && scene.size.width >= 0, "\(corpus) at \(width)")
                    }
                }
            }
        }
    }
}
