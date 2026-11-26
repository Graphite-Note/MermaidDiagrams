/**
 * File: UseCaseAgentFlowC4SwimlaneSceneLimitTests.swift
 * -----------------------------------------------------
 * Layer: Tests
 * Description: The scenes of use case diagrams, agent flows, C4 diagrams and swimlanes record their paths within the
 *              element limit of the limits they are given: a layout with one path past the limit of small limits makes
 *              a scene that says so, which the preparation's check refuses as too many path elements, while the same
 *              layout under the standard limits, and every documentation example under the limits it is prepared with,
 *              makes a whole scene.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 26/11/2026
 */

import CoreGraphics
import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class UseCaseAgentFlowC4SwimlaneSceneLimitTests: XCTestCase {
    private let typography = DiagramSceneSamples.typography
    /// Limits whose element limit is the smallest a lane has, 2¹⁶ verbs.
    private let smallLimits = MermaidDiagramLimits(maximumSourceBytes: 1_000, maximumNodeCount: 1, maximumEdgeCount: 1, maximumLayoutPointCount: 1)
    /// More line segments than a lane under the small limits holds, far fewer than one under the standard limits does.
    private let longPathSegmentCount = 70_000

    override func setUp() {
        super.setUp()
        XCTAssertGreaterThan(longPathSegmentCount, DiagramSceneWorkspace.elementLimit(for: smallLimits))
        XCTAssertLessThan(longPathSegmentCount, DiagramSceneWorkspace.elementLimit(for: .standard))
    }

    /// A zigzag path of `longPathSegmentCount` lines from `start`.
    private func longPath(from start: CGPoint) -> DiagramPath {
        DiagramPath(start: start, segments: (0..<longPathSegmentCount).map { index in
            .line(to: CGPoint(x: start.x + CGFloat(index % 2), y: start.y + CGFloat(index % 3)))
        })
    }

    /// The scene made under the small limits says it went past their element limit and is refused by the preparation's
    /// check, and the one made under the standard limits is whole.
    private func assertRefusedUnderSmallLimitsOnly(_ scene: (MermaidDiagramLimits) -> DiagramScene, file: StaticString = #filePath, line: UInt = #line) {
        let limit = DiagramSceneWorkspace.elementLimit(for: smallLimits)
        let refused = scene(smallLimits)
        XCTAssertEqual(refused.exceededPathElementLimit, limit, file: file, line: line)
        XCTAssertThrowsError(try MermaidDiagramPreparation.refuseIncomplete(refused, limits: .standard), file: file, line: line) { error in
            XCTAssertEqual(error as? MermaidDiagramPreparationFailure, .tooManyPathElements(limit: limit), file: file, line: line)
        }
        XCTAssertNil(PreparedNarrowScene(layingOut: { refused }).scene, file: file, line: line)
        XCTAssertNil(scene(.standard).exceededPathElementLimit, file: file, line: line)
    }

    /// Every documentation example of `examples` prepared under the standard limits has a whole scene and narrow scene.
    private func assertPreparedWhole(_ examples: [String], file: StaticString = #filePath, line: UInt = #line) throws {
        var preparedCount = 0
        for source in examples {
            guard let prepared = try? MermaidDiagramPreparation.prepare(source: source, typography: typography) else { continue }
            XCTAssertNil(prepared.scene.exceededPathElementLimit, file: file, line: line)
            XCTAssertNil(prepared.narrowScene?.exceededPathElementLimit, file: file, line: line)
            preparedCount += 1
        }
        XCTAssertGreaterThan(preparedCount, 0, file: file, line: line)
    }

    func testAUseCaseScenePastTheElementLimitIsRefused() throws {
        let examples = try UseCaseCorpus.documentationExamples()
        try assertPreparedWhole(examples)
        guard case .useCase(let diagram) = try MermaidDiagramReader.read(examples[0], limits: .standard) else { return XCTFail("not a use case diagram") }
        let layout = try UseCaseLayoutEngine.layout(diagram, typography: typography)
        let edge = try XCTUnwrap(layout.edges.first)
        let long = UseCaseLayoutEdge(identifier: edge.identifier, path: longPath(from: edge.path.start), dashLengths: edge.dashLengths,
                                     startMark: edge.startMark, endMark: edge.endMark, label: edge.label, labelPatch: edge.labelPatch,
                                     isSemantic: edge.isSemantic, look: edge.look, inkOverFill: edge.inkOverFill, fillUnderMarks: edge.fillUnderMarks,
                                     isCased: edge.isCased)
        let tampered = UseCaseLayout(size: layout.size, font: layout.font, title: layout.title, boundaries: layout.boundaries,
                                     edges: [long] + layout.edges.dropFirst(), nodes: layout.nodes)
        assertRefusedUnderSmallLimitsOnly { limits in DiagramScene(layout: tampered, limits: limits) }
    }

    func testAnAgentFlowScenePastTheElementLimitIsRefused() throws {
        let examples = try AgentFlowCorpus.documentationExamples()
        try assertPreparedWhole(examples)
        guard case .agentFlow(let diagram) = try MermaidDiagramReader.read(examples[0], limits: .standard) else { return XCTFail("not an agent flow") }
        let layout = try AgentFlowLayoutEngine.layout(diagram, typography: typography, limits: .standard)
        let edge = try XCTUnwrap(layout.edges.first)
        let long = AgentFlowLayoutEdge(identifier: edge.identifier, semantic: edge.semantic, isDotted: edge.isDotted, path: longPath(from: edge.path.start),
                                       targetMark: edge.targetMark, text: edge.text, style: edge.style)
        let tampered = AgentFlowLayout(size: layout.size, font: layout.font, title: layout.title, flows: layout.flows, nodes: layout.nodes,
                                       edges: [long] + layout.edges.dropFirst())
        assertRefusedUnderSmallLimitsOnly { limits in DiagramScene(layout: tampered, limits: limits) }
    }

    func testAC4ScenePastTheElementLimitIsRefused() throws {
        let examples = try C4Corpus.documentationExamples()
        try assertPreparedWhole(examples)
        guard case .c4(let diagram) = try MermaidDiagramReader.read(examples[0], limits: .standard) else { return XCTFail("not a C4 diagram") }
        let layout = try C4LayoutEngine.layout(diagram, typography: typography)
        let relation = try XCTUnwrap(layout.relations.first)
        let tampered = layout.replacingPath(ofRelation: 0, with: longPath(from: relation.path.start))
        XCTAssertEqual(tampered.relations.first?.path, longPath(from: relation.path.start))
        XCTAssertEqual(Array(tampered.relations.dropFirst()), Array(layout.relations.dropFirst()))
        assertRefusedUnderSmallLimitsOnly { limits in DiagramScene(layout: tampered, limits: limits) }
    }

    /// The lanes' outlines are one path: lanes enough to pass the limit of the small limits fill it.
    func testASwimlaneScenePastTheElementLimitIsRefused() throws {
        let examples = try SwimlaneCorpus.documentationExamples()
        try assertPreparedWhole(examples)
        guard case .swimlane(let diagram) = try MermaidDiagramReader.read(examples[0], limits: .standard) else { return XCTFail("not a swimlane") }
        let layout = SwimlaneLayoutEngine.layout(diagram, typography: typography)
        let lane = try XCTUnwrap(layout.lanes.first)
        let extraLanes = (0..<(longPathSegmentCount / 5)).map { _ in
            SwimlaneLayoutLane(frame: lane.frame, titleBand: lane.titleBand, title: nil, isTitleTurned: lane.isTitleTurned)
        }
        let tampered = SwimlaneLayout(flowchart: layout.flowchart, lanes: layout.lanes + extraLanes)
        assertRefusedUnderSmallLimitsOnly { limits in DiagramScene(layout: tampered, limits: limits) }
    }
}
