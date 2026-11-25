/**
 * File: SequenceLayoutMovingTests.swift
 * -------------------------------------
 * Layer: Tests
 * Description: A sequence layout's participants, boxes, highlights, blocks and notes moved where they stand
 *              (translate(by:)) are, bit for bit, what making them again moved (translated(by:)) gives, on every corpus
 *              input of sequence diagrams laid out regular and tight, by offsets of every sign and fraction.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import CoreGraphics
import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class SequenceLayoutMovingTests: XCTestCase {
    private let typography = DiagramSceneSamples.typography
    private static let offsets = [CGVector(dx: 8, dy: 8), CGVector(dx: -13.375, dy: 0.1), CGVector(dx: 0.3, dy: -1e-9), CGVector(dx: 1e6, dy: -2.5e-3)]

    /// The sequence layouts of every corpus input, regular and in a column 280 points wide.
    private func layouts() throws -> [SequenceLayout] {
        try OutputDigest.corpora().flatMap(\.sources).flatMap { source -> [SequenceLayout] in
            guard case .sequence(let diagram)? = try? MermaidDiagramReader.read(source, limits: .standard) else { return [] }
            return [try? SequenceLayoutEngine.layout(diagram, typography: typography),
                    try? SequenceLayoutEngine.layout(diagram, typography: typography, availableWidth: 280)].compactMap { $0 }
        }
    }

    /// Each moved in place and moved by making it again, for every offset.
    private func assertMovedAlike<Item: Equatable>(_ items: [Item], translate: (inout Item, CGVector) -> Void, translated: (Item, CGVector) -> Item,
                                                   _ name: String, file: StaticString = #filePath, line: UInt = #line) -> Int {
        var count = 0
        for item in items {
            for offset in Self.offsets {
                var moved = item
                translate(&moved, offset)
                XCTAssertEqual(moved, translated(item, offset), "\(name) moved by \(offset)", file: file, line: line)
                count += 1
            }
        }
        return count
    }

    func testPartsMovedWhereTheyStandAreThePartsMadeAgainMoved() throws {
        let layouts = try layouts()
        XCTAssertGreaterThan(layouts.count, 30)
        var blockCount = 0
        var sectionCount = 0
        for layout in layouts {
            _ = assertMovedAlike(layout.participants, translate: { $0.translate(by: $1) }, translated: { $0.translated(by: $1) }, "participant")
            _ = assertMovedAlike(layout.boxes, translate: { $0.translate(by: $1) }, translated: { $0.translated(by: $1) }, "box")
            _ = assertMovedAlike(layout.highlights, translate: { $0.translate(by: $1) }, translated: { $0.translated(by: $1) }, "highlight")
            _ = assertMovedAlike(layout.notes, translate: { $0.translate(by: $1) }, translated: { $0.translated(by: $1) }, "note")
            blockCount += assertMovedAlike(layout.blocks, translate: { $0.translate(by: $1) }, translated: { $0.translated(by: $1) }, "block")
            sectionCount += layout.blocks.reduce(0) { total, block in total + block.sections.count }
        }
        // The corpora reach blocks with sections, so the sections' moves are compared too.
        XCTAssertGreaterThan(blockCount, 0)
        XCTAssertGreaterThan(sectionCount, 0)
    }

    /// Equality of text blocks compares their bytes and sizes; the centers are compared here bit for bit, which the
    /// equality above compares as numbers.
    func testCentersMovedWhereTheyStandHaveTheBitsOfTheCentersMadeAgain() throws {
        for layout in try layouts() {
            for block in layout.blocks {
                for offset in Self.offsets {
                    var moved = block
                    moved.translate(by: offset)
                    let again = block.translated(by: offset)
                    XCTAssertEqual(moved.keyword.center.x.bitPattern, again.keyword.center.x.bitPattern)
                    XCTAssertEqual(moved.keyword.center.y.bitPattern, again.keyword.center.y.bitPattern)
                    for (movedSection, againSection) in zip(moved.sections, again.sections) {
                        XCTAssertEqual(movedSection.lineY.bitPattern, againSection.lineY.bitPattern)
                        XCTAssertEqual(movedSection.text?.center.x.bitPattern, againSection.text?.center.x.bitPattern)
                        XCTAssertEqual(movedSection.text?.center.y.bitPattern, againSection.text?.center.y.bitPattern)
                    }
                }
            }
        }
    }
}
