/**
 * File: MermaidDiagramReaderTests.swift
 * -------------------------------------
 * Layer: Tests
 * Description: Reading Mermaid text: front matter, comments, directives and the diagram type.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.11
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class MermaidDiagramReaderTests: XCTestCase {
    private func flowchart(_ source: String) throws -> FlowchartDiagram {
        try FlowchartReading.flowchart(source)
    }

    private func readError(_ source: String, limits: MermaidDiagramLimits = .standard) -> MermaidDiagramReadError? {
        FlowchartReading.readError(source, limits: limits)
    }

    func testFlowchartGraphAndElkKeywordsAllReadAFlowchart() throws {
        for keyword in ["flowchart", "graph", "flowchart-elk"] {
            XCTAssertEqual(try flowchart("\(keyword) LR\n  A --> B").nodes.count, 2, keyword)
        }
    }

    func testOtherDiagramTypesAreNamedByTheirKeyword() {
        XCTAssertEqual(readError("requirementDiagram\n  requirement test_req {\n  }"), .unsupportedDiagramType(keyword: "requirementDiagram"))
        XCTAssertEqual(readError("C4Contexts\n  title System"), .unsupportedDiagramType(keyword: "C4Contexts"))
        XCTAssertEqual(try C4Reading.c4("C4Context\n  title System\n  System(a, \"A\")").title, "System")
        XCTAssertEqual(readError("usecase\n  actor A"), .unsupportedDiagramType(keyword: "usecase"))
        XCTAssertEqual(try UseCaseReading.diagram("---\ntitle: Shop\n---\nusecase-beta\n  actor A").title, "Shop")
    }

    func testTheSequenceDiagramKeywordReadsASequenceDiagram() throws {
        let diagram = try SequenceReading.sequence("%% comment\nsequenceDiagram\n  Alice->>Bob: Hi")
        XCTAssertEqual(diagram.participantIdentifiers, ["Alice", "Bob"])
    }

    func testTextWithoutADiagramIsNoDiagram() {
        XCTAssertEqual(readError(""), .noDiagram)
        XCTAssertEqual(readError("  \n\n"), .noDiagram)
        XCTAssertEqual(readError("%% only a comment\n%%{init: {\"theme\": \"dark\"}}%%\n"), .noDiagram)
    }

    func testCommentsDirectivesAndABlankStartComeBeforeTheKeyword() throws {
        let diagram = try flowchart("\n%%{init: {\"flowchart\": {\"curve\": \"linear\"}}}%%\n%% a comment\n\ngraph TD\nA-->B")
        XCTAssertEqual(diagram.edges.count, 1)
    }

    func testFrontMatterGivesTheTitle() throws {
        let diagram = try flowchart("---\ntitle: \"Order flow\"\nconfig:\n  theme: forest\n---\nflowchart LR\n  A --> B")
        XCTAssertEqual(diagram.title, "Order flow")
        XCTAssertEqual(diagram.direction, .leftToRight)
    }

    func testUnclosedFrontMatterIsReportedOnItsFirstLine() {
        XCTAssertEqual(readError("---\ntitle: Lost\nflowchart LR\n  A --> B"), .invalidSyntax(line: 1, problem: .unclosedFrontMatter))
    }

    func testAByteOrderMarkIsSkipped() throws {
        XCTAssertEqual(try flowchart("\u{FEFF}graph TD\nA-->B").edges.count, 1)
    }

    func testTextOverTheSizeLimitIsRefusedBeforeReading() {
        var limits = MermaidDiagramLimits.standard
        limits.maximumSourceBytes = 10
        XCTAssertEqual(readError("graph TD\nA-->B", limits: limits), .sourceTooLarge(limitBytes: 10))
    }

    func testTextThatStartsWithNoKeywordIsUnexpected() {
        XCTAssertEqual(readError("--> graph"), .invalidSyntax(line: 1, problem: .unexpectedText("--> graph")))
    }

    func testErDiagramReadsAnEntityRelationshipDiagramWithItsFrontMatterTitle() throws {
        let source = "---\ntitle: Order example\n---\n%% the orders\nerDiagram\n  CUSTOMER ||--o{ ORDER : places"
        guard case .entityRelationship(let diagram) = try MermaidDiagramReader.read(source, limits: .standard) else {
            return XCTFail("An entity relationship diagram")
        }
        XCTAssertEqual(diagram.title, "Order example")
        XCTAssertEqual(diagram.entities.map(\.identifier), ["CUSTOMER", "ORDER"])
        XCTAssertEqual(readError("erDiagram\n  A ||-- B : x"), .invalidSyntax(line: 2, problem: .expectedCardinality))
    }

    func testBothXYChartKeywordsReadAnXYChartWithItsFrontMatterTitle() throws {
        XCTAssertEqual(try XYChartReading.chart("---\ntitle: Sales\n---\nxychart\n  bar [1, 2]").title, "Sales")
        XCTAssertEqual(try XYChartReading.chart("xychart-beta\n  title \"Own\"\n  bar [1, 2]").title, "Own")
        XCTAssertEqual(readError("xychart-1"), .unsupportedDiagramType(keyword: "xychart-1"))
    }

    func testTheKeywordsOfTheSimpleChartsReadTheirTypesWithTheFrontMatterTitle() throws {
        XCTAssertEqual(try SimpleChartReading.info("---\ntitle: T\n---\ninfo showInfo").title, "T")
        XCTAssertEqual(try SimpleChartReading.packet("%% c\npacket-beta\n+8: \"a\"").fields.count, 1)
        XCTAssertEqual(try SimpleChartReading.packet("packet\n+8: \"a\"").fields.count, 1)
        XCTAssertEqual(try SimpleChartReading.radar("radar-beta:\naxis a").axes.count, 1)
        XCTAssertEqual(try SimpleChartReading.treemap("treemap\n\"a\": 1").nodes.count, 1)
        XCTAssertEqual(try SimpleChartReading.treemap("treemap-beta\n\"a\": 1").nodes.count, 1)
        XCTAssertEqual(try SimpleChartReading.treemap("---\ntitle: T\n---\ntreemap\n\"a\": 1").title, "T")
        for (source, keyword) in [("radar\naxis a", "radar"), ("packet-alpha", "packet-alpha"), ("treemap-x", "treemap-x"), ("infos", "infos")] {
            XCTAssertEqual(readError(source), .unsupportedDiagramType(keyword: keyword), source)
        }
        XCTAssertEqual(MermaidDiagramKind.allCases.count, 28)
    }

    func testADirectiveWrittenOverSeveralLinesInsideASimpleChartIsSkipped() throws {
        XCTAssertEqual(try SimpleChartReading.radar("radar-beta\n%%{\n  init: {}\n}%%\naxis a").axes.count, 1)
        XCTAssertEqual(try SimpleChartReading.packet("packet\n%%{\n  init: {}\n}%%\n+1: \"a\"").fields.count, 1)
        XCTAssertEqual(try SimpleChartReading.treemap("treemap\n%%{\n  init: {}\n}%%\n\"a\": 1").nodes.count, 1)
        XCTAssertEqual(readError("info\n%%{\n  init: {}\n}%%\nx"), .invalidSyntax(line: 5, problem: .unexpectedText("x")))
    }

    func testBothSankeyKeywordsReadASankeyDiagram() throws {
        XCTAssertEqual(try SankeyReading.diagram("%% flows\nsankey\na,b,1").links.count, 1)
        XCTAssertEqual(try SankeyReading.diagram("sankey-beta\na,b,1").nodes.count, 2)
        XCTAssertEqual(readError("sankey-alpha\na,b,1"), .unsupportedDiagramType(keyword: "sankey-alpha"))
    }

    func testADirectiveWrittenOverSeveralLinesComesBeforeTheKeyword() throws {
        let diagram = try flowchart("%%{\n  init: {\n    \"theme\": \"dark\"\n  }\n}%%\nflowchart LR\nA --> B")
        XCTAssertEqual(diagram.nodes.map(\.identifier), ["A", "B"])
        XCTAssertEqual(diagram.direction, .leftToRight)
        XCTAssertEqual(try flowchart("%%{init: {\n \"flowchart\": {\"curve\": \"linear\"}\n}}%%\n%% a comment\ngraph TD\nA-->B").edges.count, 1)
    }

    func testADirectiveWrittenOverSeveralLinesInsideTheDiagramIsSkippedInEveryType() throws {
        let directive = "%%{\n  init: { \"theme\": \"dark\" }\n}%%\n"
        XCTAssertEqual(try flowchart("flowchart TD\nA --> B\n" + directive + "B --> C").edges.count, 2)
        XCTAssertEqual(try SequenceReading.sequence("sequenceDiagram\n" + directive + "Alice->>Bob: Hi").participantIdentifiers, ["Alice", "Bob"])
        XCTAssertEqual(try PieChartReading.pieChart("pie\n" + directive + "\"Dogs\" : 3").slices.count, 1)
        XCTAssertEqual(try C4Reading.c4("C4Context\n" + directive + "System(a, \"A\")").shapes.count, 1)
        XCTAssertEqual(try UseCaseReading.diagram("usecase-beta\n" + directive + "actor A").actors.count, 1)
        XCTAssertEqual(try GanttChartReading.ganttChart("gantt\n" + directive + "dateFormat YYYY-MM-DD\nsection A\nTask :a1, 2024-01-01, 3d").tasks.count, 1)
    }

    func testLineNumbersOfErrorsAfterADirectiveOfSeveralLinesStayTheTextsOwn() {
        XCTAssertEqual(readError("%%{\n init: {}\n}%%\nflowchart sideways\nA --> B"), .invalidSyntax(line: 4, problem: .unknownDirection("sideways")))
        XCTAssertEqual(readError("flowchart TD\n%%{\n init: {}\n}%%\nA --> B\nA --> ["), .invalidSyntax(line: 6, problem: .unexpectedText("[")))
    }

    func testADirectiveNeverClosedIsAComment() throws {
        XCTAssertEqual(try flowchart("%%{ never closed\nflowchart TD\nA --> B").edges.count, 1)
        XCTAssertEqual(try flowchart("flowchart TD\n%%{ never closed\nA --> B").edges.count, 1)
    }

    func testAGitGraphReadsTheOptionsOfItsMultiLineDirective() throws {
        let diagram = try GitGraphReading.gitGraph("%%{\n init: {'gitGraph': {'mainBranchName': 'trunk'}}\n}%%\ngitGraph\n commit")
        XCTAssertEqual(diagram.branches.map(\.name), ["trunk"])
        XCTAssertEqual(diagram.commits.count, 1)
    }

    func testTheKeywordsOfTheDiagramsDrawnOnAPlaneReadTheirTypes() throws {
        XCTAssertEqual(try VennReading.venn("%% sets\nvenn-beta\n  set A").subsets.count, 1)
        XCTAssertEqual(readError("venn\n  set A"), .unsupportedDiagramType(keyword: "venn"))
        XCTAssertEqual(try CynefinReading.cynefin("cynefin-beta\n  complex\n    \"Probe\"").items[.complex], ["Probe"])
        XCTAssertEqual(try CynefinReading.cynefin("cynefin-beta:clear\n\"a\"").items[.clear], ["a"])
        XCTAssertEqual(try WardleyMapReading.map("wardley-beta\ncomponent Tea [0.6, 0.8]").nodes.map(\.label), ["Tea"])
        XCTAssertEqual(readError("WARDLEY-BETA\ncomponent Tea [0.6, 0.8]"), .unsupportedDiagramType(keyword: "WARDLEY-BETA"))
    }
}
