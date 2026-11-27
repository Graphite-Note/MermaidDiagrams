/**
 * File: DiagramSceneStorageIdentifierTests.swift
 * ----------------------------------------------
 * Layer: Tests
 * Description: DiagramScene.storageIdentifier through the public interface only: the same for a scene, its copies and
 *              every read, and different for every other scene alive, even one prepared from the same text.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 27/11/2026
 */

import MermaidDiagrams
import XCTest

final class DiagramSceneStorageIdentifierTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))
    private let flowchart = "flowchart LR\n    A[Hard edge] -->|Link text| B(Round edge)\n    B --> C{Decision}"

    func testAScenesCopiesAndReadsShareItsIdentifier() throws {
        let prepared = try MermaidDiagramPreparation.prepare(source: flowchart, typography: typography)
        let scene = prepared.scene
        let copy = scene
        XCTAssertEqual(scene.storageIdentifier, copy.storageIdentifier)
        XCTAssertEqual(scene.storageIdentifier, prepared.scene.storageIdentifier, "Each read of a prepared diagram's scene is the same scene.")
        // Reading the items makes every path anew, and leaves the scene as it is.
        XCTAssertEqual(scene.items.count, scene.itemCount)
        XCTAssertEqual(scene.storageIdentifier, copy.storageIdentifier)
    }

    func testEveryOtherSceneAliveHasItsOwnIdentifier() throws {
        let texts = [flowchart, flowchart, "pie\n    \"Dogs\" : 386\n    \"Cats\" : 85", "sequenceDiagram\n    Alice->>Bob: Hello"]
        let scenes = try texts.map { text in try MermaidDiagramPreparation.prepare(source: text, typography: typography).scene }
        XCTAssertEqual(Set(scenes.map(\.storageIdentifier)).count, scenes.count,
                       "The same text prepared twice gives two scenes, each with its own identifier while both are alive.")
    }
}
