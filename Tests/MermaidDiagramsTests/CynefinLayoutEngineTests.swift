/**
 * File: CynefinLayoutEngineTests.swift
 * ------------------------------------
 * Layer: Tests
 * Description: A Cynefin framework's boundaries and layout as Pele's and Mermaid's: the seeded random numbers and hash
 *              (cynefin.spec.ts, and values worked out with JavaScript's 32-bit arithmetic), the waves and the cliff, the
 *              board, the blocks, the ellipse and the transitions.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class CynefinLayoutEngineTests: XCTestCase {
    // MARK: Mermaid's boundary spec, and mulberry32 as JavaScript computes it

    func testSeededRandomNumbersAreMulberry32sFirstStep() {
        XCTAssertEqual(CynefinBoundaries.seededRandom(0), 0.26642920868471265)
        XCTAssertEqual(CynefinBoundaries.seededRandom(42), 0.6011037519201636)
        XCTAssertEqual(CynefinBoundaries.seededRandom(-50), 0.2312965493183583)
        XCTAssertEqual(CynefinBoundaries.seededRandom(999_999), 0.03664584248326719)
        XCTAssertEqual(CynefinBoundaries.seededRandom(150_000_000_000_000.7), 0.5851703947409987, "Truncated and taken modulo 2³², as ToInt32 does")
        for seed in [0.0, 1, 100, 999_999, -50] {
            XCTAssertGreaterThanOrEqual(CynefinBoundaries.seededRandom(seed), 0)
            XCTAssertLessThan(CynefinBoundaries.seededRandom(seed), 1)
        }
    }

    func testTheHashIsMermaidsAndTheDefaultSeedPelesPrefix() {
        XCTAssertEqual(CynefinBoundaries.hash("pele"), 3_437_102)
        XCTAssertEqual(CynefinBoundaries.hash("cynefin"), 1_237_376_062)
        XCTAssertEqual(CynefinBoundaries.hash("mermaid-1"), 1_795_732_973)
        XCTAssertNotEqual(CynefinBoundaries.hash("complex"), CynefinBoundaries.hash("chaotic"))
        XCTAssertEqual(CynefinBoundaries.seed(configured: nil), 3_437_102)
        XCTAssertEqual(CynefinBoundaries.seed(configured: -3), -3)
    }

    func testAWaveJittersItsPointsAndPinsItsEnds() {
        var shape = CynefinBoundaries.WaveShape.horizon
        shape.segmentCount = 4
        shape.pinsEnd = true
        let seed = 3_437_102.0
        let wave = CynefinBoundaries.wave(from: 0, to: 400, center: 100, seed: seed, amplitude: 8, shape: shape)
        XCTAssertEqual(wave.start.x, 0)
        XCTAssertEqual(wave.start.y, 100 + 0.5959696690551937 * 16 - 8, accuracy: 1e-12)
        XCTAssertEqual(wave.segments.count, 4)
        XCTAssertEqual(CynefinBoundaries.endPoint(of: wave), CGPoint(x: 400, y: 100))
        guard case .curve(let end, let firstControl, _) = wave.segments[0] else { return XCTFail("A curve") }
        XCTAssertEqual(end.x, 100)
        XCTAssertEqual(end.y, 100 + 0.15511049912311137 * 16 - 8, accuracy: 1e-9, "The next point's seed is 23 more")
        XCTAssertEqual(firstControl.x, 50)
        XCTAssertEqual(CynefinBoundaries.wave(from: 0, to: 400, center: 100, seed: seed, amplitude: 8, shape: shape),
                       CynefinBoundaries.wave(from: 0, to: 400, center: 100, seed: seed, amplitude: 8, shape: shape))
    }

    func testTheCliffIsAnSFromTheMiddleToTheBottom() {
        let cliff = CynefinBoundaries.cliff(centerX: 400, top: 300, bottom: 600, amplitude: 24)
        XCTAssertEqual(cliff.start, CGPoint(x: 400, y: 300))
        XCTAssertEqual(cliff.segments, [.curve(to: CGPoint(x: 412, y: 525), control1: CGPoint(x: 424, y: 360), control2: CGPoint(x: 364, y: 465)),
                                        .curve(to: CGPoint(x: 400, y: 600), control1: CGPoint(x: 376, y: 555), control2: CGPoint(x: 407.2, y: 585))])
        let reversed = CynefinBoundaries.reversed(cliff)
        XCTAssertEqual(reversed.start, CGPoint(x: 400, y: 600))
        XCTAssertEqual(CynefinBoundaries.endPoint(of: reversed), CGPoint(x: 400, y: 300))
    }

    // MARK: Layout

    func testAnEmptyFrameworkIsTheOptionsBoardWithFiveBlocks() throws {
        let layout = try CynefinReading.uniformLayout("cynefin-beta")
        XCTAssertEqual(layout.size, CGSize(width: 656, height: 456))
        XCTAssertEqual(layout.blocks.map(\.domain), [.complex, .complicated, .chaotic, .clear, .confusion])
        XCTAssertEqual(layout.regions.map(\.seriesIndex), [0, 1, 3, 2])
        XCTAssertEqual(layout.confusion, CGRect(x: 328 - 88, y: 228 - 64, width: 176, height: 128))
        XCTAssertEqual(layout.blocks[0].frame.midX, 8 + 160, accuracy: 1e-9)
        XCTAssertEqual(layout.blocks[3].frame.midY, 8 + 330, accuracy: 1e-9)
        XCTAssertEqual(layout.blocks[0].subtitles.map { block in block.lines[0] }, ["Probe → Sense → Respond", "Emergent Practices"])
        XCTAssertEqual(layout.blocks[4].subtitles.map { block in block.lines[0] }, ["Disorder"], "Confusion has no decision model")
        XCTAssertEqual(layout.boundaries.count, 3)
        XCTAssertEqual(CynefinBoundaries.endPoint(of: layout.boundaries[0]), CGPoint(x: 328, y: 228), "The fold ends in the middle")
    }

    func testABlockIsItsNameSubtitlesAndItemsInBoxes() throws {
        let layout = try CynefinReading.uniformLayout("cynefin-beta\n  complex\n    \"Investigate\"")
        let block = layout.blocks[0]
        XCTAssertEqual(block.frame.height, 24 + 20 + 20 + 4 + 6 + 29)
        let badge = try XCTUnwrap(block.badges.first)
        XCTAssertEqual(badge.frame.size, CGSize(width: 11 * 7 + 20, height: 29))
        XCTAssertEqual(badge.frame.minY, block.frame.minY + 24 + 40 + 10)
        XCTAssertEqual(badge.text.center, CGPoint(x: badge.frame.midX, y: badge.frame.midY))
    }

    func testConfusionShowsThreeItemsAndABadgeForTheRest() throws {
        let layout = try CynefinReading.uniformLayout("cynefin-beta\n  confusion\n" + (1...5).map { item in "    \"Item \(item)\"\n" }.joined())
        let badges = layout.blocks[4].badges
        XCTAssertEqual(badges.map { badge in badge.text.lines[0] }, ["Item 1", "Item 2", "Item 3", "+2 more"])
        XCTAssertEqual(badges.map(\.isOverflow), [false, false, false, true])
        XCTAssertGreaterThan(layout.confusion.height, 128, "The ellipse grows around its block")
    }

    func testQuadrantsGrowToHoldTheirBlocksAndStayClearOfTheEllipse() throws {
        let many = "cynefin-beta\n  complex\n" + (1...12).map { item in "    \"Item \(item)\"\n" }.joined()
        let layout = try CynefinReading.uniformLayout(many)
        let block = layout.blocks[0]
        XCTAssertGreaterThanOrEqual(layout.size.height - 16, 2 * (block.frame.height + 40) - 1e-9)
        let inner = CGPoint(x: block.frame.maxX, y: block.frame.maxY)
        let across = (inner.x - layout.confusion.midX) / (layout.confusion.width / 2 + 10)
        let down = (inner.y - layout.confusion.midY) / (layout.confusion.height / 2 + 10)
        XCTAssertGreaterThanOrEqual(across * across + down * down, 1 - 1e-9, "The block's inner corner is clear of the ellipse")
    }

    func testTransitionsRunFromBlockToBlockAndBowAwayFromTheMiddle() throws {
        let layout = try CynefinReading.uniformLayout("cynefin-beta\n  complex --> complicated : \"Pattern\"\n  complicated --> complex\n  complex --> clear")
        XCTAssertEqual(layout.transitions.count, 3)
        let first = layout.transitions[0]
        XCTAssertGreaterThan(first.path.start.x, layout.blocks[0].frame.maxX + 7, "It starts where it leaves its block")
        XCTAssertLessThan(first.arrow.tip.x, layout.blocks[1].frame.minX - 7)
        let label = try XCTUnwrap(first.label)
        XCTAssertLessThan(label.center.y, first.path.start.y, "Above, away from the middle")
        guard case .curve(_, let firstControl, _) = first.path.segments[0], case .curve(_, let repeatedControl, _) = layout.transitions[1].path.segments[0] else {
            return XCTFail("Curves")
        }
        XCTAssertLessThan(repeatedControl.y, firstControl.y, "The repeated transition bows 56 points farther")
        XCTAssertNil(layout.transitions[2].label)
    }

    func testTheSceneHasPelesPartsInPelesOrder() throws {
        let scene = DiagramScene(layout: try CynefinReading.uniformLayout("cynefin-beta\n  title T\n  complex\n    \"A\"\n  complex --> clear : \"x\""))
        let parts = scene.items.map { item -> DiagramScenePart in
            switch item {
            case .shape(let shape): shape.part
            case .text(let text): text.part
            }
        }
        XCTAssertEqual(parts.first, .title)
        XCTAssertEqual(Array(parts[1...4]), Array(repeating: .cynefinRegion, count: 4))
        XCTAssertEqual(Array(parts[5...8]), [.cynefinBoundary, .cynefinCliff, .cynefinRegion, .cynefinRegion])
        XCTAssertEqual(Array(parts.suffix(3)), [.edge, .marker, .edgeLabel])
        XCTAssertTrue(scene.texts.contains { text in text.isItalic && text.part == .cynefinSubtitle })
    }
}
