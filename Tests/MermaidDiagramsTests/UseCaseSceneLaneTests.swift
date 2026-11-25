/**
 * File: UseCaseSceneLaneTests.swift
 * ---------------------------------
 * Layer: Tests
 * Description: The scene of a use case diagram, its paths recorded into lanes, is element for element and bit for bit
 *              the scene 0.7.0 made from Core Graphics paths, for every diagram of the corpora, generated and random
 *              ones, as they run and turned to run down for a narrow column; its lanes all go back to the pool.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import CoreGraphics
import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class UseCaseSceneLaneTests: XCTestCase {
    private let typography = DiagramSceneSamples.typography

    /// Compares the scenes of `source` when it is a use case diagram; false otherwise.
    private func assertSameScenes(_ source: String, readingLimits: MermaidDiagramLimits = .standard, file: StaticString = #filePath,
                                  line: UInt = #line) -> Bool {
        guard case .useCase(let diagram)? = try? MermaidDiagramReader.read(source, limits: readingLimits),
              let layout = try? UseCaseLayoutEngine.layout(diagram, typography: typography) else { return false }
        XCTAssertEqual(GraphTypeSceneLaneTests.transcript(of: DiagramScene(layout: layout)),
                       GraphTypeSceneLaneTests.transcript(of: ReferenceUseCaseScene.scene(layout: layout)), file: file, line: line)
        if let turned = diagram.turnedToRunDown, let narrow = try? UseCaseLayoutEngine.layout(turned, typography: typography) {
            XCTAssertEqual(GraphTypeSceneLaneTests.transcript(of: DiagramScene(layout: narrow)),
                           GraphTypeSceneLaneTests.transcript(of: ReferenceUseCaseScene.scene(layout: narrow)), file: file, line: line)
        }
        return true
    }

    func testScenesOfEveryCorpusAreThoseMadeFromCoreGraphicsPaths() throws {
        var comparedCount = 0
        for (_, sources) in try OutputDigest.corpora() {
            for source in sources where assertSameScenes(source) { comparedCount += 1 }
        }
        for source in try UseCaseCorpus.documentationExamples() where assertSameScenes(source) { comparedCount += 1 }
        XCTAssertGreaterThan(comparedCount, 40)
    }

    func testScenesOfGeneratedAndRandomDiagramsAreThoseMadeFromCoreGraphicsPaths() {
        var readingLimits = MermaidDiagramLimits.standard
        readingLimits.maximumSourceBytes = 1_000_000
        for (actors, useCases, boundaries, relationships) in [(3, 8, 1, 12), (10, 40, 4, 80), (20, 120, 6, 260)] {
            let source = UseCaseCorpus.generated(actorCount: actors, useCaseCount: useCases, boundaryCount: boundaries, relationshipCount: relationships)
            XCTAssertTrue(assertSameScenes(source, readingLimits: readingLimits), "\(useCases) use cases")
        }
        var texts = UseCaseRandomTexts(seed: 0x5CE_05E)
        var comparedCount = 0
        for index in 0..<2_000 where assertSameScenes(texts.text(statementCount: 4 + index % 24)) { comparedCount += 1 }
        XCTAssertGreaterThan(comparedCount, 600)
    }

    /// The scene's lanes go back to the thread's pool: a second scene of the same diagram makes no new lane state.
    func testTheScenesLanesGoBackToThePool() throws {
        let source = try XCTUnwrap(UseCaseCorpus.documentationExamples().max { first, second in first.utf8.count < second.utf8.count })
        guard case .useCase(let diagram) = try MermaidDiagramReader.read(source, limits: .standard) else { return XCTFail("not a use case diagram") }
        let layout = try UseCaseLayoutEngine.layout(diagram, typography: typography)
        _ = DiagramScene(layout: layout)
        let pooledCount = DiagramSceneWorkspace.current.pooledLaneCount
        _ = DiagramScene(layout: layout)
        XCTAssertEqual(DiagramSceneWorkspace.current.pooledLaneCount, pooledCount)
        XCTAssertEqual(DiagramSceneWorkspace.current.handedOutLaneCount, 0)
    }
}
