/**
 * File: VennLayoutEngineTests.swift
 * ---------------------------------
 * Layer: Tests
 * Description: A Venn diagram's geometry and layout as Pele's: the implied overlaps (vennRenderer.spec.ts), lens areas
 *              and distances, the circles' sizes and places, each region's text, styles and the colors picked for text.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class VennLayoutEngineTests: XCTestCase {
    private func subset(_ sets: [String], _ size: Double) -> VennSubset {
        VennSubset(sets: sets, size: size, label: nil)
    }

    // MARK: Mermaid's ensurePairwiseSubsets spec

    func testNothingIsAddedWithoutAnOverlapOfThreeOrMoreSets() {
        XCTAssertEqual(VennCircleGeometry.withPairwiseSubsets([]), [])
        let pairs = [subset(["A"], 10), subset(["B"], 10), subset(["A", "B"], 2.5)]
        XCTAssertEqual(VennCircleGeometry.withPairwiseSubsets(pairs), pairs)
    }

    func testAnOverlapOfThreeSetsImpliesTheMissingPairsAQuarterOfTheSmallerSet() {
        let three = [subset(["A"], 10), subset(["B"], 10), subset(["C"], 10), subset(["A", "B", "C"], 5)]
        let completed = VennCircleGeometry.withPairwiseSubsets(three)
        XCTAssertEqual(completed.count, 7)
        XCTAssertEqual(completed.filter { subset in subset.sets.count == 2 }.map(\.sets), [["A", "B"], ["A", "C"], ["B", "C"]])
        XCTAssertEqual(completed.filter { subset in subset.sets.count == 2 }.map(\.size), [2.5, 2.5, 2.5])
        let partial = VennCircleGeometry.withPairwiseSubsets(three + [subset(["A", "B"], 2.5), subset(["B", "C"], 2.5)])
        XCTAssertEqual(partial.count, 7)
        XCTAssertEqual(partial.last?.sets, ["A", "C"])
        let unordered = VennCircleGeometry.withPairwiseSubsets([subset(["A"], 10), subset(["B"], 10), subset(["C"], 10), subset(["B", "A", "C"], 5)])
        XCTAssertEqual(unordered.filter { subset in subset.sets.count == 2 }.map(\.sets), [["A", "B"], ["A", "C"], ["B", "C"]])
        let unknownSizes = VennCircleGeometry.withPairwiseSubsets([subset(["A", "B", "C"], 5)])
        XCTAssertEqual(unknownSizes.count, 4)
        XCTAssertEqual(unknownSizes.dropFirst().map(\.size), [2.5, 2.5, 2.5])
    }

    // MARK: Geometry

    func testTheLensAreaFallsAsTheCirclesMoveApartAndTheDistanceForAnOverlapFindsIt() {
        XCTAssertEqual(VennCircleGeometry.lensArea(1, 1, distance: 0), Double.pi, accuracy: 1e-12)
        XCTAssertEqual(VennCircleGeometry.lensArea(1, 1, distance: 2), 0)
        XCTAssertEqual(VennCircleGeometry.lensArea(2, 1, distance: 0.5), Double.pi, accuracy: 1e-12, "The smaller circle inside the larger")
        let distance = VennCircleGeometry.distanceForOverlap(2, 1.5, area: 2)
        XCTAssertEqual(VennCircleGeometry.lensArea(2, 1.5, distance: distance), 2, accuracy: 1e-9)
        XCTAssertEqual(VennCircleGeometry.distanceForOverlap(2, 1.5, area: 0), 3.5)
        XCTAssertEqual(VennCircleGeometry.distanceForOverlap(2, 1.5, area: 100), 0.5)
    }

    func testTwoSetsSitSideBySideAsFarApartAsTheirOverlapAsks() throws {
        let placement = try VennCirclePlacement(subsets: [subset(["A"], 20), subset(["B"], 12), subset(["A", "B"], 3)], limits: .standard)
        let circles = placement.circles
        XCTAssertEqual(circles.map(\.identifier), ["A", "B"])
        XCTAssertEqual(circles[0].radius, (20 / Double.pi).squareRoot(), accuracy: 1e-12)
        XCTAssertEqual(circles[1].y, 0)
        XCTAssertEqual(VennCircleGeometry.lensArea(circles[0].radius, circles[1].radius, distance: circles[1].x), 3, accuracy: 1e-9)
    }

    func testThreeSetsFormATriangleThatShrinksUntilTheyShareARegion() throws {
        let placement = try VennCirclePlacement(subsets: [subset(["A"], 10), subset(["B"], 10), subset(["C"], 10), subset(["A", "B", "C"], 1)],
                                                limits: .standard)
        let circles = placement.circles
        XCTAssertEqual(circles[1].x, circles[2].x * 2, accuracy: 1e-9, "The third sits below the middle of the first two")
        XCTAssertGreaterThan(circles[2].y, 0)
        let shared = VennRegionSpot.find(in: circles, inside: [0, 1, 2], outside: [])
        XCTAssertGreaterThan(shared.margin, placement.widestRadius * VennCirclePlacement.tripleOverlapShare)
    }

    func testARegionsSpotIsFarthestFromTheOutlinesAndCentredWhenSymmetric() {
        let circles = [VennCircle(identifier: "A", x: 0, y: 0, radius: 1), VennCircle(identifier: "B", x: 1, y: 0, radius: 1)]
        let overlap = VennRegionSpot.find(in: circles, inside: [0, 1], outside: [])
        XCTAssertEqual(overlap.x, 0.5, accuracy: 1e-6)
        XCTAssertEqual(overlap.y, 0, accuracy: 1e-6)
        XCTAssertEqual(overlap.margin, 0.5, accuracy: 1e-6)
        let onlyA = VennRegionSpot.find(in: circles, inside: [0], outside: [1])
        XCTAssertEqual(onlyA.y, 0, accuracy: 1e-6)
        XCTAssertEqual(onlyA.margin, 0.5, accuracy: 1e-3, "Halfway between B's outline and A's far side")
    }

    // MARK: Layout

    func testTheLargestCircleIsAHundredPointsGrownToHoldItsText() throws {
        let short = try VennReading.uniformLayout("venn-beta\n  set A\n  set B:5\n  union A,B")
        XCTAssertEqual(short.sets.map(\.radius).max() ?? 0, 100, accuracy: 1e-9)
        XCTAssertEqual(short.sets.map(\.seriesIndex), [0, 1])
        let long = try VennReading.uniformLayout("venn-beta\n  set A[\"" + String(repeating: "word ", count: 30) + "\"]")
        XCTAssertEqual(long.sets[0].radius, 160, accuracy: 1e-9, "Grown by at most 1.6")
        XCTAssertGreaterThan(long.regions[0].lines[0].text.lines.count, 1, "Still too wide, wrapped to its region")
        XCTAssertEqual(long.regions[0].lines[0].text.lineHeight, 21, "Wrapped lines are 1.3 times the size apart")
    }

    func testThePageHoldsTheCirclesAndTheTitleWithEightPointsAround() throws {
        let layout = try VennReading.uniformLayout("venn-beta\n  title Team overlap\n  set A")
        XCTAssertEqual(layout.size.width, 216)
        XCTAssertEqual(layout.size.height, 216 + 24 + 12)
        XCTAssertEqual(layout.sets[0].center, CGPoint(x: 108, y: 8 + 36 + 100))
        XCTAssertEqual(layout.title?.center, CGPoint(x: 108, y: 20))
        XCTAssertEqual(layout.regions[0].lines[0].text.center, layout.sets[0].center)
    }

    func testAStatementAboutTheSameSetsReplacesTheEarlierOneWhereItStood() throws {
        let layout = try VennReading.uniformLayout("venn-beta\n  set A[\"First\"]\n  set B\n  set A[\"Second\"]")
        XCTAssertEqual(layout.regions.map { region in region.lines.first?.text.lines.first }, ["Second", "B"])
    }

    func testAnOverlapIsOutlinedOnlyWhenAStyleGivesItALook() throws {
        XCTAssertTrue(try VennReading.uniformLayout("venn-beta\n  set A\n  set B\n  union A,B").overlaps.isEmpty)
        let styled = try VennReading.uniformLayout("venn-beta\n  set A\n  set B\n  union A,B[\"AB\"]\n  style A,B fill:gold, stroke:#000")
        XCTAssertEqual(styled.overlaps.map(\.sets), [["A", "B"]])
        guard case .corners(_, let sides) = styled.overlaps[0].outline else { return XCTFail("The lens has two corners") }
        XCTAssertEqual(sides.count, 2)
        XCTAssertEqual(styled.regions[2].lines[0].color, VennAppearance.textOnLight, "Dark text over the gold overlap")
    }

    func testTextIsInTheColorItsStyleWritesElseTheOnePickedOverAFill() throws {
        let layout = try VennReading.uniformLayout("venn-beta\n  set A\n    text A1\n    text A2\n  style A fill:#000, fill-opacity: 0.8\n  style A1 color:red")
        let lines = layout.regions[0].lines
        XCTAssertEqual(lines.map(\.isRegionText), [false, true, true])
        XCTAssertEqual(lines[0].color, VennAppearance.textOnDark)
        XCTAssertEqual(lines[1].color, DiagramColor(red: 1, green: 0, blue: 0))
        XCTAssertEqual(lines[2].color, VennAppearance.textOnDark)
        let translucent = try VennReading.uniformLayout("venn-beta\n  set A\n  style A fill:#000, fill-opacity: 0.4")
        XCTAssertNil(translucent.regions[0].lines[0].color, "Under half opaque, the page shows through: the usual color")
    }

    func testStylesMergeByTargetAndUnreadDeclarationsAreCounted() throws {
        let diagram = try VennReading.venn("venn-beta\n  set A\n  style A fill:red, font-weight:bold\n  style A fill:#00f, stroke-width: 3\n  style A rx:4")
        XCTAssertEqual(diagram.unappliedDeclarationCount, 2)
        let layout = try VennReading.uniformLayout("venn-beta\n  set A\n  style A fill:red, font-weight:bold\n  style A fill:#00f, stroke-width: 3")
        XCTAssertEqual(layout.sets[0].appearance.fill, DiagramColor(red: 0, green: 0, blue: 1))
        XCTAssertEqual(layout.sets[0].appearance.strokeWidth, 3)
    }

    func testOverlapsPastTheLayoutLimitAreRefused() throws {
        var limits = MermaidDiagramLimits.standard
        limits.maximumLayoutPointCount = 10
        let source = "venn-beta\n" + (0..<6).map { index in "set s\(index)\n" }.joined() + "union s0,s1,s2,s3,s4,s5\n"
        XCTAssertThrowsError(try VennReading.uniformLayout(source, limits: limits)) { error in
            XCTAssertEqual(error as? VennLayoutError, .tooManyOverlaps(limit: 10))
        }
        XCTAssertNoThrow(try VennReading.uniformLayout(source))
    }

    // MARK: Painting

    func testCirclesArePaintedInTheirSeriesColorsAtAFifthOfTheirOpacity() throws {
        let layout = try VennReading.uniformLayout("venn-beta\n  set A\n  set B\n  style B fill:#ff0000, fill-opacity:1")
        let pixels = try XCTUnwrap(DiagramScenePixels(size: layout.size, scale: 1) { context in
            context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(origin: .zero, size: layout.size))
            VennRenderer.draw(layout, in: context, palette: .peleLight)
        })
        func color(at point: CGPoint) -> [Int] {
            let offset = (Int(point.y) * pixels.width + Int(point.x)) * 4
            return (0..<3).map { channel in Int(pixels.bytes[offset + channel]) }
        }
        let first = color(at: CGPoint(x: layout.sets[0].center.x, y: layout.sets[0].center.y - 60))
        for (channel, expected) in zip(first, [0x4C, 0x78, 0xA8].map { value in 255 - (255 - value) / 5 }) {
            XCTAssertEqual(Double(channel), Double(expected), accuracy: 3)
        }
        XCTAssertEqual(color(at: CGPoint(x: layout.sets[1].center.x, y: layout.sets[1].center.y - 60)), [255, 0, 0])
    }
}
