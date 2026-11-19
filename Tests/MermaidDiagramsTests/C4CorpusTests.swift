/**
 * File: C4CorpusTests.swift
 * -------------------------
 * Layer: Tests
 * Description: Mermaid's C4 documentation examples, all read and laid out with their shapes apart and on the page,
 *              tight for narrow columns too, Pele's worst cases within limits and time, and the generated diagrams.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class C4CorpusTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))

    func testEveryDocumentationExampleIsDrawnWithItsShapesApartAndOnThePage() throws {
        let examples = try C4Corpus.documentationExamples()
        XCTAssertEqual(examples.count, 6)
        for (index, example) in examples.enumerated() {
            let diagram = try C4Reading.c4(example)
            for width: CGFloat? in [nil, 640, 480, 320] {
                let layout = try width.map { width in try C4LayoutEngine.tightLayout(diagram, typography: typography, columnWidth: width) }
                    ?? C4LayoutEngine.layout(diagram, typography: typography)
                PlaneMapPictures.write(DiagramScene(layout: layout), named: "c4-documentation-\(index)-\(width.map { width in "\(Int(width))" } ?? "full")")
                let page = CGRect(origin: .zero, size: layout.size)
                for (first, shape) in layout.shapes.enumerated() {
                    XCTAssertTrue(page.contains(shape.frame), "example \(index): \(shape.alias)")
                    for second in layout.shapes.indices where second > first {
                        XCTAssertFalse(shape.frame.intersects(layout.shapes[second].frame), "example \(index): \(shape.alias) and \(layout.shapes[second].alias)")
                    }
                }
                for relation in layout.relations {
                    if let label = relation.labelFrame { XCTAssertTrue(page.insetBy(dx: -1, dy: -1).contains(label), "example \(index): \(relation.from)") }
                }
                XCTAssertEqual(layout.relations.count, diagram.relations.count)
            }
        }
    }

    func testTheGeneratedDiagramsAreLaidOut() throws {
        for (shapes, boundaries, relations) in [(1, 0, 0), (20, 3, 30), (200, 10, 300)] {
            let diagram = try C4Reading.c4(C4Corpus.generated(shapeCount: shapes, boundaryCount: boundaries, relationCount: relations))
            XCTAssertEqual(diagram.shapes.count, shapes)
            XCTAssertEqual(diagram.boundaries.count, boundaries + 1)
            let layout = try C4LayoutEngine.layout(diagram, typography: typography)
            XCTAssertEqual(layout.shapes.count, shapes)
            XCTAssertEqual(layout.relations.count, diagram.relations.count)
            XCTAssertTrue(layout.size.width.isFinite && layout.size.height.isFinite)
            if shapes == 20 { PlaneMapPictures.write(DiagramScene(layout: layout), named: "c4-generated-20") }
        }
    }

    /// Pele's worst cases (tests/c4/stress.test.ts) that fit the standard text limit: each is read and laid out, or
    /// refused with a typed error, in under 10 seconds in a debug build.
    func testPelesWorstCasesAreDrawnOrRefusedQuickly() {
        let header = "C4Context\n"
        let size = 49_000
        func repeated(_ count: Int, _ line: (Int) -> String) -> String { (0..<count).map(line).joined() }
        var related = header + repeated(50) { index in "System(s\(index),\"S\")\n" }
        for first in 0..<40 { for second in 0..<40 where first != second && related.utf8.count < size - 40 { related += "Rel(s\(first),s\(second),\"x\")\n" } }
        let detours = header + "UpdateLayoutConfig(\"1000\", \"1\")\n" + repeated(1_000) { index in "System(s\(index),\"S\")\n" }
            + repeated(480) { index in "Rel(s0,s\(index + 2),\"x\")\n" }
        let cases: [(String, String)] = [
            ("one long line of statements that mentions direction", header + String(repeating: "Rel(a,b,\"x\")", count: size / 12) + " direction XX"),
            ("a line made of the word direction", header + String(repeating: "direction ", count: size / 20) + "\n" + String(repeating: "direction\n", count: size / 20)),
            ("direction followed by blank lines", header + String(repeating: "x direction" + String(repeating: "\n", count: 50), count: size / 61)),
            ("spaces after an opening parenthesis", header + "Person(" + String(repeating: " ", count: size)),
            ("an unclosed string", header + "Person(a, \"" + String(repeating: "x", count: size)),
            ("a named argument with no equals sign", header + "Person(a, $" + String(repeating: "k", count: size)),
            ("an unclosed multi-line description", header + "accDescr {" + String(repeating: " x\n", count: size / 3)),
            ("a comment followed by line breaks", header + "%% c" + String(repeating: "\r\n", count: size / 2) + "Person(a, \"b\")"),
            ("a word of 49,000 letters", header + String(repeating: "Person", count: size / 6)),
            ("a title of 49,000 characters", header + "title " + String(repeating: "word ", count: size / 5) + "\nPerson(a, \"b\")"),
            ("49,000 commas", header + "Person(" + String(repeating: ",", count: size) + ")"),
            ("24,000 unquoted arguments", header + "Person(" + String(repeating: "a,", count: size / 2) + "\"z\")"),
            ("2,000 named arguments on one shape", header + "System(a, \"A\"" + repeated(2_000) { index in ", $k\(index)=\"v\"" } + ")"),
            ("2,000 nested boundaries", header + repeated(2_000) { index in "Boundary(b\(index), \"B\") {\n" } + "System(s, \"S\")\n" + String(repeating: "}\n", count: 2_000)),
            ("1,000 sibling boundaries", header + repeated(1_000) { index in "Boundary(b\(index), \"B\") {\nSystem(s\(index), \"S\")\n}\n" }),
            ("2,000 shapes in one row", header + "UpdateLayoutConfig(\"99999999\", \"1\")\n" + repeated(2_000) { index in "System(s\(index), \"S\")\n" }),
            ("relations among 50 shapes", related),
            ("480 detours along one row of 1,000", detours),
            ("self relations and reversed pairs", header + "System(a,\"A\")\nSystem(b,\"B\")\n" + String(repeating: "Rel(a,a,\"x\")\nRel(a,b,\"y\")\nRel(b,a,\"z\")\n", count: 1_000)),
            ("one 49,000 character label", header + "System(a, \"" + String(repeating: "word ", count: size / 5) + "\")"),
            ("one unbreakable 49,000 character label", header + "System(a, \"" + String(repeating: "w", count: size) + "\")"),
            ("a description of entities and line breaks", header + "System(a, \"A\", \"" + String(repeating: "#35;&amp;<br>", count: size / 13) + "\")"),
            ("colours of 49,000 characters", header + "System(a, \"A\")\nUpdateElementStyle(a, \"" + String(repeating: "url( ", count: size / 10) + "\", \""
                + String(repeating: "a", count: size / 2) + "\")"),
        ]
        for (name, source) in cases {
            let started = Date()
            // A refusal is a typed error of the reader or the layout; either is a pass.
            if let diagram = try? C4Reading.c4(source), let layout = try? C4LayoutEngine.layout(diagram, typography: typography) {
                XCTAssertTrue(layout.size.width.isFinite && layout.size.height.isFinite, name)
            }
            let elapsed = Date().timeIntervalSince(started)
            XCTAssertLessThan(elapsed, 10, name)
            if elapsed > 1 { print("C4 worst case \(name): \(elapsed) s") }
        }
    }

    /// Pele's check that every line keeps clear of the shapes it does not join, in every documentation example at its
    /// full width and tight at 640, 480 and 320 points: a shape's body (a person's below its head, a database's between
    /// its caps, a queue's between its ends) less a point on each side, the line's stretches sampled every fiftieth.
    func testEveryLineKeepsClearOfTheShapesItDoesNotJoin() throws {
        var behind: [String] = []
        for (index, example) in try C4Corpus.documentationExamples().enumerated() {
            let diagram = try C4Reading.c4(example)
            for width: CGFloat? in [nil, 640, 480, 320] {
                let layout = try width.map { width in try C4LayoutEngine.tightLayout(diagram, typography: typography, columnWidth: width) }
                    ?? C4LayoutEngine.layout(diagram, typography: typography)
                for relation in layout.relations {
                    for shape in layout.shapes where shape.alias != relation.from && shape.alias != relation.to {
                        if Self.crosses(relation.corners, Self.body(of: shape).insetBy(dx: 1, dy: 1)) {
                            behind.append("\(relation.from)-\(relation.to) behind \(shape.alias) at \(width.map { width in "\(Int(width))" } ?? "full") in example \(index)")
                        }
                    }
                }
            }
        }
        XCTAssertEqual(behind, ["backend_api-banking_system behind mobile_app at full in example 2"])
    }

    private static func body(of shape: C4LayoutShape) -> CGRect {
        switch shape.form {
        case .person: CGRect(x: shape.frame.minX, y: shape.frame.minY + C4Metrics.personHead, width: shape.frame.width, height: shape.frame.height - C4Metrics.personHead)
        case .cylinder: shape.frame.insetBy(dx: 0, dy: C4Metrics.cylinderCapDepth(width: shape.frame.width))
        case .horizontalCylinder: shape.frame.insetBy(dx: C4Metrics.queueCapDepth(height: shape.frame.height), dy: 0)
        case .rectangle: shape.frame
        }
    }

    private static func crosses(_ corners: [CGPoint], _ box: CGRect) -> Bool {
        guard corners.count > 1 else { return false }
        for index in 1..<corners.count {
            for step in 0...50 {
                let fraction = CGFloat(step) / 50
                let point = CGPoint(x: corners[index - 1].x + (corners[index].x - corners[index - 1].x) * fraction,
                                    y: corners[index - 1].y + (corners[index].y - corners[index - 1].y) * fraction)
                if point.x > box.minX, point.x < box.maxX, point.y > box.minY, point.y < box.maxY { return true }
            }
        }
        return false
    }
}
