/**
 * File: TrackDiagramPreparationTests.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: Event models and railroad diagrams are prepared through the one entry point: their kind and Pele's
 *              name, what a screen reader says of them, their narrow scenes, their SVG, and what has nothing to draw.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class TrackDiagramPreparationTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))

    private func prepared(_ source: String) throws(MermaidDiagramPreparationFailure) -> PreparedMermaidDiagram {
        try MermaidDiagramPreparation.prepare(source: source, typography: typography)
    }

    func testAScreenReaderHearsEachFrameOrRule() throws {
        let model = try prepared("eventmodeling\ntf 01 ui CartUI\ntf 02 cmd Inventory.AddItem\ntf 03 evt ItemAdded\ntf 04 rmo Cart\ntf 05 pcr Robot")
        XCTAssertEqual(model.kind, .eventModel)
        XCTAssertEqual(model.accessibility.label, "Event model")
        XCTAssertEqual(model.accessibility.value, "Interface CartUI, Command AddItem, Event ItemAdded, Read model Cart, Processor Robot")
        let titled = try prepared("eventmodeling title Checkout\ntf 01 ui A accDescr: Described\ntf 02 cmd B accTitle: Named")
        XCTAssertEqual(titled.accessibility.label, "Named")
        XCTAssertEqual(titled.accessibility.value, "Described")
        let railroad = try prepared("railroad-ebnf-beta\ntitle \"Digits\"\ndigit = \"0\" | \"1\" ;\nnumber = digit+ ;")
        XCTAssertEqual(railroad.kind, .railroad)
        XCTAssertEqual(railroad.accessibility.label, "Digits")
        XCTAssertEqual(railroad.accessibility.value, "digit, number")
        XCTAssertEqual(try prepared("railroad-beta\nr = terminal(\"a\") ;").accessibility.label, "Railroad diagram")
    }

    func testPelesNamesOfTheTypesNameTheirSVG() throws {
        XCTAssertEqual(MermaidDiagramKind.eventModel.peleName, "eventmodeling")
        XCTAssertEqual(MermaidDiagramKind.railroad.peleName, "railroad")
        let document = try prepared("railroad-ebnf-beta\nr = \"<t>\" , ? any ? ;").svgDocument()
        XCTAssertTrue(document.contains("class=\"pele pele-railroad\""))
        XCTAssertTrue(document.contains("&lt;t&gt;"))
        XCTAssertTrue(document.contains("font-family=\"var(--pele-font-mono,"), "Terminals in Pele's monospaced font")
        XCTAssertTrue(document.contains("font-style=\"italic\""))
    }

    func testAWideModelOrGrammarHasANarrowSceneForAColumn() throws {
        let model = try prepared("eventmodeling\ntf 01 ui CartUI\ntf 02 cmd AddItem\ntf 03 evt ItemAdded\ntf 04 rmo CartItems\ntf 05 ui CartUI2")
        let narrowModel = try XCTUnwrap(model.narrowScene)
        XCTAssertLessThan(narrowModel.size.width, model.scene.size.width)
        XCTAssertTrue(model.showsNarrowScene(inColumnWidth: 300, scale: 1))
        let grammar = try prepared("railroad-ebnf-beta\nr = alpha beta gamma delta epsilon zeta eta theta iota kappa lambda ;")
        XCTAssertLessThanOrEqual(try XCTUnwrap(grammar.narrowScene).size.width, PreparedMermaidDiagram.standardNarrowestColumnWidth)
        XCTAssertNil(try prepared("railroad-ebnf-beta\nr = a ;").narrowScene, "Narrower than a column already")
    }

    func testAModelOrGrammarDeclaringNothingHasNothingToDraw() {
        for source in ["eventmodeling", "eventmodeling\nentity A\ndata D {\n x\n}", "railroad-ebnf-beta", "railroad-peg-beta\ntitle Only a title"] {
            XCTAssertThrowsError(try prepared(source), source) { error in
                XCTAssertEqual(error as? MermaidDiagramPreparationFailure, .nothingToDraw, source)
            }
        }
        XCTAssertNoThrow(try prepared("eventmodeling\nnote 01 {\n  A note alone\n}"))
    }

    func testRefusalsAreOfTheirCategory() {
        XCTAssertEqual(try? prepared("RAILROAD-BETA\nr = terminal(\"a\") ;").kind, nil)
        do {
            _ = try prepared("railroad-ebnf-beta\nr = " + String(repeating: "(", count: 70) + "a" + String(repeating: ")", count: 70) + " ;")
            XCTFail("Refused")
        } catch {
            XCTAssertEqual(error.category, .beyondLimits)
        }
        do {
            _ = try prepared("eventmodeling\ntf 01 ui A\ntf 01 cmd B")
            XCTFail("Refused")
        } catch {
            XCTAssertEqual(error.category, .unreadable)
        }
    }
}
