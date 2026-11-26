/**
 * File: ArchitectureFlatTableTests.swift
 * --------------------------------------
 * Layer: Tests
 * Description: Checks the architecture grid's flat tables against a dictionary over random keys, rounds and growth, and
 *              that keys built to share their slots' low bits are still told apart quickly.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import Foundation
import XCTest
@testable import MermaidDiagrams

final class ArchitectureFlatTableTests: XCTestCase {
    func testCellsAndSlidesAreKeptAsADictionaryKeepsThem() {
        var random = MapReadingMutations(seed: 0xF1A7, tokens: [])
        var cells = ArchitectureFlatTable(emptyKey: ArchitectureCellKey(column: 0, row: 0))
        var slides = ArchitectureFlatTable(emptyKey: ArchitectureSlideKey(column: 0, row: 0, width: 0, height: 0, stepX: 0, stepY: 0))
        var expectedCells: [Int: Int] = [:]
        var expectedSlides: [ArchitectureSlideKey: Int] = [:]
        for step in 0..<200_000 {
            if random.below(5_000) == 0 {
                cells.removeAll()
                slides.removeAll()
                expectedCells.removeAll()
                expectedSlides.removeAll()
            }
            let column = random.below(80) - 40
            let row = random.below(80) - 40
            let cellKey = (column + 1_000) * 10_000 + row + 1_000
            if random.below(2) == 0 {
                cells.set(step, for: ArchitectureCellKey(column: column, row: row))
                expectedCells[cellKey] = step
            }
            XCTAssertEqual(cells.value(of: ArchitectureCellKey(column: column, row: row)), expectedCells[cellKey])
            let slide = ArchitectureSlideKey(column: column, row: row, width: 1 + random.below(3), height: 1 + random.below(3), stepX: random.below(3) - 1,
                                             stepY: random.below(3) - 1)
            if random.below(2) == 0 {
                slides.set(step, for: slide)
                expectedSlides[slide] = step
            }
            XCTAssertEqual(slides.value(of: slide), expectedSlides[slide])
        }
        XCTAssertEqual(cells.count, expectedCells.count)
        XCTAssertEqual(slides.count, expectedSlides.count)
    }

    func testRoundsOutlastTheirCounterWrapping() {
        var cells = ArchitectureFlatTable(emptyKey: ArchitectureCellKey(column: 0, row: 0))
        for round in 0..<70_000 {
            cells.removeAll()
            XCTAssertNil(cells.value(of: ArchitectureCellKey(column: round - 1, row: 0)))
            cells.set(round, for: ArchitectureCellKey(column: round, row: 0))
            XCTAssertEqual(cells.value(of: ArchitectureCellKey(column: round, row: 0)), round)
        }
    }

    /// Cells whose mixed bits share their low twelve bits all start probing at one slot of a table of 4,096 slots: they
    /// are still found, and 2,000 of them are kept and read back quickly.
    func testCellsThatShareTheirSlotsAreToldApart() {
        var colliding: [ArchitectureCellKey] = []
        var column = 0
        while colliding.count < 2_000 {
            for row in 0..<4_096 {
                let key = ArchitectureCellKey(column: column, row: row)
                if key.mixedBits & 0xFFF == 0x5A5 { colliding.append(key) }
            }
            column += 1
        }
        let start = Date()
        var cells = ArchitectureFlatTable(emptyKey: ArchitectureCellKey(column: 0, row: 0))
        for (index, key) in colliding.enumerated() { cells.set(index, for: key) }
        for (index, key) in colliding.enumerated() { XCTAssertEqual(cells.value(of: key), index) }
        XCTAssertNil(cells.value(of: ArchitectureCellKey(column: -1, row: -1)))
        XCTAssertLessThan(Date().timeIntervalSince(start), 10)
    }
}
