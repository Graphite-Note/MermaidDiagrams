/**
 * File: PeleThemePaletteTests.swift
 * ---------------------------------
 * Layer: Tests
 * Description: Pele's palette tests (tests/render/palette.test.ts) ported: the series colors each type's theme variables
 *              set, written on the SVG's root as Pele writes them, unsafe values dropped, and the label inks on them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class PeleThemePaletteTests: XCTestCase {
    private static let pie = "pie\n  \"A\": 1\n  \"B\": 2"
    private static let xyChart = "xychart\n  bar [1, 2]\n  line [2, 1]"

    /// `body` after a directive that sets `variables`, as Pele's test writes it with `JSON.stringify`.
    private func themed(_ variables: [String: Any], _ body: String) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: ["themeVariables": variables], options: [.sortedKeys])
        return "%%{init: \(String(decoding: data, as: UTF8.self))}%%\n" + body
    }

    private func prepared(_ source: String) throws -> PreparedMermaidDiagram {
        try MermaidDiagramPreparation.prepare(source: source, typography: DiagramSceneSamples.typography, now: GanttChartCorpus.now,
                                              timeZone: GanttChartCorpus.timeZone)
    }

    private func svg(_ source: String) throws -> String {
        try prepared(source).svgDocument()
    }

    /// The `--pele-series-N` declarations of the root's style, as Pele's test reads them.
    private func series(_ document: String) throws -> [Int: String] {
        let rootStyle = try XCTUnwrap(document.firstMatch(of: /^<svg[^>]*\bstyle="([^"]*)"/)?.1)
        var found: [Int: String] = [:]
        for match in rootStyle.matches(of: /--pele-series-(\d):([^;]*)/) { found[Int(match.1) ?? 0] = String(match.2) }
        return found
    }

    func testXYChartSeriesTakeThePlotColorPaletteRepeatingAShortList() throws {
        let source = """
            ---
            config:
              themeVariables:
                xyChart:
                  plotColorPalette: '#000000, #0000FF, #00FF00, #FF0000'
            ---
            xychart
            title "Different Colors in xyChart"
            x-axis "categoriesX" ["Category 1", "Category 2", "Category 3", "Category 4"]
            y-axis "valuesY" 0 --> 50
            line [10,20,30,40]
            bar [20,30,25,35]
            bar [15,25,20,30]
            line [5,15,25,35]
            """
        let document = try svg(source)
        XCTAssertEqual(try series(document), [1: "#000000", 2: "#0000FF", 3: "#00FF00", 4: "#FF0000", 5: "#000000", 6: "#0000FF", 7: "#00FF00",
                                              8: "#FF0000"])
        XCTAssertTrue(document.contains("stroke=\"var(--pele-series-1,"))
    }

    func testCommasInsideColorFunctionsAreKept() throws {
        let found = try series(svg(themed(["xyChart": ["plotColorPalette": "rgb(0, 0, 0), hsl(0 50% 50% / 0.5)"]], Self.xyChart)))
        XCTAssertEqual(found[1], "rgb(0, 0, 0)")
        XCTAssertEqual(found[2], "hsl(0 50% 50% / 0.5)")
    }

    func testEachTypesPaletteSetsItsSeriesInOrder() throws {
        let cases: [(String, [String: String])] = [
            (Self.pie, ["pie1": "red", "pie2": "blue"]),
            ("gitGraph\n  commit", ["git0": "red", "git1": "blue"]),
            ("timeline\n  2001 : a\n  2002 : b", ["cScale0": "red", "cScale1": "blue"]),
            ("radar-beta\n  axis a, b, c\n  curve x{1,2,3}", ["cScale0": "red", "cScale1": "blue"]),
            ("treemap\n\"a\": 1\n\"b\": 2", ["cScale0": "red", "cScale1": "blue"]),
            ("mindmap\n  root\n    a\n    b", ["cScale0": "green", "cScale1": "red", "cScale2": "blue"]),
        ]
        for (body, variables) in cases {
            XCTAssertEqual(try series(svg(themed(variables, body))), [1: "red", 2: "blue"], body)
        }
    }

    func testAVennDiagramRepeatsTheColorsThatAreSet() throws {
        let found = try series(svg(themed(["venn2": "red", "venn4": "blue"], "venn-beta\n  set A\n  set B")))
        XCTAssertEqual(found, [1: "red", 2: "blue", 3: "red", 4: "blue", 5: "red", 6: "blue", 7: "red", 8: "blue"])
    }

    func testOtherTypesPalettesAndOtherThemeColorsAreIgnored() throws {
        XCTAssertEqual(try series(svg(themed(["cScale0": "red", "primaryColor": "red"], Self.pie))), [:])
        XCTAssertEqual(try series(svg(themed(["fillType0": "red", "cScale0": "red"], "journey\n  section S\n    Task: 5: Me"))), [:])
        XCTAssertEqual(try series(svg(themed(["pie1": "red"], "flowchart LR\n  a --> b"))), [:])
    }

    /// Pele also reads the host's `config` option; this package's preparation takes no such option.
    func testThemeVariablesAreReadFromFrontMatterAndDirectives() throws {
        XCTAssertEqual(try series(svg("---\nconfig:\n  themeVariables:\n    pie1: '#123456'\n---\n" + Self.pie)), [1: "#123456"])
        let both = "---\nconfig:\n  themeVariables:\n    pie1: '#123456'\n---\n%%{init: {\"themeVariables\": {\"pie2\": \"oklch(70% 0.1 200)\"}}}%%\n" + Self.pie
        XCTAssertEqual(try series(svg(both)), [1: "#123456", 2: "oklch(70% 0.1 200)"])
    }

    func testThemeAwareColorsAreAccepted() throws {
        let variables = ["pie1": "var(--pele-accent)", "pie2": "light-dark(#000, #fff)", "pie3": "color-mix(in srgb, red 40%, blue)"]
        XCTAssertEqual(try series(svg(themed(variables, Self.pie))),
                       [1: "var(--pele-accent)", 2: "light-dark(#000, #fff)", 3: "color-mix(in srgb, red 40%, blue)"])
    }

    func testValuesThatAreNotColorsAreDroppedAndKeepTheThemesColor() throws {
        let unsafe = [
            "url(https://example.com/a.svg)", "url(//example.com/a.svg)", "image-set(a 1x)", "red;stroke:blue", "\"><script>alert(1)</script>",
            "expression(alert(1))", "rgb(0, 0", "red)", "red}", "javascript:alert(1)", "/*", "reddish", "#ff00000", "var(--page-color)",
            "color-mix(in srgb, var(--page-color) 50%, red)",
        ]
        for value in unsafe {
            let document = try svg(themed(["pie1": value, "pie2": "blue"], Self.pie))
            XCTAssertEqual(try series(document), [2: "blue"], value)
            XCTAssertFalse(document.contains("<script"), value)
            XCTAssertFalse(document.contains("url("), value)
        }
        let list = try svg(themed(["xyChart": ["plotColorPalette": "url(a), blue"]], Self.xyChart))
        XCTAssertEqual(try series(list), [2: "blue", 4: "blue", 6: "blue", 8: "blue"])
    }

    func testLabelsOnPaletteColorsTakeTheInkThatContrasts() throws {
        let pie = try prepared(themed(["pie1": "#ffeb3b", "pie2": "navy", "pie3": "var(--pele-accent)"], "pie\n  \"A\": 1\n  \"B\": 1\n  \"C\": 1")).scene
        let percentages = pie.texts.filter { text in text.block.lines.first?.hasSuffix("%") == true }
        XCTAssertEqual(percentages.map(\.paint), [.color(DiagramSeriesInk.onLight), .color(DiagramSeriesInk.onDark), .background])

        let git = try prepared(themed(["git0": "#ffeb3b"], "gitGraph\n  commit\n  branch dev\n  commit")).scene
        XCTAssertEqual(git.texts.filter { text in text.part == .clusterLabel }.map(\.paint), [.color(DiagramSeriesInk.onLight), .background])

        let timeline = try prepared(themed(["cScale0": "#ffeb3b"], "timeline\n  section S\n    2001 : a")).scene
        XCTAssertEqual(timeline.texts.filter { text in text.paint == .color(DiagramSeriesInk.onLight) }.count, 2)

        let treemap = try prepared(themed(["cScale0": "#ffeb3b"], "treemap\n\"a\": 1\n\"b\": 1")).scene
        XCTAssertEqual(treemap.texts.filter { text in text.paint == .color(DiagramSeriesInk.onLight) }.count, 2)
    }

    func testTheOutputIsUnchangedWithoutAPalette() throws {
        XCTAssertEqual(try svg(Self.pie), try svg(themed(["primaryColor": "red"], Self.pie)))
        XCTAssertFalse(try svg(Self.pie).contains("--pele-series-1:"))
        XCTAssertTrue(try prepared(Self.pie).scene.seriesColors.isEmpty)
    }
}
