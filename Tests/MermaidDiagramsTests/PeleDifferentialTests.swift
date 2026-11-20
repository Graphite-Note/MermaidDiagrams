/**
 * File: PeleDifferentialTests.swift
 * ---------------------------------
 * Layer: Tests
 * Description: Compares, type by type, the package's prepared scene of every input Pele's runner drew with Pele's own
 *              drawing: the page within a tolerance, the texts and the edges; every difference listed with its reason.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

/// Pele's drawings are recorded by `scripts/pele/run.sh` (`pele-corpus.json`, with Pele measuring text with its table of
/// Arial's advances); each input here is prepared in Arial at 16 points, regular layout only (Pele drew without a
/// `maxWidth`). An input that differs beyond `PeleComparison`'s tolerance must be listed in PeleKnownDifferences.md with
/// what differs, and a listed input must differ as listed, so that a change towards or away from Pele shows.
final class PeleDifferentialTests: XCTestCase {
    private static let knownDifferences = Result { try PeleKnownDifferenceList() }

    private func compare(_ corpora: String..., file: StaticString = #filePath, line: UInt = #line) throws {
        let known = try Self.knownDifferences.get()
        let compared = try PeleComparison.compared(corpora: Set(corpora))
        XCTAssertFalse(compared.isEmpty, "Pele's runner drew no input of \(corpora)", file: file, line: line)
        for input in compared {
            XCTAssertEqual(PeleResults.sourceHash(of: input.source), input.pele.sourceHash, "\(input.name) is not the text Pele drew", file: file, line: line)
            XCTAssertEqual(Set(input.differences), known.inputs[input.name] ?? [], "\(input.name): differs from Pele in \(input.differences)",
                           file: file, line: line)
        }
    }

    func testEveryListedInputIsOneOfPelesAndEveryReasonIsExplained() throws {
        let known = try Self.knownDifferences.get()
        let names = Set(try PeleResults.corpus().inputs.map { input in "\(input.corpus)#\(input.index)" })
        XCTAssertEqual(Set(known.inputs.keys).subtracting(names), [])
        XCTAssertEqual(known.namedReasons.subtracting(known.reasons), [])
        XCTAssertGreaterThan(known.reasons.count, 10)
    }

    func testPelesRunIsTheOneRecordedForTheseTests() throws {
        let run = try PeleResults.corpus().run
        XCTAssertEqual(run.pele, "1.13.0")
        XCTAssertTrue(run.measurer.hasPrefix("metricsMeasurer"), "Pele measured with \(run.measurer), not its table of Arial's advances")
        XCTAssertEqual(try PeleResults.corpus().inputs.count, 765)
    }

    func testAgentFlows() throws {
        try compare("agentflow-docs", "agentflow-reference")
    }

    func testArchitectureDiagrams() throws {
        try compare("architecture-docs")
    }

    func testBlockDiagrams() throws {
        try compare("block-docs")
    }

    func testC4Diagrams() throws {
        try compare("c4-docs")
    }

    func testClassDiagrams() throws {
        try compare("class-docs")
    }

    func testCynefinFrameworks() throws {
        try compare("cynefin-docs")
    }

    func testEntityRelationshipDiagrams() throws {
        try compare("er-docs")
    }

    func testEventModels() throws {
        try compare("eventmodeling-docs")
    }

    func testFlowcharts() throws {
        try compare("flowchart-docs")
    }

    func testGeneratedGraphsOfPelesBenchmark() throws {
        try compare("bench-generated")
    }

    func testGanttCharts() throws {
        try compare("gantt-docs")
    }

    func testGitGraphs() throws {
        try compare("git-docs")
    }

    func testInfoDiagrams() throws {
        try compare("info-docs")
    }

    func testIshikawaDiagrams() throws {
        try compare("ishikawa-docs")
    }

    func testUserJourneys() throws {
        try compare("journey-docs")
    }

    func testKanbanBoards() throws {
        try compare("kanban-docs")
    }

    func testMindmaps() throws {
        try compare("mindmap-docs")
    }

    func testPacketDiagrams() throws {
        try compare("packet-docs")
    }

    func testPieCharts() throws {
        try compare("pie-docs")
    }

    func testQuadrantCharts() throws {
        try compare("quadrant-docs")
    }

    func testRadarCharts() throws {
        try compare("radar-docs")
    }

    func testRailroadDiagrams() throws {
        try compare("railroad-docs")
    }

    func testRequirementDiagrams() throws {
        try compare("requirement-docs")
    }

    func testSankeyDiagrams() throws {
        try compare("sankey-docs")
    }

    func testSequenceDiagrams() throws {
        try compare("sequence-docs")
    }

    func testStateDiagrams() throws {
        try compare("state-docs")
    }

    func testSwimlaneDiagrams() throws {
        try compare("swimlane-docs")
    }

    func testTimelines() throws {
        try compare("timeline-docs")
    }

    func testTreemaps() throws {
        try compare("treemap-docs")
    }

    func testTreeViews() throws {
        try compare("treeview-docs")
    }

    func testUseCaseDiagrams() throws {
        try compare("usecase-docs")
    }

    func testVennDiagrams() throws {
        try compare("venn-docs")
    }

    func testWardleyMaps() throws {
        try compare("wardley-docs")
    }

    func testXYCharts() throws {
        try compare("xychart-docs")
    }
}
