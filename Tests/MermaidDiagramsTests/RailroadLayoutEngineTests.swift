/**
 * File: RailroadLayoutEngineTests.swift
 * -------------------------------------
 * Layer: Tests
 * Description: Railroad diagrams are laid out in Pele's measurements: boxes, sequences, stacked choices, bypasses,
 *              loops with their counts, folded rows in the tight layout, the options, the shown text, and the scene.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class RailroadLayoutEngineTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))

    private func layout(_ source: String) throws -> RailroadLayout {
        RailroadLayoutEngine.layout(try RailroadReading.diagram(source), typography: typography)
    }

    private func measured(_ expression: String, tight: Bool = false, room: CGFloat = .infinity) throws -> RailroadTrackBox {
        let diagram = try RailroadReading.diagram("railroad-ebnf-beta\nr = \(expression) ;")
        let metrics = RailroadResolvedOptions(diagram.options, fontSize: 16, isTight: tight).metrics(typography: typography)
        return RailroadTrackMeasurement(metrics: metrics).box(of: diagram.rules[0].definition, room: room)
    }

    func testABoxIsThirtyPointsTallAndItsTextAndPaddingWide() throws {
        let terminal = try measured("\"while\"")
        XCTAssertEqual(terminal.up, 15)
        XCTAssertEqual(terminal.down, 15)
        let textWidth = typography.monospacedEdgeText.width(of: "while")
        XCTAssertEqual(terminal.width, ((textWidth + 24) / 2).rounded(.up) * 2)
        XCTAssertEqual(try measured("\"\"").width, 30, "No narrower than it is tall")
        XCTAssertEqual(try measured("? any ?").text, "? any ?")
    }

    func testSequencesChoicesBypassesAndLoopsTakePelesRoom() throws {
        let a = try measured("a"), b = try measured("b"), c = try measured("c")
        let sequence = try measured("a b")
        XCTAssertEqual(sequence.width, a.width + b.width + 16)
        let choice = try measured("a | b | c")
        XCTAssertEqual(choice.width, max(a.width, b.width, c.width) + 40)
        // Each branch below the one before: its depth, 10 points and the next's height.
        XCTAssertEqual(choice.down, 15 + 2 * (15 + 10 + 15))
        let optional = try measured("[ a ]")
        XCTAssertEqual(optional.kind, .bypass)
        XCTAssertEqual(optional.up, 25)
        XCTAssertEqual(optional.width, a.width + 40)
        let oneOrMore = try measured("a+")
        XCTAssertEqual(oneOrMore.kind, .loop)
        XCTAssertEqual(oneOrMore.down, 25 + 7 / 2 + 1, "No count: the arrow's room below the loop")
        XCTAssertEqual(oneOrMore.width, a.width + 20)
        let zeroOrMore = try measured("{ a }")
        XCTAssertEqual(zeroOrMore.kind, .bypass)
        XCTAssertEqual(zeroOrMore.children.first?.kind, .loop)
    }

    func testRepeatsShowTheirCounts() throws {
        let diagram = try RailroadReading.diagram("railroad-abnf-beta\nr = 2*4a 3b *4c 2*d 1e ;")
        let laidOut = RailroadLayoutEngine.layout(diagram, typography: typography)
        XCTAssertEqual(laidOut.rules[0].counts.map { count in count.lines.joined() }, ["2–4×", "3×", "≤4×", "≥2×"])
        XCTAssertEqual(laidOut.rules[0].counts.first?.fontSize, 12)
        XCTAssertEqual(laidOut.rules[0].boxes.count, 5, "Exactly once is the part itself")
        XCTAssertEqual(RailroadText.count(minimum: .infinity, maximum: .infinity), "∞×")
        XCTAssertEqual(RailroadText.count(minimum: 1, maximum: .infinity), "")
        XCTAssertEqual(RailroadText.count(minimum: 1e21, maximum: 1e21), "1e+21×")
    }

    func testARuleSitsBelowItsNameBetweenTwoDotsHalfAPointOff() throws {
        let laidOut = try layout("railroad-ebnf-beta\nr = a ;\nnext = b ;")
        let rule = laidOut.rules[0]
        // The name 24 points tall, 6 points above the track, the box 15 points above its baseline.
        let baseline: CGFloat = 8 + 24 + 6 + 15
        let width = rule.boxes[0].frame.width
        XCTAssertEqual(rule.markerCenters, [CGPoint(x: 8 + 4 + 0.5, y: baseline + 0.5), CGPoint(x: 8 + 8 + 12 + width + 12 + 4 + 0.5, y: baseline + 0.5)])
        XCTAssertEqual(rule.boxes[0].frame, CGRect(x: 8 + 8 + 12 + 0.5, y: baseline - 15 + 0.5, width: width, height: 30))
        XCTAssertEqual(rule.name.center.y, 8 + 12 + 0.5)
        XCTAssertEqual(rule.name.center.x - rule.name.size.width / 2, 8.5, accuracy: 0.001)
        // The next rule 10 and 18 points below the first's lowest point.
        XCTAssertEqual(laidOut.rules[1].name.center.y, baseline + 15 + 10 + 18 + 12 + 0.5)
        XCTAssertEqual(laidOut.size.height, (2 * baseline + 15 + 10 + 18 - 8 + 15 + 8).rounded(.up))
    }

    func testTheTightLayoutFoldsALongSequenceIntoRowsThatFitTheColumn() throws {
        let diagram = try RailroadReading.diagram("railroad-ebnf-beta\nr = alpha beta gamma delta epsilon zeta eta theta iota kappa ;")
        let regular = RailroadLayoutEngine.layout(diagram, typography: typography)
        let tight = RailroadLayoutEngine.layout(diagram, typography: typography, columnWidth: 280)
        XCTAssertTrue(tight.isTight)
        XCTAssertGreaterThan(regular.size.width, 280)
        XCTAssertLessThanOrEqual(tight.size.width, 280)
        XCTAssertEqual(Set(tight.rules[0].boxes.map(\.frame.minY)).count, tight.rules[0].arrows.count + 1, "One arrow into each row after the first")
        let folded = try measured("alpha beta gamma delta epsilon zeta eta theta iota kappa", tight: true, room: 200)
        XCTAssertEqual(folded.kind, .folded)
        XCTAssertTrue(folded.children.allSatisfy { row in row.width <= 200 - 36 })
    }

    func testTheOptionsSetTheMeasurementsWithinPelesBounds() throws {
        let options = "---\nconfig:\n  railroad:\n    arcRadius: 4\n    showMarkers: false\n    strokeWidth: 2\n    padding: 4\n    fontSize: 500\n---\n"
        let laidOut = try layout(options + "railroad-ebnf-beta\nr = a | b ;")
        XCTAssertTrue(laidOut.rules[0].markerCenters.isEmpty)
        XCTAssertEqual(laidOut.markerRadius, 0)
        XCTAssertEqual(laidOut.lineWidth, 2)
        // A font of 200 points at most, 300 points a line, with 4 points of padding above and below.
        XCTAssertEqual(laidOut.rules[0].boxes[0].frame.height, 308)
        let resolved = RailroadResolvedOptions(RailroadOptions(), fontSize: 16, isTight: true)
        XCTAssertEqual(resolved.arc, 6)
        XCTAssertEqual(resolved.gap, 12)
        XCTAssertEqual(resolved.markerRadius, 4)
    }

    func testTextIsShownAsWrittenWithMermaidsEntityCodesReadAndInvisibleEscapesWrittenOut() {
        XCTAssertEqual(RailroadText.shown("<br>*"), "<br>*")
        XCTAssertEqual(RailroadText.shown("a#35;b"), "a#b")
        XCTAssertEqual(RailroadText.shown("#quot;"), "\"")
        XCTAssertEqual(RailroadText.shown("#nosuchname;"), "&nosuchname;")
        XCTAssertEqual(RailroadText.shown("&amp;"), "&amp;")
        XCTAssertEqual(RailroadText.shown("a\nb\tc\rd"), "a\\nb\\tc\\rd")
    }

    func testBlanksAreShownAsOpenBoxes() throws {
        let laidOut = try layout("railroad-ebnf-beta\nr = \"  \" ;")
        XCTAssertEqual(laidOut.rules[0].boxes[0].text.lines, ["␣␣"])
    }

    func testTheSceneIsPaintedInPelesColorsAndOrder() throws {
        let scene = DiagramScene(layout: try layout("railroad-ebnf-beta\ntitle \"Grammar\"\nr = \"t\" , n , ? s ? , { m } ;"))
        let line = DiagramStroke(lineWidth: 1)
        XCTAssertEqual(scene.shapes.map(\.painting), [
            .stroke(.line, line), .fill(.line), .fillAndStroke(.surface, .border, line), .fillAndStroke(.background, .border, line),
            .fillAndStroke(.background, .border, DiagramStroke(lineWidth: 1, dashLengths: [4, 3])),
        ])
        XCTAssertEqual(scene.texts.map(\.part), [.title, .clusterLabel, .label, .label, .label, .label, .label, .label])
        XCTAssertEqual(scene.texts.filter(\.isMonospaced).map { text in text.block.lines.joined() }, ["t"])
        XCTAssertEqual(scene.texts.filter(\.isItalic).map { text in text.block.lines.joined() }, ["? ", " ?", "s"])
        XCTAssertEqual(scene.texts.filter(\.isItalic).map(\.paint), [.muted, .muted, .foreground])
    }
}
