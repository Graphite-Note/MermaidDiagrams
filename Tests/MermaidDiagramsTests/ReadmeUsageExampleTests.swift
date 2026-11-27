/**
 * File: ReadmeUsageExampleTests.swift
 * -----------------------------------
 * Layer: Tests
 * Description: The README's usage example, line for line, with the public interface only: a diagram's text prepared,
 *              painted into a bitmap context whose y runs down and written as a standalone SVG document.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 27/11/2026
 */

import CoreGraphics
import MermaidDiagrams
import XCTest

final class ReadmeUsageExampleTests: XCTestCase {
    func testTheReadmeExamplePreparesPaintsAndWritesADiagram() throws {
        let text = "flowchart LR\n    A[Hard edge] -->|Link text| B(Round edge)"
        let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        let black = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        let palette = DiagramPalette(background: white, foreground: black, line: black, surface: white, border: black)
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: 400, height: 200, bitsPerComponent: 8, bytesPerRow: 1_600,
                                              space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.translateBy(x: 0, y: 200)
        context.scaleBy(x: 1, y: -1)

        // The README's lines.
        let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16)) // Made once, kept for every diagram.
        let prepared = try MermaidDiagramPreparation.prepare(source: text, typography: typography)
        DiagramSceneRenderer.draw(prepared.scene, in: context, palette: palette)              // A CGContext whose y runs down.
        let svg = prepared.svgDocument()                                                       // Or a standalone SVG.

        XCTAssertEqual(prepared.kind, .flowchart)
        XCTAssertGreaterThan(prepared.scene.size.width, 0)
        XCTAssertTrue(svg.contains("<svg"), String(svg.prefix(80)))
        XCTAssertTrue(svg.contains("Round edge"))
    }
}
