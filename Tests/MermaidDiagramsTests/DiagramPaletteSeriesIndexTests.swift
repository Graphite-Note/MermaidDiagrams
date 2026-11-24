/**
 * File: DiagramPaletteSeriesIndexTests.swift
 * ------------------------------------------
 * Layer: Tests
 * Description: A palette's series color at any index, negative ones included, which trapped before 0.8.0, and the SVG
 *              writer in palette mode for a scene that paints them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
import XCTest
@testable import MermaidDiagrams

final class DiagramPaletteSeriesIndexTests: XCTestCase {
    private let palette = DiagramPalette.peleLight

    func testEveryIndexTakesTheSlotTheSeriesColorsTake() {
        let count = palette.series.count
        for index in -3 * count...3 * count {
            XCTAssertEqual(palette.seriesColor(at: index), palette.series[DiagramSeriesColors.slot(ofSeries: index)], "index \(index)")
        }
        XCTAssertEqual(palette.seriesColor(at: -1), palette.series[count - 1])
        XCTAssertEqual(palette.seriesColor(at: Int.min), palette.series[DiagramSeriesColors.slot(ofSeries: Int.min)])
        XCTAssertEqual(palette.seriesColor(at: Int.max), palette.series[DiagramSeriesColors.slot(ofSeries: Int.max)])
    }

    func testAPaletteOfOtherLengthCountsBackFromItsLast() {
        var three = palette
        three.series = Array(palette.series.prefix(3))
        XCTAssertEqual(three.seriesColor(at: -1), three.series[2])
        XCTAssertEqual(three.seriesColor(at: -4), three.series[2])
        XCTAssertEqual(three.seriesColor(at: -3), three.series[0])
        var none = palette
        none.series = []
        XCTAssertEqual(none.seriesColor(at: -5), none.line)
    }

    /// A scene painted in a negative series is written in palette mode in the color the variables mode names.
    func testTheSVGWriterInPaletteModeWritesANegativeSeries() {
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: 4, height: 4), transform: nil)
        let items = [-1, -9, 7].map { index in
            DiagramSceneItem.shape(DiagramSceneShape(path: path, painting: .fill(DiagramPaint(.series(index))), part: .node))
        }
        let scene = DiagramScene(size: CGSize(width: 10, height: 10), font: DiagramFont(postScriptName: nil, size: 12), items: items)
        let document = DiagramSVGWriter(colors: .palette(palette)).document(of: scene, diagramType: "pie")
        let lastSeries = DiagramSVGColors.hexadecimal(palette.series[7])
        XCTAssertEqual(document.components(separatedBy: lastSeries).count - 1, 3, document)
    }
}
