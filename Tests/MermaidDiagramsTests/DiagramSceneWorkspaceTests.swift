/**
 * File: DiagramSceneWorkspaceTests.swift
 * --------------------------------------
 * Layer: Tests
 * Description: The thread's scene workspace hands out lanes that keep their blocks between recordings, gives a recording
 *              begun inside another a workspace of its own, frees blocks grown past a mebibyte, empties and marks a lane
 *              that goes past its element limit instead of growing without bound, and keeps one workspace per thread;
 *              and the sines, cosines and angles the lanes look up are the system's own.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
import Darwin
import XCTest
@testable import MermaidDiagrams

final class DiagramSceneWorkspaceTests: XCTestCase {
    /// A second recording on the thread reuses the first one's lane states, emptied, with their blocks.
    func testLanesAreGivenBackEmptyAndReused() {
        let firstCount = DiagramSceneWorkspace.withRecording { workspace in
            for _ in 0..<5 {
                let lane = workspace.makeLane()
                for index in 0..<200 { lane.addLine(to: CGPoint(x: index, y: index)) }
                lane.move(to: .zero)
            }
            return workspace.pooledLaneCount
        }
        DiagramSceneWorkspace.withRecording { workspace in
            XCTAssertEqual(workspace.pooledLaneCount, firstCount)
            let lane = workspace.makeLane()
            XCTAssertTrue(lane.isEmpty)
            XCTAssertEqual(lane.boundsOfPath, .null)
            XCTAssertEqual(workspace.pooledLaneCount, firstCount)
        }
    }

    /// A recording begun while the thread's workspace records (a narrow scene read while another records) gets a
    /// workspace of its own, so the outer recording's lanes are left as they were.
    func testARecordingInsideAnotherHasAWorkspaceOfItsOwn() {
        DiagramSceneWorkspace.withRecording { outer in
            let lane = outer.rectangle(CGRect(x: 1, y: 2, width: 3, height: 4))
            DiagramSceneWorkspace.withRecording { inner in
                XCTAssertFalse(inner === outer)
                let other = inner.makeLane()
                other.addEllipse(in: CGRect(x: 0, y: 0, width: 10, height: 10))
            }
            XCTAssertEqual(lane.boundsOfPath, CGRect(x: 1, y: 2, width: 3, height: 4))
            XCTAssertTrue(DiagramSceneWorkspace.current === outer)
        }
    }

    /// Each thread has its own workspace, kept from one recording to the next.
    func testEachThreadHasItsOwnWorkspace() {
        let here = ObjectIdentifier(DiagramSceneWorkspace.current)
        XCTAssertEqual(ObjectIdentifier(DiagramSceneWorkspace.current), here)
        let finished = expectation(description: "the other thread's workspace")
        let thread = Thread {
            let there = ObjectIdentifier(DiagramSceneWorkspace.current)
            XCTAssertNotEqual(there, here)
            XCTAssertEqual(ObjectIdentifier(DiagramSceneWorkspace.current), there)
            finished.fulfill()
        }
        thread.start()
        wait(for: [finished], timeout: 10)
    }

    /// A lane grown past a mebibyte by one scene is freed when the recording ends, so a thread keeps at most that much
    /// a lane between scenes.
    func testBlocksGrownPastTheLimitAreFreedAfterTheRecording() {
        DiagramSceneWorkspace.withRecording { workspace in
            let lane = workspace.makeLane()
            lane.move(to: .zero)
            for index in 0..<100_000 { lane.addCurve(to: CGPoint(x: index, y: 1), control1: .zero, control2: CGPoint(x: 1, y: index)) }
            XCTAssertGreaterThan(workspace.pooledByteCount, DiagramSceneWorkspace.largestKeptByteCount)
        }
        DiagramSceneWorkspace.withRecording { workspace in
            XCTAssertLessThanOrEqual(workspace.pooledByteCount, workspace.pooledLaneCount * DiagramSceneWorkspace.largestKeptByteCount)
            XCTAssertLessThan(workspace.pooledByteCount, 64 * 1_024)
        }
    }

    /// A lane given more elements than its limit is emptied and marked, without trapping, and so are its additions of
    /// itself, which double it each time; the next recording's lanes are unmarked.
    func testALanePastItsLimitIsMarkedInsteadOfGrowingWithoutBound() {
        let limits = MermaidDiagramLimits(maximumSourceBytes: 1_000, maximumNodeCount: 1, maximumEdgeCount: 1, maximumLayoutPointCount: 1)
        let elementLimit = DiagramSceneWorkspace.elementLimit(for: limits)
        XCTAssertEqual(elementLimit, 1 << 16)
        DiagramSceneWorkspace.withRecording(limits: limits) { workspace in
            let lane = workspace.makeLane()
            lane.move(to: .zero)
            for index in 0..<(elementLimit + 10) { lane.addLine(to: CGPoint(x: index, y: 0)) }
            XCTAssertTrue(lane.hasOverflowed)
            XCTAssertTrue(workspace.anyLaneOverflowed)
            let doubling = workspace.makeLane()
            doubling.addRoundedRect(in: CGRect(x: 0, y: 0, width: 20, height: 10), cornerWidth: 3, cornerHeight: 3)
            for _ in 0..<40 { doubling.addPath(doubling) }
            XCTAssertTrue(doubling.hasOverflowed)
            _ = doubling.boundsOfPath
            doubling.forEachElement { _, _ in }
        }
        DiagramSceneWorkspace.withRecording(limits: limits) { workspace in
            XCTAssertFalse(workspace.makeLane().hasOverflowed)
            XCTAssertFalse(workspace.anyLaneOverflowed)
        }
        XCTAssertEqual(DiagramSceneWorkspace.elementLimit(for: MermaidDiagramLimits(maximumSourceBytes: .max, maximumNodeCount: .max,
                                                                                     maximumEdgeCount: .max, maximumLayoutPointCount: .max)), 1 << 24)
    }

    /// A bounds asked once is kept and asked again after the lane changes.
    func testBoundsAreWorkedOutAgainAfterAChange() {
        DiagramSceneWorkspace.withRecording { workspace in
            let lane = workspace.makeLane()
            lane.move(to: CGPoint(x: 1, y: 1))
            lane.addLine(to: CGPoint(x: 5, y: 3))
            XCTAssertEqual(lane.boundsOfPath, CGRect(x: 1, y: 1, width: 4, height: 2))
            lane.addQuadCurve(to: CGPoint(x: 9, y: 3), control: CGPoint(x: 7, y: 11))
            XCTAssertEqual(lane.boundsOfPath, CGPath.boundsReference { path in
                path.move(to: CGPoint(x: 1, y: 1))
                path.addLine(to: CGPoint(x: 5, y: 3))
                path.addQuadCurve(to: CGPoint(x: 9, y: 3), control: CGPoint(x: 7, y: 11))
            })
            lane.closeSubpath()
            lane.addEllipse(in: CGRect(x: -10, y: -10, width: 4, height: 4))
            XCTAssertEqual(lane.boundsOfPath.minX, -10)
        }
    }
}

/// The values the lanes look up instead of calling the system: they must be the system's own.
final class DiagramPathArithmeticTests: XCTestCase {
    func testLookedUpSinesAndCosinesAreTheSystems() {
        for angle in [CGFloat.pi / 2, .pi, -CGFloat.pi / 2, -.pi, 0] {
            let looked = DiagramPathArithmetic.sineAndCosine(of: angle)
            let system = __sincos_stret(angle)
            XCTAssertEqual(Double(looked.sine).bitPattern, system.__sinval.bitPattern, "\(angle)")
            XCTAssertEqual(Double(looked.cosine).bitPattern, system.__cosval.bitPattern, "\(angle)")
        }
        XCTAssertEqual(DiagramPathArithmetic.halfPi, CGFloat.pi / 2)
        XCTAssertEqual(DiagramPathArithmetic.quarterPi, CGFloat.pi / 2 * 0.5)
        XCTAssertEqual(DiagramPathArithmetic.sine(of: DiagramPathArithmetic.quarterPi), sin(CGFloat.pi / 2 * 0.5))
        XCTAssertEqual(DiagramPathArithmetic.cosine(of: DiagramPathArithmetic.quarterPi), cos(CGFloat.pi / 2 * 0.5))
        var samples = DiagramPathLaneSamples(seed: 0x51_4E)
        for _ in 0..<20_000 {
            let angle = samples.angle()
            let looked = DiagramPathArithmetic.sineAndCosine(of: angle)
            let system = __sincos_stret(angle)
            XCTAssertEqual(Double(looked.sine).bitPattern, system.__sinval.bitPattern, "\(angle)")
            XCTAssertEqual(Double(looked.cosine).bitPattern, system.__cosval.bitPattern, "\(angle)")
        }
    }

    func testAnglesAlongAnAxisAreAtan2s() {
        let lengths: [CGFloat] = [0, -0.0, 1, -1, 3.5, -1e-300, 1e300, .nan, .infinity, -.infinity, 4.440892098500626e-16]
        for across in lengths {
            for down in lengths {
                let looked = DiagramPathArithmetic.angle(across: across, down: down)
                let system = atan2(down, across)
                XCTAssertTrue(looked.bitPattern == system.bitPattern || (looked.isNaN && system.isNaN), "\(across) \(down)")
            }
        }
    }

    /// The fused minimum and maximum are the processor's `fminnm` and `fmaxnm`, as C's `fmin` and `fmax` give them.
    func testFusedMinimumAndMaximumAreTheSystems() {
        let values: [CGFloat] = [0, -0.0, 1, -1, .nan, .infinity, -.infinity, 2.5]
        for first in values {
            for second in values {
                let minimum = DiagramPathArithmetic.minimum(first, second), maximum = DiagramPathArithmetic.maximum(first, second)
                XCTAssertTrue(minimum.bitPattern == fmin(first, second).bitPattern || (minimum.isNaN && fmin(first, second).isNaN), "\(first) \(second)")
                XCTAssertTrue(maximum.bitPattern == fmax(first, second).bitPattern || (maximum.isNaN && fmax(first, second).isNaN), "\(first) \(second)")
            }
        }
    }
}

private extension CGPath {
    static func boundsReference(_ build: (CGMutablePath) -> Void) -> CGRect {
        let path = CGMutablePath()
        build(path)
        return path.boundingBoxOfPath
    }
}
