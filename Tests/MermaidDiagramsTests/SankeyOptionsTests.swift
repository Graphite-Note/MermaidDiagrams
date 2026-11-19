/**
 * File: SankeyOptionsTests.swift
 * ------------------------------
 * Layer: Tests
 * Description: The Sankey options that colour and outline (labelStyle, linkColor, nodeColors) and the narrow column's
 *              chart, as Pele's Sankey renderer applies them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class SankeyOptionsTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))
    private let rows = "sankey\nCoal,Power,60\nGas,Power,40\nPower,Homes,70\nPower,Industry,30"

    private func options(_ written: String) throws -> SankeyOptions {
        try SankeyReading.diagram("---\nconfig:\n  sankey:\n    " + written.replacingOccurrences(of: "; ", with: "\n    ") + "\n---\n" + rows).options
    }

    private func laidOut(_ written: String, availableWidth: CGFloat? = nil, rows: String? = nil) throws -> SankeyLayout {
        let source = "---\nconfig:\n  sankey:\n    " + written.replacingOccurrences(of: "; ", with: "\n    ") + "\n---\n" + (rows ?? self.rows)
        return try SankeyLayoutEngine.layout(try SankeyReading.diagram(source), typography: typography, availableWidth: availableWidth)
    }

    func testTheColouringOptionsAreRead() throws {
        let plain = try SankeyReading.diagram(rows).options
        XCTAssertFalse(plain.isOutlined)
        XCTAssertEqual(plain.linkColor, .gradient)
        XCTAssertTrue(plain.nodeColors.isEmpty)
        XCTAssertTrue(try options("labelStyle: outlined").isOutlined)
        XCTAssertFalse(try options("labelStyle: plain").isOutlined)
        XCTAssertEqual(try options("linkColor: source").linkColor, .source)
        XCTAssertEqual(try options("linkColor: target").linkColor, .target)
        XCTAssertEqual(try options("linkColor: \"#ff0000\"").linkColor, .fixed(DiagramColor(red: 1, green: 0, blue: 0)))
        XCTAssertEqual(try options("linkColor: red").linkColor, .fixed(DiagramColor(red: 1, green: 0, blue: 0)))
        XCTAssertEqual(try options("linkColor: var(--mine)").linkColor, .source, "A color not read is a band in its source's color, as in Pele")
        XCTAssertEqual(try options("linkColor: 5").linkColor, .gradient, "Not text")
    }

    func testNodeColorsAreReadFromBlockFlowAndDirectiveFormsByNodeName() throws {
        let block = try SankeyReading.diagram("---\nconfig:\n  sankey:\n    nodeColors:\n      Coal: \"#000000\"\n      Power plant: \"#ff0000\"\n      Gas: notAColor\n---\n" + rows).options
        XCTAssertEqual(block.nodeColors, ["Coal": DiagramColor(red: 0, green: 0, blue: 0), "Power plant": DiagramColor(red: 1, green: 0, blue: 0)])
        let flow = try SankeyReading.diagram("---\nconfig:\n  sankey:\n    nodeColors: {Coal: \"#000\", Homes: blue}\n---\n" + rows).options
        XCTAssertEqual(Set(flow.nodeColors.keys), ["Coal", "Homes"])
        let directive = try SankeyReading.diagram("%%{init: {'sankey': {'nodeColors': {'Gas': '#00ff00', 'Nested': {'inner': 'red'}}}}}%%\n" + rows).options
        XCTAssertEqual(directive.nodeColors, ["Gas": DiagramColor(red: 0, green: 1, blue: 0)], "An entry that is itself a mapping is no color")
        let dotted = try SankeyReading.diagram("---\nconfig:\n  sankey:\n    nodeColors:\n      \"a.b\": red\n---\n" + rows).options
        XCTAssertEqual(dotted.nodeColors, ["a.b": DiagramColor(red: 1, green: 0, blue: 0)], "A name with a dot")
    }

    func testANodeWithAColorCarriesItAndTheLayoutKeepsTheOptions() throws {
        let layout = try laidOut("nodeColors: {Coal: \"#336699\"}; linkColor: target; labelStyle: outlined")
        XCTAssertEqual(layout.nodes[0].color, DiagramColor(red: 0.2, green: 0.4, blue: 0.6))
        XCTAssertTrue(layout.nodes.dropFirst().allSatisfy { node in node.color == nil })
        XCTAssertEqual(layout.linkColor, .target)
        XCTAssertTrue(layout.hasOutlinedLabels)
        let plain = try laidOut("showValues: true")
        XCTAssertEqual(plain.linkColor, .gradient)
        XCTAssertFalse(plain.hasOutlinedLabels)
    }

    func testOutlinedLabelsStandAfterTheirBarsFromTheFullestColumnOn() throws {
        let plain = try laidOut("showValues: true")
        let outlined = try laidOut("labelStyle: outlined")
        // The nodes in the order the rows name them: Coal, Power, Gas, Homes, Industry; Power is the fullest.
        XCTAssertGreaterThan(plain.labels[0].name.frame.minX, plain.nodes[0].frame.maxX, "Plain: after the bar in the left half")
        XCTAssertLessThan(plain.labels[3].name.frame.maxX, plain.nodes[3].frame.minX, "Plain: before the bar in the right half")
        XCTAssertLessThan(outlined.labels[0].name.frame.maxX, outlined.nodes[0].frame.minX, "Outlined: before the first column's bars")
        XCTAssertGreaterThan(outlined.labels[1].name.frame.minX, outlined.nodes[1].frame.maxX, "Outlined: after the fullest column's bar")
        XCTAssertGreaterThan(outlined.labels[3].name.frame.minX, outlined.nodes[3].frame.maxX, "Outlined: after the last column's bars")
    }

    func testTheSceneColoursAndOutlinesWhatTheOptionsSay() throws {
        func scene(_ written: String) throws -> DiagramScene {
            DiagramScene(layout: try laidOut(written))
        }
        let gradient = try scene("showValues: true")
        XCTAssertTrue(gradient.shapes.contains { shape in if case .gradientFill = shape.painting { true } else { false } })
        XCTAssertTrue(gradient.texts.allSatisfy { text in text.outline == nil })
        let outlined = try scene("labelStyle: outlined")
        XCTAssertTrue(outlined.texts.filter { text in text.part == .label }.allSatisfy { text in text.outline == DiagramTextOutline(paint: .background, lineWidth: 3) })
        XCTAssertNil(outlined.texts.first { text in text.part == .title }?.outline)
        let target = try scene("linkColor: target")
        XCTAssertFalse(target.shapes.contains { shape in if case .gradientFill = shape.painting { true } else { false } })
        let bandPaints = target.shapes.filter { shape in shape.part == .edge }.compactMap { shape -> DiagramPaint? in
            if case .fill(let paint) = shape.painting { paint } else { nil }
        }
        XCTAssertEqual(Set(bandPaints), [DiagramPaint.series(1).atOpacity(0.4), DiagramPaint.series(3).atOpacity(0.4), DiagramPaint.series(4).atOpacity(0.4)],
                       "Each band in its target's series color at 0.4: Power, Homes and Industry")
        let fixed = try scene("linkColor: \"#102030\"")
        let fixedPaints = Set(fixed.shapes.filter { shape in shape.part == .edge }.compactMap { shape -> DiagramPaint? in
            if case .fill(let paint) = shape.painting { paint } else { nil }
        })
        XCTAssertEqual(fixedPaints, [DiagramPaint.color(DiagramColor(red: 16 / 255, green: 32 / 255, blue: 48 / 255)).atOpacity(0.4)])
        let colored = try scene("nodeColors: {Coal: \"#336699\"}")
        let nodePaints = colored.shapes.filter { shape in shape.part == .node }.compactMap { shape -> DiagramPaint? in
            if case .fill(let paint) = shape.painting { paint } else { nil }
        }
        XCTAssertTrue(nodePaints.contains(DiagramPaint.color(DiagramColor(red: 0.2, green: 0.4, blue: 0.6))))
        XCTAssertFalse(nodePaints.contains(.series(0)), "Coal's bar is in its own color; no other node has the first series color")
    }

    func testTheOutlinesAreStrokedUnderTheTextInPixelsAndInSVG() throws {
        let layout = try laidOut("labelStyle: outlined; linkColor: source")
        let scene = DiagramScene(layout: layout)
        let svg = DiagramSVGWriter(colors: .peleVariables).document(of: scene, diagramType: "sankey", title: "T", description: "D")
        XCTAssertTrue(svg.contains("fill=\"none\" xml:space=\"preserve\" stroke=\"var(--_bg)\" stroke-width=\"3\" stroke-linejoin=\"round\""))
        XCTAssertNotNil(DiagramSVGDocumentReading.read(svg))
        // In pixels, the outline puts the page's color around the glyphs: with a black page the pixels near a label are not the label's alone.
        var palette = DiagramPalette.peleLight
        palette.background = CGColor(red: 1, green: 0, blue: 0, alpha: 1)
        let width = Int(scene.size.width), height = Int(scene.size.height)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return XCTFail("A bitmap") }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: scene.size))
        DiagramSceneRenderer.draw(scene, in: context, palette: palette)
        let data = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = context.bytesPerRow
        let label = layout.labels[0].name.frame.insetBy(dx: -2, dy: -2)
        var redPixels = 0
        for y in Int(label.minY)..<Int(label.maxY) {
            for x in Int(label.minX)..<Int(label.maxX) {
                let pixel = data + y * bytesPerRow + x * 4
                if pixel[0] > 200, pixel[1] < 120, pixel[2] < 120 { redPixels += 1 }
            }
        }
        XCTAssertGreaterThan(redPixels, 10, "The outline in the page's color is drawn around the glyphs")
    }

    // MARK: Narrow columns

    func testANarrowColumnNarrowsTheChartAndShrinksTheLabelsWithIt() throws {
        let natural = try laidOut("showValues: true")
        XCTAssertGreaterThan(natural.size.width, 600)
        let narrow = try laidOut("showValues: true", availableWidth: 400)
        XCTAssertLessThanOrEqual(narrow.size.width, 400, "The chart gives up what its labels overflow")
        XCTAssertLessThan(narrow.labels[0].name.fontSize, natural.labels[0].name.fontSize)
        XCTAssertTrue(narrow.nodes.allSatisfy { node in CGRect(origin: .zero, size: narrow.size).contains(node.frame) })
        XCTAssertTrue(narrow.labels.allSatisfy { label in CGRect(origin: .zero, size: narrow.size).contains(label.name.frame) })
        XCTAssertEqual(try laidOut("showValues: true", availableWidth: 900), natural, "A column the chart fits leaves it as it is")
        XCTAssertEqual(try laidOut("showValues: true", availableWidth: nil), natural)
    }

    func testTheChartIsNeverNarrowerThanItsLeastAndTheLabelsNeverSmallerThanFiveEighths() throws {
        let narrowest = try laidOut("showValues: true", availableWidth: 50)
        let chartWidth = narrowest.nodes.map(\.frame.maxX).max()! - narrowest.nodes.map(\.frame.minX).min()!
        XCTAssertGreaterThanOrEqual(chartWidth, 160 - 0.001)
        XCTAssertGreaterThanOrEqual(narrowest.labels[0].name.fontSize, 10, "Five eighths of 16")
        let own = try laidOut("width: 120", availableWidth: 50)
        XCTAssertLessThanOrEqual(own.nodes.map(\.frame.maxX).max()! - own.nodes.map(\.frame.minX).min()!, 120.001, "Not wider than its own width when that is under 160")
    }

    func testTheTitleWrapsToTheColumn() throws {
        let source = "---\ntitle: A rather long title for a narrow column of a reading view\nconfig:\n  sankey:\n    width: 200\n---\n" + rows
        let wide = try SankeyLayoutEngine.layout(try SankeyReading.diagram(source), typography: typography)
        let narrow = try SankeyLayoutEngine.layout(try SankeyReading.diagram(source), typography: typography, availableWidth: 300)
        XCTAssertEqual(wide.title?.lines.count, 1)
        XCTAssertGreaterThan(narrow.title?.lines.count ?? 0, 1, "Wrapped at the column's width less the padding")
        XCTAssertLessThanOrEqual(narrow.title?.size.width ?? 0, 300 - 16 + 0.001)
    }

    func testAPreparedDiagramHasANarrowSceneForTheNarrowestColumn() throws {
        let prepared = try MermaidDiagramPreparation.prepare(source: rows, typography: typography)
        let narrow = try XCTUnwrap(prepared.narrowScene)
        XCTAssertLessThan(narrow.size.width, prepared.scene.size.width)
        XCTAssertLessThanOrEqual(narrow.size.width, 400, "Labels outside the chart keep it wider than 280")
        XCTAssertTrue(prepared.showsNarrowScene(inColumnWidth: 350))
        let small = try MermaidDiagramPreparation.prepare(source: "---\nconfig:\n  sankey:\n    width: 100\n    height: 100\n---\nsankey\na,b,1", typography: typography)
        XCTAssertNil(small.narrowScene, "No wider than the narrowest column")
    }
}
