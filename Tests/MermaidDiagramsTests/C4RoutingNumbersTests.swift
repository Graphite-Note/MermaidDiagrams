/**
 * File: C4RoutingNumbersTests.swift
 * ---------------------------------
 * Layer: Tests
 * Description: C4 routes in Pele's numbers (route.ts and render.ts), worked out by hand with characters half the size
 *              wide: a loop and its label, a detour along a column with its label leaning off it; and every
 *              documentation example's drawing kept value for value, so that no number of the routing moves unnoticed.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 20/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class C4RoutingNumbersTests: XCTestCase {
    /// A box 216 by 66 at (8, 8) related to itself: the loop leaves its right side 10 above the middle (half the height
    /// less 4, at most 10), bends out 28 and comes back 10 below it. Its label sits at the loop's reach plus 4, pushed out
    /// by half its width and 2, and wraps at 64: "loop label" is 65 wide, so it takes two lines 17 apart (13 × 1.3), and
    /// its patch is "label" (32.5) plus 8 wide.
    func testALoopInPelesNumbers() throws {
        let layout = try C4Reading.uniformLayout("C4Context\nSystem(a, \"A\")\nRel(a, a, \"loop label\")")
        XCTAssertEqual(layout.shape("a")?.frame, CGRect(x: 8, y: 8, width: 216, height: 66))
        let loop = try XCTUnwrap(layout.relation("a", "a"))
        XCTAssertEqual(loop.path.start, CGPoint(x: 224, y: 31))
        guard case .curve(_, let control1, let control2) = loop.path.segments.first else { return XCTFail("a loop is a curve") }
        XCTAssertEqual(control1, CGPoint(x: 252, y: 21))
        XCTAssertEqual(control2, CGPoint(x: 252, y: 61))
        XCTAssertEqual(loop.label?.lines, ["loop", "label"])
        XCTAssertEqual(loop.labelFrame, CGRect(x: 258, y: 24, width: 40.5, height: 34))
    }

    /// Three boxes in a column, 216 by 66 and 88 apart, the first related to the third: the straight line runs into the
    /// second, so the line goes round on the right, the natural side when going down and outside on both sides. It leaves
    /// the first a quarter of its height below the middle (8 + 33 + 16.5) and reaches the third a quarter above its middle
    /// (8 + 308 + 33 − 16.5), along a lane a lane's width (20) right of the column. Its label, wrapped at 88 to "a much
    /// longer" (84.5) and "label", leans 30 off the lane, not its half width plus 2, and stays at the middle, clear of the
    /// shapes.
    func testADetourAlongAColumnInPelesNumbers() throws {
        let layout = try C4Reading.uniformLayout("""
            C4Context
            UpdateLayoutConfig("1")
            System(a, "A")
            System(b, "B")
            System(c, "C")
            Rel(a, c, "a much longer label")
            """)
        XCTAssertEqual(layout.shape("c")?.frame, CGRect(x: 8, y: 316, width: 216, height: 66))
        let detour = try XCTUnwrap(layout.relation("a", "c"))
        XCTAssertEqual(detour.corners, [CGPoint(x: 224, y: 57.5), CGPoint(x: 244, y: 57.5), CGPoint(x: 244, y: 332.5), CGPoint(x: 224, y: 332.5)])
        XCTAssertEqual(detour.label?.lines, ["a much longer", "label"])
        XCTAssertEqual(detour.labelFrame, CGRect(x: 244 + 30 - 46.25, y: 195 - 17, width: 92.5, height: 34))
    }

    /// Every documentation example, laid out with text of fixed widths at full width and tight at 640, 480 and 320 points, and
    /// the generated diagram of 20 systems: a weighted sum of every corner, label patch and shape and boundary frame, as
    /// this port draws them. A change to any number of the routing or placement changes a sum; one made on purpose
    /// writes the new sums here, after the drawings are looked at again.
    func testTheDrawingsStayValueForValue() throws {
        var sources = try C4Corpus.documentationExamples()
        sources.append(C4Corpus.generated(shapeCount: 20, boundaryCount: 3, relationCount: 30))
        var sums: [String] = []
        for source in sources {
            for width: CGFloat? in [nil, 640, 480, 320] {
                let diagram = try C4Reading.c4(source)
                let layout = try width.map { width in
                    try C4LayoutEngine.tightLayout(diagram, measurers: C4Reading.uniformMeasurers, font: DiagramFont(postScriptName: nil, size: 16), columnWidth: width)
                } ?? C4Reading.uniformLayout(source)
                sums.append(String(format: "%.2f", Self.weightedSum(layout)))
            }
        }
        XCTAssertEqual(sums, Self.expectedSums)
    }

    /// Full width, 640, 480 and 320 points for each of the six documentation examples, then the generated diagram.
    private static let expectedSums = [
        "1682854.92", "1760799.54", "2573074.77", "2593578.00", "1682854.92", "1760799.54", "2573074.77", "2593578.00",
        "2228696.76", "2437294.89", "3603106.50", "3659806.50", "2133100.05", "2305660.23", "3790560.75", "3790560.75",
        "387057.70", "355399.32", "666767.25", "666767.25", "3443017.39", "4177906.37", "5327882.10", "5770478.98",
        "11663477.68", "12366688.32", "20914020.10", "20914020.10",
    ]

    private static func weightedSum(_ layout: C4Layout) -> Double {
        var sum = 0.0
        var weight = 1.0
        func add(_ value: CGFloat) {
            sum += Double(value) * weight
            weight = weight.truncatingRemainder(dividingBy: 97) + 1
        }
        func add(_ rectangle: CGRect?) {
            guard let rectangle else { return add(-1) }
            [rectangle.minX, rectangle.minY, rectangle.width, rectangle.height].forEach(add)
        }
        add(layout.size.width)
        add(layout.size.height)
        for boundary in layout.boundaries {
            add(boundary.frame)
            add(boundary.name.first?.frame)
        }
        for shape in layout.shapes { add(shape.frame) }
        for relation in layout.relations {
            for corner in relation.corners { [corner.x, corner.y].forEach(add) }
            [relation.path.start.x, relation.path.start.y].forEach(add)
            add(relation.labelFrame)
        }
        return sum
    }
}
