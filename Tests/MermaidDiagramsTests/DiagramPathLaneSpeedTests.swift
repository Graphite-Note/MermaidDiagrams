/**
 * File: DiagramPathLaneSpeedTests.swift
 * -------------------------------------
 * Layer: Tests
 * Description: A flowchart-like scene's paths built in lanes are the Core Graphics paths built by the same calls, and how
 *              long each takes, printed: rounded rectangles filled and outlined, curved edges, arrowheads and label
 *              patches, read back and bounded as a scene reads them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
import XCTest
@testable import MermaidDiagrams

final class DiagramPathLaneSpeedTests: XCTestCase {
    /// Eight nodes on a grid of fractional points, as a flowchart lays them out.
    private static let nodeFrames = (0..<8).map { index in
        CGRect(x: 20 + Double(index % 3) * 140.25, y: 30 + Double(index / 3) * 90.5, width: 96.125, height: 44)
    }

    /// The scene's five paths with Core Graphics: label patches, edges, arrowheads, fills and outlines.
    private static func coreGraphicsPaths() -> [CGMutablePath] {
        let patches = CGMutablePath(), edges = CGMutablePath(), marks = CGMutablePath(), fills = CGMutablePath(), outlines = CGMutablePath()
        for frame in nodeFrames {
            let shape = CGPath(roundedRect: frame, cornerWidth: 5, cornerHeight: 5, transform: nil)
            fills.addPath(shape)
            outlines.addPath(shape)
            edges.move(to: CGPoint(x: frame.midX, y: frame.maxY))
            edges.addCurve(to: CGPoint(x: frame.midX + 30, y: frame.maxY + 40), control1: CGPoint(x: frame.midX, y: frame.maxY + 20),
                           control2: CGPoint(x: frame.midX + 30, y: frame.maxY + 20))
            marks.addLines(between: [CGPoint(x: frame.midX + 26, y: frame.maxY + 34), CGPoint(x: frame.midX + 30, y: frame.maxY + 40),
                                     CGPoint(x: frame.midX + 34, y: frame.maxY + 34)])
            marks.closeSubpath()
            patches.addPath(CGPath(roundedRect: frame.insetBy(dx: 20, dy: 14), cornerWidth: 3, cornerHeight: 3, transform: nil))
        }
        return [patches, edges, marks, fills, outlines]
    }

    /// The same paths in lanes of `workspace`.
    private static func lanes(in workspace: DiagramSceneWorkspace) -> [DiagramPathLane] {
        let lanes = (0..<5).map { _ in workspace.makeLane() }
        for frame in nodeFrames {
            lanes[3].addPathOfRoundedRect(frame, cornerWidth: 5, cornerHeight: 5)
            lanes[4].addPathOfRoundedRect(frame, cornerWidth: 5, cornerHeight: 5)
            lanes[1].move(to: CGPoint(x: frame.midX, y: frame.maxY))
            lanes[1].addCurve(to: CGPoint(x: frame.midX + 30, y: frame.maxY + 40), control1: CGPoint(x: frame.midX, y: frame.maxY + 20),
                              control2: CGPoint(x: frame.midX + 30, y: frame.maxY + 20))
            lanes[2].addLines(between: [CGPoint(x: frame.midX + 26, y: frame.maxY + 34), CGPoint(x: frame.midX + 30, y: frame.maxY + 40),
                                        CGPoint(x: frame.midX + 34, y: frame.maxY + 34)])
            lanes[2].closeSubpath()
            lanes[0].addPathOfRoundedRect(frame.insetBy(dx: 20, dy: 14), cornerWidth: 3, cornerHeight: 3)
        }
        return lanes
    }

    func testAFlowchartLikeScenesLanesAreItsCoreGraphicsPaths() {
        let references = Self.coreGraphicsPaths()
        DiagramSceneWorkspace.withRecording { workspace in
            for (lane, reference) in zip(Self.lanes(in: workspace), references) {
                assertSameAsCoreGraphics(lane, reference, "flowchart-like scene")
            }
        }
    }

    /// Prints the time of one scene built, bounded and read back with Core Graphics and with lanes, medians of
    /// alternating rounds; meaningful in an optimized build (`swift test -c release -Xswiftc -enable-testing`).
    func testTimeAFlowchartLikeSceneWithLanesAndWithCoreGraphics() {
        let rounds = 2_000
        var coreGraphicsTimes: [Double] = [], laneTimes: [Double] = []
        var sink: CGFloat = 0
        for _ in 0..<7 {
            coreGraphicsTimes.append(Self.microseconds(rounds: rounds) {
                for path in Self.coreGraphicsPaths() {
                    sink += path.boundingBoxOfPath.width
                    path.applyWithBlock { element in sink += element.pointee.points[0].x }
                }
            })
            laneTimes.append(Self.microseconds(rounds: rounds) {
                DiagramSceneWorkspace.withRecording { workspace in
                    for lane in Self.lanes(in: workspace) {
                        sink += lane.boundsOfPath.width
                        lane.forEachElement { _, points in sink += points[0].x }
                    }
                }
            })
        }
        let coreGraphics = coreGraphicsTimes.sorted()[3], lanes = laneTimes.sorted()[3]
        print(String(format: "flowchart-like scene: Core Graphics %.2f µs, lanes %.2f µs, %.2fx [%.0f]", coreGraphics, lanes, coreGraphics / lanes, sink.sign == .minus ? 1 : 0))
    }

    private static func microseconds(rounds: Int, _ body: () -> Void) -> Double {
        let clock = ContinuousClock()
        let start = clock.now
        for _ in 0..<rounds { body() }
        let elapsed = clock.now - start
        return (Double(elapsed.components.seconds) * 1e6 + Double(elapsed.components.attoseconds) / 1e12) / Double(rounds)
    }
}
