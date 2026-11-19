/**
 * File: SwimlaneLayoutEngineTests.swift
 * -------------------------------------
 * Layer: Tests
 * Description: Swimlane diagrams read as flowcharts under their own keyword and laid out as Pele's swimlane variant: the
 *              lane of loose nodes first, title bands and turned titles, groups inside lanes, edges to a lane's border,
 *              handoffs that turn their corners, the scene and what a screen reader says.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class SwimlaneLayoutEngineTests: XCTestCase {
    private static func layout(_ source: String, isTight: Bool = false) throws -> SwimlaneLayout {
        let measurer = UniformWidthTextMeasurer()
        return SwimlaneLayoutEngine.layout(try SwimlaneCorpusTests.read(source), nodeText: measurer,
                                           edgeText: UniformWidthTextMeasurer(characterWidth: 7, fontSize: 14, lineHeight: 21), titleText: measurer,
                                           font: DiagramFont(postScriptName: nil, size: 16), isTight: isTight)
    }

    func testOnlyItsOwnKeywordReadsASwimlaneDiagram() throws {
        XCTAssertEqual(try MermaidDiagramReader.read("swimlane-beta LR\n  a --> b\n", limits: .standard).kind, .swimlane)
        XCTAssertThrowsError(try MermaidDiagramReader.read("swimlane\n  a --> b\n", limits: .standard)) { error in
            XCTAssertEqual(error as? MermaidDiagramReadError, .unsupportedDiagramType(keyword: "swimlane"))
        }
        XCTAssertEqual(try SwimlaneCorpusTests.read("swimlane-beta RL\n  a --> b\n").direction, .rightToLeft)
    }

    /// Lanes run the length of the diagram side by side across the flow, the lane of the nodes outside every group first,
    /// each title in a band at the lane's start, at least 34 points deep: 24 points of title and 16 here.
    func testLanesTheLooseLaneFirstAndTheirTitleBands() throws {
        let layout = try Self.layout("swimlane-beta TD\n  start --> a\n  subgraph Sales\n    a --> b\n  end\n  subgraph Ops\n    c\n  end\n  b --> c\n")
        XCTAssertEqual(layout.lanes.map { lane in lane.title?.lines ?? [] }, [[], ["Sales"], ["Ops"]])
        XCTAssertEqual(Set(layout.lanes.map(\.frame.height)).count, 1, "every lane the length of the diagram")
        XCTAssertLessThan(layout.lanes[0].frame.midX, layout.lanes[1].frame.midX)
        XCTAssertLessThan(layout.lanes[1].frame.midX, layout.lanes[2].frame.midX)
        for lane in layout.lanes {
            XCTAssertEqual(lane.titleBand, CGRect(x: lane.frame.minX, y: lane.frame.minY, width: lane.frame.width, height: 40))
            XCTAssertFalse(lane.isTitleTurned)
        }
        SwimlaneCorpusTests.assertNodesInLanesAndApart(layout)
        let nodes = layout.flowchart.nodes.map(\.frame)
        XCTAssertGreaterThan(nodes[2].minY, nodes[1].maxY, "b ranked after a")
        XCTAssertGreaterThan(nodes[3].minY, nodes[2].maxY, "c a rank after b, in its own lane")
    }

    func testTitlesTurnWhereTheFlowRunsAcross() throws {
        let layout = try Self.layout("swimlane-beta LR\n  subgraph Sales\n    a --> b\n  end\n")
        let lane = try XCTUnwrap(layout.lanes.first)
        XCTAssertTrue(lane.isTitleTurned)
        XCTAssertEqual(lane.titleBand.width, 40)
        XCTAssertEqual(lane.titleBand.height, lane.frame.height)
        let scene = DiagramScene(layout: layout)
        XCTAssertEqual(scene.texts.first { text in text.part == .clusterLabel }?.rotation, -.pi / 2)
    }

    func testAGroupInsideALaneIsDrawnAroundItsNodesAsAFlowchartsGroup() throws {
        let layout = try Self.layout("swimlane-beta TD\n  subgraph Lane\n    subgraph Inner\n      a --> b\n    end\n    c\n  end\n")
        XCTAssertEqual(layout.lanes.count, 1)
        let inner = try XCTUnwrap(layout.flowchart.clusters.first)
        XCTAssertEqual(inner.depth, 0)
        XCTAssertEqual(inner.title?.lines, ["Inner"])
        for node in layout.flowchart.nodes.prefix(2) { XCTAssertTrue(inner.frame.contains(node.frame)) }
        XCTAssertTrue(layout.lanes[0].frame.contains(inner.frame))
    }

    func testAnEdgeToALaneRunsStraightToItsBorder() throws {
        let layout = try Self.layout("swimlane-beta TD\n  subgraph A\n    a\n  end\n  subgraph B\n    b\n  end\n  a --> B\n")
        let edge = try XCTUnwrap(layout.flowchart.edges.first)
        let laneB = layout.lanes[1].frame
        let tip = try XCTUnwrap(edge.targetMark?.tip)
        XCTAssertEqual(tip.x, laneB.minX, accuracy: 0.001, "the line from a's center to the lane's leaves it at its border")
        guard case .line = edge.path.segments.last, edge.path.segments.count == 2 else { return XCTFail("an S, then a short run straight into the arrow") }
    }

    /// A handoff that leaves toward the other lane and then runs along the flow turns its corner in a curve whose handles
    /// reach 0.62 of the way to the corner, 20 points either side of it, as Pele's `routePath` draws it.
    func testAHandoffTurnsItsCornerAsPeleDrawsIt() {
        let drawn = DiagramTurningRouteDrawing.path(through: [CGPoint(x: 0, y: 0), CGPoint(x: 80, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 20),
                                                              CGPoint(x: 100, y: 100)],
                                                    segmentsRunVertically: [false, false, true, true], startTrim: 0, endTrim: 7)
        XCTAssertEqual(drawn.path.segments.first, .line(to: CGPoint(x: 80, y: 0)))
        guard case .curve(let end, let first, let second) = drawn.path.segments[1] else { return XCTFail("a turn") }
        XCTAssertEqual(end, CGPoint(x: 100, y: 20))
        XCTAssertEqual(first.x, 92.4, accuracy: 1e-9)
        XCTAssertEqual(second.y, 7.6, accuracy: 1e-9)
        XCTAssertEqual(drawn.path.segments.last, .line(to: CGPoint(x: 100, y: 93)))
        XCTAssertEqual(drawn.endDirection, CGVector(dx: 0, dy: 1))
    }

    func testTheScenePaintsTheLanesBehindTheFlowchartAndAScreenReaderNamesThem() throws {
        let source = "swimlane-beta LR\n  accTitle: Orders\n  subgraph Customer\n    order[Place order]\n  end\n  subgraph Shop\n    ship[Ship]\n  end\n  order --> ship\n"
        let prepared = try MermaidDiagramPreparation.prepare(source: source, typography: DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16)))
        XCTAssertEqual(prepared.kind, .swimlane)
        XCTAssertEqual(prepared.accessibility.label, "Orders")
        XCTAssertEqual(prepared.accessibility.summary, ["Customer", "Shop", "Place order", "Ship"])
        guard case .shape(let first) = prepared.scene.items.first else { return XCTFail("a shape first") }
        XCTAssertEqual(first.part, .cluster)
    }
}
