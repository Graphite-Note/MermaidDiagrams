/**
 * File: PeleNarrowDifferentialTests.swift
 * ---------------------------------------
 * Layer: Tests
 * Description: Compares, type by type, the scene a column 280, 390 and 600 points wide shows of every documentation
 *              example with what Pele shows in a container that wide; every difference listed with its reason.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

/// Pele's drawings for narrow containers are recorded by `scripts/pele/run.sh --max-width=280,390,600`
/// (`pele-narrow.json`): each documentation example as Pele's mount shows it in a container that wide, drawn again
/// for the width (`maxWidth`) when it is wider than that. Each is prepared here in Arial at 16 points with that width as
/// its narrowest column (`narrowestColumnWidth`), and the scene that column shows (`scene(inColumnWidth:)`) is compared
/// as `PeleDifferentialTests` compares the regular scene. An input that differs beyond `PeleComparison`'s tolerance must
/// be listed under PeleKnownDifferences.md's `## Narrow columns` with what differs, and a listed one must differ as
/// listed.
final class PeleNarrowDifferentialTests: XCTestCase {
    private static let knownDifferences = Result { try PeleKnownDifferenceList() }

    private func compare(_ corpus: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let known = try Self.knownDifferences.get()
        let compared = try PeleNarrowComparison.compared(corpora: [corpus])
        XCTAssertEqual(compared.count, try PeleResults.sources(ofCorpus: corpus).count * 3, "\(corpus) is not drawn at the three widths", file: file, line: line)
        for (name, input) in compared {
            XCTAssertEqual(PeleResults.sourceHash(of: input.source), input.pele.sourceHash, "\(name) is not the text Pele drew", file: file, line: line)
            XCTAssertEqual(Set(input.differences), known.narrowInputs[name] ?? [], "\(name): differs from Pele in \(input.differences)",
                           file: file, line: line)
        }
    }

    func testPelesNarrowRunIsTheOneRecordedForTheseTests() throws {
        let narrow = try PeleResults.narrow()
        XCTAssertEqual(narrow.run.pele, "1.13.0")
        XCTAssertTrue(narrow.run.measurer.hasPrefix("metricsMeasurer"), "Pele measured with \(narrow.run.measurer), not its table of Arial's advances")
        XCTAssertEqual(narrow.run.maxWidths, [280, 390, 600])
        XCTAssertEqual(narrow.inputs.count, 1_566)
        XCTAssertGreaterThan(narrow.inputs.filter { input in input.narrowed == true }.count, 500, "Pele drew most of the examples for the width")
    }

    func testEveryListedNarrowInputIsOneOfPelesAndEveryReasonIsExplained() throws {
        let known = try Self.knownDifferences.get()
        let names = Set(try PeleResults.narrow().inputs.map(PeleNarrowComparison.name(of:)))
        XCTAssertEqual(Set(known.narrowInputs.keys).subtracting(names), [])
        XCTAssertEqual(known.namedReasons.subtracting(known.reasons), [])
    }

    func testAgentFlows() throws { try compare("agentflow-docs") }
    func testArchitectureDiagrams() throws { try compare("architecture-docs") }
    func testBlockDiagrams() throws { try compare("block-docs") }
    func testC4Diagrams() throws { try compare("c4-docs") }
    func testClassDiagrams() throws { try compare("class-docs") }
    func testCynefinFrameworks() throws { try compare("cynefin-docs") }
    func testEntityRelationshipDiagrams() throws { try compare("er-docs") }
    func testEventModels() throws { try compare("eventmodeling-docs") }
    func testFlowcharts() throws { try compare("flowchart-docs") }
    func testGanttCharts() throws { try compare("gantt-docs") }
    func testGitGraphs() throws { try compare("git-docs") }
    func testInfoDiagrams() throws { try compare("info-docs") }
    func testIshikawaDiagrams() throws { try compare("ishikawa-docs") }
    func testUserJourneys() throws { try compare("journey-docs") }
    func testKanbanBoards() throws { try compare("kanban-docs") }
    func testMindmaps() throws { try compare("mindmap-docs") }
    func testPacketDiagrams() throws { try compare("packet-docs") }
    func testPieCharts() throws { try compare("pie-docs") }
    func testQuadrantCharts() throws { try compare("quadrant-docs") }
    func testRadarCharts() throws { try compare("radar-docs") }
    func testRailroadDiagrams() throws { try compare("railroad-docs") }
    func testRequirementDiagrams() throws { try compare("requirement-docs") }
    func testSankeyDiagrams() throws { try compare("sankey-docs") }
    func testSequenceDiagrams() throws { try compare("sequence-docs") }
    func testStateDiagrams() throws { try compare("state-docs") }
    func testSwimlaneDiagrams() throws { try compare("swimlane-docs") }
    func testTimelines() throws { try compare("timeline-docs") }
    func testTreemaps() throws { try compare("treemap-docs") }
    func testTreeViews() throws { try compare("treeview-docs") }
    func testUseCaseDiagrams() throws { try compare("usecase-docs") }
    func testVennDiagrams() throws { try compare("venn-docs") }
    func testWardleyMaps() throws { try compare("wardley-docs") }
    func testXYCharts() throws { try compare("xychart-docs") }
}
