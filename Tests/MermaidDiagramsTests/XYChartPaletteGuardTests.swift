/**
 * File: XYChartPaletteGuardTests.swift
 * ------------------------------------
 * Layer: Tests
 * Description: The XY chart reader reads its theme's plot palette only when the text names it or holds a backslash,
 *              and gives every chart the series colors reading the palette always gave: palettes in front matter and
 *              directives, written plainly, quoted, escaped, in the wrong section, named only in a title, and none.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class XYChartPaletteGuardTests: XCTestCase {
    private static let charts = [
        "xychart-beta\nbar [1, 2]",
        "xychart-beta\ntitle \"plotColorPalette\"\nline [1, 2]",
        "xychart-beta horizontal\nx-axis [a, b]\nbar \"plot\\\\ColorPalette\" [3, 4]",
    ]

    private static let configurations = [
        "",
        "---\nconfig:\n  themeVariables:\n    xyChart:\n      plotColorPalette: '#f00, #0f0, rgb(1,2,3)'\n---\n",
        "---\nconfig:\n  themeVariables:\n    xyChart:\n      \"plotColorPalette\": \"#123, red\"\n---\n",
        "---\nconfig:\n  themeVariables:\n    xyChart:\n      \"plot\\x43olorPalette\": \"#123, red\"\n---\n",
        "---\nconfig:\n  themeVariables:\n    xyChart: {plotColorPalette: '#abc'}\n---\n",
        "---\nconfig:\n  themeVariables:\n    pie1: '#f00'\n---\n",
        "---\nconfig:\n  xyChart:\n    plotColorPalette: '#f00'\n---\n",
        "%%{init: {\"themeVariables\": {\"xyChart\": {\"plotColorPalette\": \"#f00, #00f\"}}}}%%\n",
        "%%{init: {\"themeVariables\": {\"xyChart\": {\"plot\\u0043olorPalette\": \"#f00, #00f\"}}}}%%\n",
        "%%{init: {'themeVariables': {'xyChart': {'plotColorPalette': 'hsl(1 2% 3%), oklch(50% 0.1 20)'}}}}%%\n",
        "%%{init: {\"themeVariables\": {\"pie1\": \"#f00\"}}}%%\n",
    ]

    /// Each chart under each configuration: the reader's series colors are those the theme's palette gives the text.
    func testTheSeriesColorsAreThoseThePaletteGivesWhetherOrNotItIsRead() throws {
        var comparedCount = 0
        var coloredCount = 0
        for configuration in Self.configurations {
            for chart in Self.charts {
                let source = configuration + chart
                guard let cursor = MapReadingEquivalence.cursor(of: source, readAs: .xyChart) else { continue }
                let read = try XYChartParser.parse(cursor, limits: .standard)
                let expected = MermaidThemeSeriesPalette.xyChart.seriesColors(in: cursor)
                XCTAssertEqual(read.seriesColors, expected, source)
                comparedCount += 1
                if expected != DiagramSeriesColors.none { coloredCount += 1 }
            }
        }
        XCTAssertEqual(comparedCount, Self.configurations.count * Self.charts.count)
        // The palettes written, plainly, quoted, in flow form and escaped, color their charts.
        XCTAssertGreaterThanOrEqual(coloredCount, 6 * Self.charts.count)
    }
}
