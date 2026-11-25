/**
 * File: WardleyMapLayoutTranslationTests.swift
 * --------------------------------------------
 * Layer: Tests
 * Description: Moving a laid-out Wardley map where the layout keeps it gives the layout 0.7.0's move made anew, on the
 *              layouts of every corpus input and spec text, regular and narrow, with their random changes, by offsets
 *              of every sign and size.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
import XCTest
@testable import MermaidDiagrams

final class WardleyMapLayoutTranslationTests: XCTestCase {
    private let typography = DiagramSceneSamples.typography
    private let offsets = [CGVector(dx: 0, dy: 0), CGVector(dx: 12.5, dy: -3.25), CGVector(dx: -1e-7, dy: 4_000.1), CGVector(dx: 0.1, dy: 0.2)]

    func testMovingInPlaceGivesTheLayoutTheFrozenMoveMakes() throws {
        let texts = MapReadingEquivalence.texts(readAs: .wardleyMap, among: try MapReadingEquivalence.everyText(), mutationCount: 20,
                                                tokens: ["note \"n\" [0.2, 0.3]\n", "annotation 1,[0.2, 0.2] \"a\"\n", "annotations [0.1, 0.1]\n",
                                                         "accelerator X [0.5, 0.5]\n", "pipeline A {\n  component P [0.3]\n}\n", "evolve A 0.9\n"],
                                                seed: 0x7_2A45)
        var comparedCount = 0
        for text in texts {
            guard case .wardleyMap(let map)? = try? MermaidDiagramReader.read(text, limits: .standard) else { continue }
            for layout in [WardleyMapLayoutEngine.layout(map, typography: typography), WardleyMapLayoutEngine.layout(map, typography: typography, fittingWidth: 280)] {
                for offset in offsets {
                    var moved = layout
                    moved.translate(by: offset)
                    XCTAssertEqual(moved, layout.referenceTranslated(by: offset), text)
                }
                comparedCount += 1
            }
        }
        XCTAssertGreaterThan(comparedCount, 300)
    }
}
