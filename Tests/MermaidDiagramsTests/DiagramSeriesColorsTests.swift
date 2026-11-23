/**
 * File: DiagramSeriesColorsTests.swift
 * ------------------------------------
 * Layer: Tests
 * Description: The series colors a diagram's theme variables set, painted: resolved over a palette as a browser resolves
 *              Pele's variables, drawn by the scene renderer, written out in palette mode, with Pele's inks, and safe on
 *              hostile values.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import CoreGraphics
import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class DiagramSeriesColorsTests: XCTestCase {
    private func prepared(_ source: String) throws -> PreparedMermaidDiagram {
        try MermaidDiagramPreparation.prepare(source: source, typography: DiagramSceneSamples.typography, now: GanttChartCorpus.now,
                                              timeZone: GanttChartCorpus.timeZone)
    }

    private func colors(_ values: [String?]) -> DiagramSeriesColors {
        DiagramSeriesColors(colors: values.map { value in value.flatMap { value in DiagramThemeColor(cssText: value) } })
    }

    /// The sRGB channels of a color, out of 255.
    private func channels(_ color: CGColor) -> [Int] {
        let space = CGColorSpace(name: CGColorSpace.extendedSRGB)!
        let components = color.converted(to: space, intent: .defaultIntent, options: nil)?.components ?? []
        return components.prefix(3).map { component in Int((component * 255).rounded()) }
    }

    private func resolved(_ values: [String?], over palette: DiagramPalette = .peleLight) -> [[Int]] {
        colors(values).palette(over: palette).series.map(channels)
    }

    func testPlainColorsAndCSSColorFunctionsResolveAsABrowserDoes() {
        let series = resolved(["#ff000080", "hsl(120 100% 25%)", "hwb(240 20% 20%)", "lab(50% 40 -20)", "oklch(70% 0.1 200)",
                               "color(srgb 0.5 0.25 1)", "rgb(10%, 20%, 30%)", "rebeccapurple"])
        XCTAssertEqual(series[0], [255, 0, 0])
        XCTAssertEqual(series[1], [0, 128, 0])
        XCTAssertEqual(series[2], [51, 51, 204])
        // CSS Color 4's conversions (lab(50% 0 0) is #777777, and the specification's lab(29.2345% 39.3825 20.0664) is
        // rgb(125 35 41) by the same code).
        XCTAssertEqual(series[3], [171, 90, 154])
        XCTAssertEqual(series[4], [64, 177, 183])
        XCTAssertEqual(resolved(["lab(50% 0 0)", "lab(29.2345% 39.3825 20.0664)"]).prefix(2), [[119, 119, 119], [125, 35, 41]])
        XCTAssertEqual(series[5], [128, 64, 255])
        XCTAssertEqual(series[6], [26, 51, 77])
        XCTAssertEqual(series[7], [102, 51, 153])
        XCTAssertEqual(colors(["#ff000080"]).palette(over: .peleLight).series[0].alpha, 128.0 / 255, accuracy: 0.001)
    }

    func testPelesVariablesTakeThePalettesRolesAndSlots() {
        let dark = DiagramScenePaletteSamples.dark
        let values = ["var(--pele-accent)", "var(--pele-series-1)", "var(--pele-series-6)", "currentColor", "light-dark(#000000, #ffffff)", nil,
                      "var(--pele-unknown, #123456)", nil]
        let light = resolved(values)
        XCTAssertEqual(light[0], channels(DiagramPalette.peleAccent))
        XCTAssertEqual(light[1], light[0], "a slot set to another set slot takes its color")
        XCTAssertEqual(light[2], channels(DiagramPalette.peleSeries[5]), "a slot left unset is the palette's own")
        XCTAssertEqual(light[3], channels(DiagramPalette.peleLight.foreground))
        XCTAssertEqual(light[4], [0, 0, 0])
        XCTAssertEqual(light[5], channels(DiagramPalette.peleSeries[5]))
        XCTAssertEqual(light[6], [18, 52, 86])
        let darkSeries = resolved(values, over: dark)
        XCTAssertEqual(darkSeries[3], channels(dark.foreground))
        XCTAssertEqual(darkSeries[4], [255, 255, 255], "a dark page takes light-dark()'s second color")
    }

    func testColorMixMixesAsCSSDoes() {
        let series = resolved(["color-mix(in srgb, red 40%, blue)", "color-mix(in srgb, red, blue)", "color-mix(in srgb-linear, white 25%, black)",
                               "color-mix(in srgb, red 30%, blue 30%)", "color-mix(in hsl, hsl(350 100% 50%), hsl(10 100% 50%))",
                               "color-mix(in oklab, var(--pele-accent) 0%, #00ff00)", "color-mix(in srgb, red 0%, blue 0%)", nil])
        XCTAssertEqual(series[0], [102, 0, 153])
        XCTAssertEqual(series[1], [128, 0, 128])
        XCTAssertEqual(series[2], [137, 137, 137])
        XCTAssertEqual(series[3], [128, 0, 128])
        XCTAssertEqual(colors(["color-mix(in srgb, red 30%, blue 30%)"]).palette(over: .peleLight).series[0].alpha, 0.6, accuracy: 0.001)
        XCTAssertEqual(series[4], [255, 0, 0], "the shorter way round the hue from 350° to 10° passes 0°")
        XCTAssertEqual(series[5], [0, 255, 0])
        XCTAssertEqual(series[6], channels(DiagramPalette.peleSeries[6]), "two 0% shares are no color, which falls back to Pele's own")
    }

    func testSlotsThatReferToThemselvesAreNoColorAndTakePelesOwn() {
        let black = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        let palette = DiagramPalette(background: white, foreground: black, line: black, surface: white, border: black, series: [black])
        let series = colors(["var(--pele-series-2)", "var(--pele-series-1, red)", "var(--pele-series-1, #00ff00)", "var(--pele-nothing)"])
            .palette(over: palette).series.map(channels)
        XCTAssertEqual(series[0], channels(DiagramPalette.peleSeries[0]))
        XCTAssertEqual(series[1], channels(DiagramPalette.peleSeries[1]), "a fallback does not break a cycle")
        XCTAssertEqual(series[2], [0, 255, 0], "a slot that refers to a cycle takes its fallback")
        XCTAssertEqual(series[3], channels(DiagramPalette.peleSeries[3]))
        XCTAssertEqual(series[4], [0, 0, 0], "an unset slot keeps the palette's own")
    }

    func testValuesThisPackageDoesNotResolveKeepThePalettesColor() {
        let series = resolved(["color(rec2020 1 0 0)", "rgb(var(--pele-accent) 0 0)", "color-mix(in srgb, red 120%, blue)", "rgb(0\u{A0}0 0)"])
        for slot in 0..<4 { XCTAssertEqual(series[slot], channels(DiagramPalette.peleSeries[slot]), "slot \(slot + 1)") }
    }

    func testInksFollowPelesReadingOfColors() {
        let onLight = DiagramSeriesInk.onLight
        let onDark = DiagramSeriesInk.onDark
        let cases: [(String, DiagramColor?)] = [
            ("#ffeb3b", onLight), ("#333", onDark), ("navy", onDark), ("LightGrey", onLight), ("darkslategrey", onDark), ("#ffffff7f", nil),
            ("#ffffff80", onLight), ("rgb(255, 255, 255)", onLight), ("rgb(100%, 0, 0)", nil), ("rgb(0 0 0 / 40%)", nil), ("hsl(60, 100%, 50%)", onLight),
            ("hsl(240 100% 25%)", onDark), ("hsl(0.5turn 100% 90%)", onLight), ("rgb(none 0 0)", onDark), ("oklch(70% 0.1 200)", nil),
            ("var(--pele-accent)", nil), ("transparent", nil), ("color-mix(in srgb, red, blue)", nil),
        ]
        for (color, ink) in cases { XCTAssertEqual(DiagramSeriesInk.ink(on: color), ink, color) }
        XCTAssertEqual(colors(["#ffeb3b", nil, "navy"]).inks, [onLight, nil, onDark, nil, nil, nil, nil, nil])
    }

    func testSafeColorsAreCheckedAsPeleChecksThem() {
        let safe = ["red", "#AbC", "Transparent", "currentColor", "rgb (0 0 0)", "hsl(0 50% 50% / 0.5)", "var(  --pele-x)", "VAR(--pele-bg)",
                    "color-mix(in oklch longer hue, red, blue)", "  red  "]
        for value in safe { XCTAssertNotNil(DiagramThemeColor(cssText: value), value) }
        XCTAssertEqual(DiagramThemeColor(cssText: "  red  ")?.cssText, "red")
        let unsafe = ["", "red blue", "rgb(0 0 0))", "calc(1)", "a-rgb(0 0 0)", "(red)", "var(--x)", "var(-- pele-x)", "rgb(0 0 0); x",
                      String(repeating: "a", count: 201), "rgb(0 0 0)\"", "#12345"]
        for value in unsafe { XCTAssertNil(DiagramThemeColor(cssText: value), value) }
        XCTAssertEqual(DiagramThemeColor(cssText: "\u{A0}red\u{FEFF}\u{2028}")?.cssText, "red", "JavaScript's trim takes Unicode's spaces away")
    }

    func testHostileValuesNeverCrashOrRecurseWithoutEnd() {
        // Fourteen nested var()s in 199 characters are deeper than a value is read here: the palette's color stays.
        let nested = String(repeating: "var(--pele-a,", count: 14) + "red" + String(repeating: ")", count: 14)
        XCTAssertNotNil(DiagramThemeColor(cssText: nested))
        let deep = String(repeating: "(", count: 99) + String(repeating: ")", count: 99)
        XCTAssertNil(DiagramThemeColor(cssText: deep))
        let values: [String?] = [nested, "var(--pele-series-3)", "var(--pele-series-8)", "var(--pele-series-7)", "var(--pele-series-6)",
                                 "var(--pele-series-5)", "var(--pele-series-4)", "var(--pele-series-2)"]
        let series = colors(values).palette(over: .peleLight).series
        XCTAssertEqual(series.count, DiagramSeriesColors.slotCount)
        XCTAssertEqual(channels(series[0]), channels(DiagramPalette.peleSeries[0]))
        XCTAssertEqual(channels(series[1]), channels(DiagramPalette.peleSeries[1]), "every slot of the cycle is Pele's own")
        let longList = "xychart\n  bar [1, 2]\n"
        let source = "---\nconfig:\n  themeVariables:\n    xyChart:\n      plotColorPalette: '" + String(repeating: "red, ", count: 9_000) + "blue'\n---\n" + longList
        XCTAssertEqual(try prepared(source).scene.seriesColors.colors.compactMap { color in color?.cssText }, Array(repeating: "red", count: 8))
    }

    func testTheRendererPaintsThePieInItsThemeColors() throws {
        let scene = try prepared("%%{init: {\"themeVariables\": {\"pie1\": \"#ff0000\", \"pie2\": \"#00ff00\"}}}%%\npie\n  \"A\": 1\n  \"B\": 1").scene
        let bitmap = try XCTUnwrap(DiagramBitmap(size: scene.size))
        bitmap.paint { context in DiagramSceneRenderer.draw(scene, in: context, palette: .peleLight) }
        var found: Set<[Int]> = []
        for y in stride(from: 0, to: bitmap.height, by: 2) {
            for x in stride(from: 0, to: bitmap.width, by: 2) { found.insert(bitmap.color(at: CGPoint(x: x, y: y))) }
        }
        XCTAssertTrue(found.contains([255, 0, 0]))
        XCTAssertTrue(found.contains([0, 255, 0]))
        XCTAssertFalse(found.contains(channels(DiagramPalette.peleSeries[0])), "the first series is no longer Pele's own blue")
        let written = DiagramSVGWriter(colors: .palette(.peleLight)).document(of: scene, diagramType: "pie")
        XCTAssertTrue(written.contains("fill=\"#ff0000\""))
        XCTAssertTrue(written.contains("fill=\"#00ff00\""))
        XCTAssertFalse(written.contains("--pele-series-1:"))
    }

    func testCorpusExamplesWithThemeVariablesPaintTheirColors() throws {
        let red = [255, 0, 0]
        let green = [0, 255, 0]
        let blue = [0, 0, 255]
        let examples: [(String, String, [[Int]])] = [
            ("git-graph", try GitGraphCorpus.documentationExamples()[28], [red, green, blue, [255, 0, 255], [0, 255, 255], [255, 255, 0]]),
            ("timeline", try TimelineCorpus.documentationExamples()[8], [red, green, blue]),
            ("radar", try RadarChartCorpus.documentationExamples()[2], [red, green, blue]),
            ("xy-chart", try XYChartCorpus.documentationExamples()[2], [[0, 0, 0], blue, green, red]),
        ]
        for (name, source, expected) in examples {
            let scene = try prepared(source).scene
            XCTAssertEqual(Array(scene.palette(over: .peleLight).series.map(channels).prefix(expected.count)), expected, name)
            PlaneMapPictures.write(scene, named: "theme-palette-" + name)
        }
        let pie = "---\nconfig:\n  themeVariables:\n    pie1: '#ffeb3b'\n    pie2: navy\n    pie3: 'oklch(60% 0.15 30)'\n    pie4: 'light-dark(#ddd, #333)'\n---\n"
            + "pie title Pets\n  \"Dogs\": 386\n  \"Cats\": 85\n  \"Rats\": 150\n  \"Fish\": 60\n  \"Birds\": 90"
        let pieScene = try prepared(pie).scene
        PlaneMapPictures.write(pieScene, named: "theme-palette-pie")
        PlaneMapPictures.write(pieScene, named: "theme-palette-pie-dark", palette: DiagramScenePaletteSamples.dark)
        let titleColored = try prepared(XYChartCorpus.documentationExamples()[7]).scene
        XCTAssertTrue(titleColored.seriesColors.isEmpty, "xyChart.titleColor is not one of Pele's palettes")
    }
}
