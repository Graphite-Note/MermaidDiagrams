/**
 * File: C4StyleAndPlacementTests.swift
 * ------------------------------------
 * Layer: Tests
 * Description: C4 styles, casings, label offsets, headings and narrow columns as Pele's render tests check them: colors
 *              and the text color picked on a fill, lines inked or cased over a filled boundary, offsets kept off shapes,
 *              headings moved off lines, and the tight drawing's lanes through the gaps between columns.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class C4StyleAndPlacementTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))

    func testUpdateElementStyleColorsShapesAndBoundaries() throws {
        let layout = try C4Reading.uniformLayout("""
            C4Context
            Person(a, "A", "desc")
            Boundary(b, "B") {
              System(c, "C")
            }
            UpdateElementStyle(a, $fontColor="red", $bgColor="grey", $borderColor="blue")
            UpdateElementStyle(b, "#eee", "green", "orange")
            UpdateElementStyle(nobody, "red")
            """)
        let person = try XCTUnwrap(layout.shape("a")?.look)
        XCTAssertEqual(person.fill, DiagramColor(cssText: "grey"))
        XCTAssertEqual(person.stroke, DiagramColor(cssText: "blue"))
        XCTAssertEqual(person.textColor, DiagramColor(cssText: "red"))
        let boundary = try XCTUnwrap(layout.boundary("b")?.look)
        XCTAssertEqual([boundary.fill, boundary.stroke, boundary.textColor], [DiagramColor(cssText: "#eee"), DiagramColor(cssText: "orange"),
                                                                               DiagramColor(cssText: "green")])
        let scene = DiagramScene(layout: layout)
        XCTAssertEqual(scene.texts.filter { text in text.paint == .color(DiagramColor(cssText: "red")!) }.count, 3)
    }

    func testAContrastingTextColorOnFillsAStyleSets() throws {
        let layout = try C4Reading.uniformLayout("""
            C4Context
            Boundary(b, "B", "Kind") {
              System(c, "C", "about c")
            }
            System(d, "D", "about d")
            System(e, "E")
            UpdateElementStyle(b, $bgColor="lightyellow")
            UpdateElementStyle(c, $bgColor="navy")
            UpdateElementStyle(d, $bgColor="navy", $fontColor="#ddd")
            """)
        XCTAssertEqual(layout.shape("c")?.look.ink, VennAppearance.textOnDark)
        XCTAssertEqual(layout.boundary("b")?.look.ink, VennAppearance.textOnLight)
        XCTAssertEqual(layout.shape("d")?.look.textColor, DiagramColor(cssText: "#ddd"))
        XCTAssertNil(layout.shape("d")?.look.ink)
        XCTAssertNil(layout.shape("e")?.look.ink)
        let scene = DiagramScene(layout: layout)
        XCTAssertEqual(scene.texts.filter { text in text.paint == .color(VennAppearance.textOnDark) }.count, 3)
    }

    func testLinesOverAFilledBoundaryAreInkedOrCased() throws {
        let source = """
            C4Context
            Boundary(b, "B") {
              System(x, "X")
              System(y, "Y")
            }
            System(z, "Z")
            System(w, "W")
            Rel(x, y, "in")
            Rel(y, z, "out")
            Rel(z, w, "away")
            UpdateElementStyle(b, $bgColor="lightyellow")
            """
        let layout = try C4Reading.uniformLayout(source)
        XCTAssertEqual(layout.relation("x", "y")?.lineColor, VennAppearance.textOnLight)
        XCTAssertEqual(layout.relation("x", "y")?.isCased, false)
        XCTAssertEqual(layout.relation("y", "z")?.isCased, true)
        XCTAssertEqual(layout.relation("z", "w")?.isCased, false)
        XCTAssertNil(layout.relation("z", "w")?.lineColor)
        let plain = try C4Reading.uniformLayout(source.replacingOccurrences(of: "UpdateElementStyle(b, $bgColor=\"lightyellow\")", with: ""))
        XCTAssertFalse(plain.relations.contains { relation in relation.isCased || relation.lineColor != nil })
        XCTAssertTrue(DiagramScene(layout: layout).shapes.contains { shape in shape.part == .casing })
        let loop = try C4Reading.uniformLayout("C4Context\nBoundary(S, \"S\") {\n  System(A, \"A\")\n}\nRel(A, A, \"self\")\nUpdateElementStyle(S, $bgColor=\"white\")")
        XCTAssertEqual(loop.relation("A", "A")?.lineColor, VennAppearance.textOnLight)
    }

    func testUpdateRelStyleColorsAndOffsets() throws {
        let base = "C4Context\nUpdateLayoutConfig(\"1\", \"1\")\nSystem(a, \"A\")\nSystem(b, \"B\")\nRel(a, b, \"x\")\n"
        let plain = try XCTUnwrap(try C4Reading.uniformLayout(base).relations.first)
        let styled = try XCTUnwrap(try C4Reading.uniformLayout(base + "UpdateRelStyle(a, b, $textColor=\"red\", $lineColor=\"blue\", $offsetX=\"30\", $offsetY=\"-10\")").relations.first)
        XCTAssertEqual(styled.lineColor, DiagramColor(cssText: "blue"))
        XCTAssertEqual(styled.textColor, DiagramColor(cssText: "red"))
        XCTAssertEqual(styled.labelFrame?.minX, (plain.labelFrame?.minX ?? 0) + 30)
        XCTAssertEqual(styled.labelFrame?.minY, (plain.labelFrame?.minY ?? 0) - 10)
        let positional = try C4Reading.uniformLayout(base + "UpdateRelStyle(a, b, \"red\", \"blue\", \"30\", \"-10\")").relations.first
        XCTAssertEqual(positional?.labelFrame, styled.labelFrame)
        let swapped = try C4Reading.uniformLayout(base + "UpdateRelStyle(a, b, $offsetX=\"30\", $offsetY=\"-10\", $lineColor=\"blue\", $textColor=\"red\")").relations.first
        XCTAssertEqual(swapped?.labelFrame, styled.labelFrame)
        XCTAssertEqual(swapped?.lineColor, styled.lineColor)
    }

    func testALabelStaysOnItsLineWhenAnOffsetWouldPutItOnAShape() throws {
        let base = "C4Context\nSystem(a, \"A\")\nSystem(b, \"B\")\nRel(a, b, \"x\")\n"
        let plain = try C4Reading.uniformLayout(base)
        XCTAssertEqual(try C4Reading.uniformLayout(base + "UpdateRelStyle(a, b, $offsetX=\"-120\")"), plain)
        let raised = try C4Reading.uniformLayout(base + "UpdateRelStyle(a, b, $offsetY=\"-60\")")
        // The page grows upward to hold it, so it is measured from its line.
        func aboveLine(_ layout: C4Layout) -> CGFloat { layout.relations[0].path.start.y - (layout.relations[0].labelFrame?.minY ?? 0) }
        XCTAssertEqual(aboveLine(raised), aboveLine(plain) + 60)
        XCTAssertLessThan(try C4Reading.uniformLayout(base + "UpdateRelStyle(a, b, $offsetX=\"9999999999\")").size.width, 3_000)
        XCTAssertEqual(try C4Reading.uniformLayout(base + "UpdateRelStyle(a, b, $offsetX=\"abc\", $offsetY=\"x1\")"), plain)
    }

    func testABoundaryHeadingMovesOutOfTheWayOfALine() throws {
        let layout = try C4Reading.uniformLayout("C4Context\nSystem(top, \"Top\")\nBoundary(b, \"Boundary name\") {\n  System(in, \"In\")\n  System(other, \"Other\")\n}\nRel(top, in, \"x\")")
        let heading = try XCTUnwrap(layout.boundary("b")?.name.first?.frame.minX)
        let line = try XCTUnwrap(layout.relation("top", "in")?.path.start.x)
        XCTAssertGreaterThan(abs(heading - line), 20)
        let alone = try C4Reading.uniformLayout("C4Context\nBoundary(b, \"Boundary name\") {\n System(in, \"In\")\n System(other, \"Other\")\n}")
        XCTAssertLessThan(try XCTUnwrap(alone.boundary("b")?.name.first?.frame.minX), heading)
    }

    // MARK: - Narrow columns

    private func componentExample() throws -> C4Diagram {
        try C4Reading.c4(try XCTUnwrap(try C4Corpus.documentationExamples().first { source in source.contains("Accounts Summary Controller") }))
    }

    func testATightLineThroughTheGapBetweenColumnsKeepsApartFromTheOthersThere() throws {
        let layout = try C4LayoutEngine.tightLayout(try componentExample(), typography: typography, columnWidth: 640)
        let application = try XCTUnwrap(layout.shape("spa")?.frame)
        let accounts = try XCTUnwrap(layout.shape("accounts")?.frame)
        var lanes: [CGFloat] = []
        for (from, to) in [("spa", "accounts"), ("ma", "sign")] {
            let corners = try XCTUnwrap(layout.relation(from, to)?.corners, from)
            XCTAssertEqual(corners.count, 4, from)
            XCTAssertGreaterThan(corners[2].x, application.maxX, from)
            XCTAssertLessThan(corners[2].x, accounts.minX, from)
            lanes.append(corners[2].x)
        }
        XCTAssertGreaterThanOrEqual(abs(lanes[0] - lanes[1]), 10)
    }

    func testATightDetourTakesTheOutsideWhenItsColumnIsAtTheEdge() throws {
        let layout = try C4LayoutEngine.tightLayout(try componentExample(), typography: typography, columnWidth: 640)
        XCTAssertLessThan(try XCTUnwrap(layout.relation("spa", "sign")?.corners[2].x), try XCTUnwrap(layout.shape("spa")?.frame.minX))
        XCTAssertGreaterThan(try XCTUnwrap(layout.relation("mbsfacade", "mbs")?.corners[2].x), try XCTUnwrap(layout.shape("mbs")?.frame.maxX))
    }

    func testOffsetsAreLeftOutWhenTight() throws {
        let source = try XCTUnwrap(try C4Corpus.documentationExamples().first { source in source.contains("Accounts Summary Controller") })
        let withoutOffsets = source.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { line in !line.trimmingCharacters(in: .whitespaces).hasPrefix("UpdateRelStyle(") }.joined(separator: "\n")
        for width: CGFloat in [320, 480, 568] {
            XCTAssertEqual(try C4LayoutEngine.tightLayout(try C4Reading.c4(source), typography: typography, columnWidth: width),
                           try C4LayoutEngine.tightLayout(try C4Reading.c4(withoutOffsets), typography: typography, columnWidth: width), "\(width)")
        }
        let wide = try C4LayoutEngine.layout(try C4Reading.c4(source), typography: typography)
        XCTAssertEqual(try C4LayoutEngine.layout(try C4Reading.c4(source), typography: typography, fittingWidth: wide.size.width), wide)
        XCTAssertNotEqual(wide, try C4LayoutEngine.layout(try C4Reading.c4(withoutOffsets), typography: typography))
    }

    func testTheNarrowSceneIsTheTightDrawing() throws {
        let prepared = try MermaidDiagramPreparation.prepare(source: try XCTUnwrap(try C4Corpus.documentationExamples().first), typography: typography)
        XCTAssertEqual(prepared.kind, .c4)
        let narrow = try XCTUnwrap(prepared.narrowScene)
        XCTAssertLessThan(narrow.size.width, prepared.scene.size.width)
        XCTAssertTrue(prepared.accessibility.summary.contains("Banking Customer A, person"))
        XCTAssertTrue(prepared.accessibility.summary.contains("Banking Customer A to Internet Banking System: Uses"))
    }
}
