/**
 * File: FlowchartSceneLaneTests.swift
 * -----------------------------------
 * Layer: Tests
 * Description: The flowchart, swimlane and agent flow scenes recorded into lanes are, item for item and element for
 *              element, the scenes 0.7.0 made from Core Graphics paths, on every corpus, thousands of random flowcharts
 *              and the narrow layouts; a shape held whole added to two lanes at once is added as two calls add it; and
 *              the lanes a scene makes for a moment go back to the thread's pool.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class FlowchartSceneLaneTests: XCTestCase {
    private let typography = DiagramSceneSamples.typography

    /// A scene's items as text: each shape's part, painting and every element's bits, each text's part and place.
    private func transcript(of scene: DiagramScene) -> [String] {
        var lines = ["\(scene.size.width.bitPattern) \(scene.size.height.bitPattern) \(scene.itemCount)"]
        scene.forEachItem { item in
            switch item {
            case .shape(let shape):
                var line = "shape \(shape.part.rawValue) \(shape.painting)"
                shape.forEachElement { verb, points in
                    line += " \(verb.rawValue)"
                    for index in 0..<verb.pointCount { line += ":\(points[index].x.bitPattern),\(points[index].y.bitPattern)" }
                }
                lines.append(line)
            case .text(let text):
                lines.append("text \(text.part.rawValue) \(text.paint) \(text.block.center) \(text.block.lineCount) \(String(describing: text.rotation))")
            }
        }
        return lines
    }

    private func assertSameScenes(_ source: String, file: StaticString = #filePath, line: UInt = #line) throws -> Bool {
        guard let diagram = try? MermaidDiagramReader.read(source, limits: .standard) else { return false }
        switch diagram {
        case .flowchart(let flowchart):
            guard let layout = try? FlowchartLayoutEngine.layout(flowchart, typography: typography, limits: .standard) else { return false }
            XCTAssertEqual(transcript(of: DiagramScene(layout: layout)), transcript(of: ReferenceFlowchartScene.scene(layout: layout)), file: file, line: line)
            if let narrow = try? FlowchartLayoutEngine.layout(flowchart, typography: typography, limits: .standard, availableWidth: 280) {
                XCTAssertEqual(transcript(of: DiagramScene(layout: narrow)), transcript(of: ReferenceFlowchartScene.scene(layout: narrow)), file: file, line: line)
            }
        case .swimlane(let flowchart):
            let layout = SwimlaneLayoutEngine.layout(flowchart, typography: typography)
            XCTAssertEqual(transcript(of: DiagramScene(layout: layout)), transcript(of: ReferenceSwimlaneScene.scene(layout: layout)), file: file, line: line)
        case .agentFlow(let agentFlow):
            guard let layout = try? AgentFlowLayoutEngine.layout(agentFlow, typography: typography, limits: .standard) else { return false }
            XCTAssertEqual(transcript(of: DiagramScene(layout: layout)), transcript(of: ReferenceAgentFlowScene.scene(layout: layout)), file: file, line: line)
        default:
            return false
        }
        return true
    }

    func testScenesOfEveryCorpusAreThoseMadeFromCoreGraphicsPaths() throws {
        var comparedCount = 0
        for (_, sources) in try OutputDigest.corpora() {
            for source in sources where try assertSameScenes(source) { comparedCount += 1 }
        }
        XCTAssertGreaterThan(comparedCount, 300, "flowcharts, swimlanes and agent flows of the corpora compared")
    }

    func testScenesOfRandomFlowchartsAreThoseMadeFromCoreGraphicsPaths() throws {
        var texts = FlowchartRandomTexts(seed: 0x5CE_7E_1A)
        var comparedCount = 0
        for index in 0..<2_500 where try assertSameScenes(texts.text(statementCount: 2 + index % 40)) { comparedCount += 1 }
        XCTAssertGreaterThan(comparedCount, 1_000)
    }

    /// A shape held whole added to two lanes at once gets the elements two calls of `addPath(_:)` give, which are Core
    /// Graphics' own, whatever the lanes hold: nothing, a shape held whole, elements ending with a move, with a close or
    /// with a line.
    func testAShapeAddedToTwoLanesAtOnceIsAddedAsTwoCallsAddIt() {
        DiagramSceneWorkspace.withRecording { workspace in
            for shape in SampleShape.allCases {
                for firstStart in SampleStart.allCases {
                    for secondStart in SampleStart.allCases {
                        let coreGraphics = DiagramCoreGraphicsPaths()
                        let expectedFirst = coreGraphics.makePath()
                        let expectedSecond = coreGraphics.makePath()
                        firstStart.record(into: expectedFirst, making: coreGraphics)
                        secondStart.record(into: expectedSecond, making: coreGraphics)
                        let expectedShape = shape.made(by: coreGraphics)
                        expectedFirst.addPath(expectedShape)
                        expectedSecond.addPath(expectedShape)
                        let first = workspace.makeLane()
                        let second = workspace.makeLane()
                        firstStart.record(into: first, making: workspace)
                        secondStart.record(into: second, making: workspace)
                        first.addPath(shape.made(by: workspace), alsoTo: second)
                        let label = "\(shape) added to lanes holding \(firstStart) and \(secondStart)"
                        XCTAssertEqual(elements(of: first.makePath()), elements(of: expectedFirst.path), label)
                        XCTAssertEqual(elements(of: second.makePath()), elements(of: expectedSecond.path), label)
                        XCTAssertEqual(first.boundsOfPath, expectedFirst.path.boundingBoxOfPath, label)
                        XCTAssertEqual(second.boundsOfPath, expectedSecond.path.boundingBoxOfPath, label)
                        XCTAssertEqual(second.currentPoint, expectedSecond.path.currentPoint, label)
                    }
                }
            }
        }
    }

    /// Lanes made for a moment while a flowchart's scene records go back to the pool, so that the pool holds about as
    /// many lanes for a flowchart of 600 nodes as for one of 6.
    func testLanesMadeForAMomentGoBackToThePool() throws {
        func pooledLaneCount(nodeCount: Int) throws -> Int {
            var source = "flowchart TD\n  classDef warm fill:#fca\n"
            for index in 0..<nodeCount { source += "  n\(index)([node \(index)]) --> n\(index + 1){{next}}:::warm\n" }
            guard case .flowchart(let flowchart) = try MermaidDiagramReader.read(source, limits: .standard) else { throw XCTSkip("not a flowchart") }
            let layout = try FlowchartLayoutEngine.layout(flowchart, typography: typography, limits: .standard)
            var count = 0
            DiagramSceneWorkspace.withRecording { workspace in
                var builder = DiagramSceneBuilder(workspace: workspace)
                FlowchartSceneRecording.add(layout, to: &builder, workspace: workspace)
                count = workspace.pooledLaneCount
            }
            return count
        }
        XCTAssertLessThanOrEqual(try pooledLaneCount(nodeCount: 600), try pooledLaneCount(nodeCount: 6) + 2)
    }

    private func elements(of path: CGPath) -> [String] {
        var elements: [String] = []
        path.applyWithBlock { element in
            var count = 0
            switch element.pointee.type {
            case .moveToPoint, .addLineToPoint: count = 1
            case .addQuadCurveToPoint: count = 2
            case .addCurveToPoint: count = 3
            default: count = 0
            }
            elements.append("\(element.pointee.type.rawValue)" + (0..<count).map { index in
                ":\(element.pointee.points[index].x.bitPattern),\(element.pointee.points[index].y.bitPattern)"
            }.joined())
        }
        return elements
    }
}

/// A shape Core Graphics holds whole.
private enum SampleShape: CaseIterable {
    case roundedRectangle, ellipse, rectangle

    func made<Maker: DiagramPathMaking>(by maker: Maker) -> Maker.Path {
        switch self {
        case .roundedRectangle: maker.roundedRectangle(CGRect(x: 1.5, y: 2.25, width: 40, height: 17), cornerWidth: 4, cornerHeight: 4)
        case .ellipse: maker.ellipse(in: CGRect(x: -3, y: 7, width: 9.5, height: 4))
        case .rectangle: maker.rectangle(CGRect(x: 2, y: 3, width: 5, height: 6))
        }
    }
}

/// What a lane holds before a shape is added to it.
private enum SampleStart: CaseIterable {
    case nothing, heldShape, loneMove, closedLine, openLine

    func record<Maker: DiagramPathMaking>(into path: Maker.Path, making maker: Maker) {
        switch self {
        case .nothing: break
        case .heldShape: path.addPath(maker.roundedRectangle(CGRect(x: 50, y: 0, width: 30, height: 10), cornerWidth: 3, cornerHeight: 3))
        case .loneMove: path.move(to: CGPoint(x: 9, y: 9))
        case .closedLine:
            path.move(to: CGPoint(x: 1, y: 1))
            path.addLine(to: CGPoint(x: 4, y: 1))
            path.closeSubpath()
        case .openLine:
            path.move(to: CGPoint(x: 1, y: 1))
            path.addLine(to: CGPoint(x: 4, y: 7))
        }
    }
}
