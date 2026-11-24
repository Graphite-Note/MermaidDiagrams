/**
 * File: GraphTypeSceneLaneTests.swift
 * -----------------------------------
 * Layer: Tests
 * Description: The scenes of state diagrams, their paths recorded into lanes, are element for element and bit for bit
 *              the scenes 0.7.0 made from Core Graphics paths, for every diagram of the corpora and random ones, as they
 *              run and fitted to a narrow column.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class GraphTypeSceneLaneTests: XCTestCase {
    private let typography = DiagramSceneSamples.typography

    /// A scene's items as text: each shape's part, painting and every element's bits, each text's part, paint and place.
    static func transcript(of scene: DiagramScene) -> [String] {
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
                lines.append("text \(text.part.rawValue) \(text.paint) \(text.isBold) \(text.block.center.x.bitPattern),\(text.block.center.y.bitPattern) "
                             + "\(text.block.lineCount) \(String(describing: text.rotation))")
            }
        }
        return lines
    }

    /// Compares the scenes of `source` when it is one of the types these tests cover; false otherwise.
    private func assertSameScenes(_ source: String, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        guard let diagram = try? MermaidDiagramReader.read(source, limits: .standard) else { return false }
        switch diagram {
        case .stateDiagram(let stateDiagram):
            guard let layout = try? StateDiagramLayoutEngine.layout(stateDiagram, typography: typography, limits: .standard) else { return false }
            XCTAssertEqual(Self.transcript(of: DiagramScene(layout: layout)), Self.transcript(of: ReferenceStateDiagramScene.scene(layout: layout)),
                           file: file, line: line)
            if let narrow = try? StateDiagramLayoutEngine.layout(stateDiagram, typography: typography, limits: .standard, availableWidth: 280) {
                XCTAssertEqual(Self.transcript(of: DiagramScene(layout: narrow)), Self.transcript(of: ReferenceStateDiagramScene.scene(layout: narrow)),
                               file: file, line: line)
            }
        default:
            return false
        }
        return true
    }

    func testStateScenesOfEveryCorpusAreThoseMadeFromCoreGraphicsPaths() throws {
        var comparedCount = 0
        for (_, sources) in try OutputDigest.corpora() {
            for source in sources where assertSameScenes(source) { comparedCount += 1 }
        }
        for source in try StateDiagramCorpus.documentationExamples() where assertSameScenes(source) { comparedCount += 1 }
        XCTAssertGreaterThan(comparedCount, 40)
    }

    func testStateScenesOfRandomDiagramsAreThoseMadeFromCoreGraphicsPaths() {
        var texts = StateRandomTexts(seed: 0x5CE_57A7)
        var comparedCount = 0
        for index in 0..<1_500 where assertSameScenes(texts.text(statementCount: 2 + index % 30)) { comparedCount += 1 }
        XCTAssertGreaterThan(comparedCount, 600)
    }
}
