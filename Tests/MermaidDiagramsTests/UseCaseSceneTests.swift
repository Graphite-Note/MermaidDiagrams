/**
 * File: UseCaseSceneTests.swift
 * -----------------------------
 * Layer: Tests
 * Description: A use case diagram's scene is painted in Pele's order and colors, its styles and inks applied, a line
 *              across a filled boundary's border cased; its preparation, narrow scene and accessibility; and Pele's
 *              worst cases are drawn or refused quickly.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class UseCaseSceneTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))

    private func scene(_ lines: String...) throws -> DiagramScene {
        DiagramScene(layout: try UseCaseReading.uniformLayout((["usecase-beta"] + lines).joined(separator: "\n")))
    }

    private func parts(_ scene: DiagramScene) -> [DiagramScenePart] {
        scene.items.map { item in
            switch item {
            case .shape(let shape): shape.part
            case .text(let text): text.part
            }
        }
    }

    func testTheSceneIsPaintedInPelesOrder() throws {
        let scene = try scene("actor A <<Human>>", "systemBoundary S[Shop]", "U(Use)", "end", "A -- go --> U", "note for U n")
        XCTAssertEqual(parts(scene), [.cluster, .clusterLabel, .edge, .marker, .edge, .labelBackground, .edgeLabel, .actorFigure, .actorFigure,
                                      .stereotype, .label, .node, .label, .note, .note, .label])
        let boundary = try XCTUnwrap(scene.shapes.first)
        XCTAssertEqual(boundary.painting, .fillAndStroke(DiagramPaint.alternateSurface.atOpacity(0.5), .border, DiagramStroke(lineWidth: 1)))
        XCTAssertEqual(scene.texts.map(\.paint), [.muted, .foreground, .muted, .foreground, .foreground, .foreground])
        XCTAssertEqual(scene.shapes[1].painting, .stroke(.line, DiagramStroke(lineWidth: 1, lineCap: .round)))
        XCTAssertEqual(scene.shapes.last?.painting, .stroke(.border, DiagramStroke(lineWidth: 1, lineJoin: .round)))
    }

    func testStylesSetColorsWidthsAndDashesAndTextReadsOnAFill() throws {
        let scene = try scene("U(Use)", "style U fill:#000000,stroke:#ff0000,stroke-width:3px", "U e@--> V", "style e stroke:#00ff00,stroke-dasharray:4 2")
        let red = DiagramColor(red: 1, green: 0, blue: 0)
        let oval = try XCTUnwrap(scene.shapes.first { shape in shape.part == .node })
        XCTAssertEqual(oval.painting, .fillAndStroke(.color(DiagramColor(red: 0, green: 0, blue: 0)), .color(red), DiagramStroke(lineWidth: 3)))
        XCTAssertEqual(scene.texts.first?.paint, .color(VennAppearance.textOnDark))
        let line = try XCTUnwrap(scene.shapes.first { shape in shape.part == .edge })
        XCTAssertEqual(line.painting, .stroke(.color(DiagramColor(red: 0, green: 1, blue: 0)), DiagramStroke(lineWidth: 1, dashLengths: [4, 2], lineCap: .round)))
    }

    /// A line that crosses the border of a boundary a style fills is drawn over a wider line of the page's color.
    func testALineAcrossAFilledBoundarysBorderIsCased() throws {
        let scene = try scene("systemBoundary S", "U", "end", "style S fill:#eeeeee", "A --> U")
        XCTAssertEqual(parts(scene).filter { part in part == .casing }.count, 2)
        XCTAssertEqual(try self.scene("systemBoundary S", "U", "end", "A --> U").items.count, parts(scene).count - 2)
    }

    func testAGeneralizationEndsInAHollowTriangle() throws {
        let scene = try scene("actor A", "actor B", "A --|> B")
        let triangle = try XCTUnwrap(scene.shapes.first { shape in shape.part == .marker })
        XCTAssertEqual(triangle.painting, .fillAndStroke(.background, .line, DiagramStroke(lineWidth: 1, lineCap: .round, lineJoin: .round)))
    }

    func testPreparationGivesTheSceneANarrowSceneAndWhatAScreenReaderSays() throws {
        let source = "usecase-beta\naccTitle: Shop\nactor Customer\nCustomer --> Checkout(\"Place order\")\nCheckout ..> : include Browse\nB --> C\nC --> D"
        let prepared = try MermaidDiagramPreparation.prepare(source: source, typography: typography, narrowestColumnWidth: 320)
        XCTAssertEqual(prepared.accessibility.label, "Shop")
        XCTAssertEqual(prepared.accessibility.value, "Customer; Place order; Browse; B; C; D; Customer to Place order; Place order includes Browse; B to C; C to D")
        let narrow = try XCTUnwrap(prepared.narrowScene)
        XCTAssertLessThan(narrow.size.width, prepared.scene.size.width)
        XCTAssertEqual(MermaidDiagramKind.useCase.peleName, "usecase")
        let svg = DiagramSVGWriter().document(of: prepared.scene, diagramType: "usecase")
        XCTAssertTrue(svg.contains("pele-actor-figure"))
        XCTAssertThrowsError(try MermaidDiagramPreparation.prepare(source: "usecase-beta\n%% nothing", typography: typography)) { error in
            XCTAssertEqual(error as? MermaidDiagramPreparationFailure, .nothingToDraw)
        }
    }

    /// Pele's worst cases (tests/usecase/stress.test.ts): each is drawn or refused with a typed error, quickly.
    func testPelesWorstCasesAreDrawnOrRefusedQuickly() {
        let size = 50_000
        let header = "usecase-beta\n"
        func repeated(_ count: Int, _ line: (Int) -> String) -> String { (0..<count).map(line).joined() }
        var complete = header
        for first in 0..<40 { for second in (first + 1)..<40 { complete += "n\(first) --o n\(second)\n" } }
        let cases = [
            header + "A \"'" + String(repeating: "\"'", count: size / 2 - 10), header + "A(" + String(repeating: "word ", count: 9_000) + ")",
            header + "A -- " + String(repeating: "word ", count: size / 5 - 4), header + repeated(3_000) { index in "A\(index) -- x y z\n" },
            header + "actor A\nA@{\n" + String(repeating: "business: true,\n", count: 2_500) + "}",
            header + "A@{" + String(repeating: "\n", count: size - 20) + "}\nA",
            header + repeated(1_500) { index in "e\(index)\n" } + "class " + repeated(1_500) { index in "e\(index)," } + "e0 c,z\n",
            header + "A:::" + repeated(4_000) { index in "c\(index)," } + "z\n",
            header + "A\nstyle A fill:" + String(repeating: ":#", count: size / 2 - 20),
            header + String(repeating: "A(A) <<S>>:::c\n", count: 3_000), header + "systemBoundary S\n" + repeated(5_000) { index in "u\(index)\n" } + "end",
            header + repeated(1_000) { index in "systemBoundary s\(index)\n u\(index)\nend\n" },
            header + "A\n" + String(repeating: "note for A \"n\"\n", count: 3_000),
            header + "json P@" + String(repeating: "{\"a\":", count: 8_000) + "1" + String(repeating: "}", count: 8_000),
            header + "json P@{\"a\":[" + String(repeating: "1,", count: 20_000) + "1]}",
            header + "json P@{\"a\":\"" + String(repeating: "x", count: size - 50) + "\",}",
            header + "actor A(\"" + String(repeating: "a", count: size - 30) + "\")",
            header + "A(\"" + String(repeating: "#35;&amp;<br>", count: size / 14) + "\")",
            header + repeated(2_000) { index in "actor a\(index)\n" }, header + repeated(2_500) { index in "n\(index) --> n\(index + 1)\n" },
            header + repeated(1_800) { index in "actor a\(index)\na\(index) --> hub\n" }, header + String(repeating: "A --> B\n", count: 2_000)
                + String(repeating: "A -- l --> A\n", count: 1_000),
            complete, header + "A " + String(repeating: "-", count: 10_000) + "> B",
            header + "systemBoundary S\n U\n V\nend\n" + repeated(1_000) { index in "actor a\(index)\na\(index) --> U\nV --> a\(index)\n" },
        ]
        for source in cases {
            XCTAssertLessThanOrEqual(source.utf8.count, size, String(source.prefix(40)))
            let started = Date()
            _ = try? MermaidDiagramPreparation.prepare(source: source, typography: typography)
            XCTAssertLessThan(Date().timeIntervalSince(started), 10, String(source.prefix(40)))
        }
    }
}
