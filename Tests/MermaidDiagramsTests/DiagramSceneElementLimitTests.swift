/**
 * File: DiagramSceneElementLimitTests.swift
 * -----------------------------------------
 * Layer: Tests
 * Description: A scene one of whose lanes went past its element limit, added to the builder or given back before, says so,
 *              and the preparation refuses it and its narrow form instead of drawing it with shapes missing; a scene of
 *              whole lanes says nothing; the builder's paintings and texts are the scene's, whether it goes on or not.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
import XCTest
@testable import MermaidDiagrams

final class DiagramSceneElementLimitTests: XCTestCase {
    private let font = DiagramFont(postScriptName: nil, size: 16)
    private let smallLimits = MermaidDiagramLimits(maximumSourceBytes: 1_000, maximumNodeCount: 1, maximumEdgeCount: 1, maximumLayoutPointCount: 1)

    /// A lane given one element more than its limit: emptied and marked, holding only what came after.
    private func overflowedLane(in workspace: DiagramSceneWorkspace) -> DiagramPathLane {
        let lane = workspace.makeLane()
        lane.move(to: .zero)
        for index in 0..<workspace.laneElementLimit { lane.addLine(to: CGPoint(x: index, y: 1)) }
        XCTAssertTrue(lane.hasOverflowed)
        return lane
    }

    func testAScenePastItsElementLimitSaysSoAndIsRefused() throws {
        let scene = DiagramSceneWorkspace.withRecording(limits: smallLimits) { workspace in
            var builder = DiagramSceneBuilder(workspace: workspace)
            builder.fill(workspace.rectangle(CGRect(x: 0, y: 0, width: 10, height: 10)), .surface, part: .node)
            builder.stroke(overflowedLane(in: workspace), .line, DiagramStroke(lineWidth: 1), part: .edge)
            return builder.scene(size: CGSize(width: 10, height: 10), font: font)
        }
        let limit = DiagramSceneWorkspace.elementLimit(for: smallLimits)
        XCTAssertEqual(scene.exceededPathElementLimit, limit)
        XCTAssertThrowsError(try MermaidDiagramPreparation.refuseIncomplete(scene, limits: .standard)) { error in
            XCTAssertEqual(error as? MermaidDiagramPreparationFailure, .tooManyPathElements(limit: limit))
            XCTAssertEqual((error as? MermaidDiagramPreparationFailure)?.category, .beyondLimits)
        }
        XCTAssertNil(PreparedNarrowScene(made: scene).scene)
        XCTAssertNil(PreparedNarrowScene(layingOut: { scene }).scene)
    }

    /// A drawing's lane that went past its limit and was given back before the scene was made still counts: what it
    /// held is missing from whatever it was added to.
    func testALaneGivenBackAfterGoingPastItsLimitStillRefusesTheScene() {
        let scene = DiagramSceneWorkspace.withRecording(limits: smallLimits) { workspace in
            var builder = DiagramSceneBuilder(workspace: workspace)
            let kept = workspace.handedOutLaneCount
            let joined = workspace.makeLane()
            joined.addPath(overflowedLane(in: workspace))
            builder.fill(workspace.rectangle(CGRect(x: 0, y: 0, width: 4, height: 4)), .surface, part: .node)
            workspace.giveLanesBack(downTo: kept)
            return builder.scene(size: CGSize(width: 4, height: 4), font: font)
        }
        XCTAssertEqual(scene.exceededPathElementLimit, DiagramSceneWorkspace.elementLimit(for: smallLimits))
    }

    func testAWholeSceneSaysNothingAndTheNextRecordingStartsAfresh() throws {
        _ = DiagramSceneWorkspace.withRecording(limits: smallLimits) { workspace in overflowedLane(in: workspace) }
        let scene = DiagramSceneWorkspace.withRecording(limits: smallLimits) { workspace in
            var builder = DiagramSceneBuilder(workspace: workspace)
            builder.fill(workspace.ellipse(in: CGRect(x: 0, y: 0, width: 10, height: 10)), .surface, part: .node)
            return builder.scene(size: CGSize(width: 10, height: 10), font: font)
        }
        XCTAssertNil(scene.exceededPathElementLimit)
        XCTAssertNoThrow(try MermaidDiagramPreparation.refuseIncomplete(scene, limits: .standard))
        XCTAssertNotNil(PreparedNarrowScene(made: scene).scene)
        var paths = DiagramSceneBuilder()
        paths.fill(CGPath(rect: CGRect(x: 0, y: 0, width: 2, height: 2), transform: nil), .surface, part: .node)
        XCTAssertNil(paths.scene(size: CGSize(width: 2, height: 2), font: font).exceededPathElementLimit)
    }

    /// A scene made while a run is open, and the builder going on afterwards, outlining that run and adding texts: the
    /// first scene keeps the paintings and texts it was made with, the second has the builder's later ones.
    func testAScenesPaintingsAndTextsStayAsMadeWhenTheBuilderGoesOn() throws {
        let typography = DiagramSceneSamples.typography
        let label = DiagramTextBlock(label: DiagramLabelDecoder.label(from: "label", form: .plain), measurer: typography.measurer(ofSize: 14),
                                     maximumWidth: 200)
        let square = CGPath(rect: CGRect(x: 0, y: 0, width: 10, height: 10), transform: nil)
        var builder = DiagramSceneBuilder()
        builder.text(label, .foreground, part: .label)
        builder.fill(square, .surface, part: .node)
        let first = builder.scene(size: CGSize(width: 10, height: 10), font: font)
        builder.stroke(square, .border, DiagramStroke(lineWidth: 1), part: .node)
        builder.text(label, .muted, part: .label)
        let second = builder.scene(size: CGSize(width: 10, height: 10), font: font)
        XCTAssertEqual(first.shapes.map(\.painting), [.fill(.surface)])
        XCTAssertEqual(first.texts.map(\.paint), [.foreground])
        XCTAssertEqual(second.shapes.map(\.painting), [.fillAndStroke(.surface, .border, DiagramStroke(lineWidth: 1))])
        XCTAssertEqual(second.texts.map(\.paint), [.foreground, .muted])
        XCTAssertEqual(first.itemCount, 2)
        XCTAssertEqual(second.itemCount, 3)
    }
}
