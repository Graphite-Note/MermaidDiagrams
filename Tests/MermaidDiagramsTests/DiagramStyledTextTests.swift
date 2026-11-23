/**
 * File: DiagramStyledTextTests.swift
 * ----------------------------------
 * Layer: Tests
 * Description: Labels with bold, italic and monospaced pieces measured, wrapped, drawn and written as Pele lays out,
 *              draws and writes a label's spans.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import CoreGraphics
import XCTest
@testable import MermaidDiagrams

/// The widths and lines expected are Pele 1.13.0's `layoutLabel` at 16 pixels with its table of Arial's advances, run in
/// Deno on the same texts; the package measures in Arial at 16 points, the bold and italic pieces in Arial's bold and
/// italic, which have the advances of Pele's tables to a few hundredths of a point.
final class DiagramStyledTextTests: XCTestCase {
    private let measurer = DiagramTypography(font: DiagramFont(postScriptName: "ArialMT", size: 16)).nodeText
    private let accuracy: CGFloat = 0.1

    private func block(_ text: String, form: DiagramLabelDecoder.Form = .plain, maximumWidth: CGFloat = 200) -> DiagramTextBlock {
        DiagramTextBlock(label: DiagramLabelDecoder.label(from: text, form: form), measurer: measurer, maximumWidth: maximumWidth)
    }

    private func assertRuns(_ runs: [DiagramTextRun], _ expected: [(String, DiagramTextStyle, CGFloat)], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(runs.map(\.text), expected.map(\.0), file: file, line: line)
        XCTAssertEqual(runs.map(\.style), expected.map(\.1), file: file, line: line)
        for (run, width) in zip(runs, expected.map(\.2)) { XCTAssertEqual(run.width, width, accuracy: accuracy, file: file, line: line) }
    }

    func testEachPieceIsMeasuredInItsEmphasisAndTheLineIsTheirSum() throws {
        let measured = block("**Bold** and *italic* in snake_case\n__strong__ _Markdown_", form: .markdown, maximumWidth: 130)
        let runs = try XCTUnwrap(measured.lineRuns)
        assertRuns(runs[0], [("Bold", .bold, 35.552), (" and ", [], 35.584), ("italic", .italic, 32), (" in", [], 16.896)])
        assertRuns(runs[1], [("snake_case", [], 85.376)])
        assertRuns(runs[2], [("strong", .bold, 49.776), (" ", [], 4.448), ("Markdown", .italic, 73.792)])
        XCTAssertEqual(measured.lines, ["Bold and italic in", "snake_case", "strong Markdown"])
        XCTAssertEqual(measured.lineWidths[0], 120.032, accuracy: accuracy)
        XCTAssertEqual(measured.lineHeight, 21, "Several lines are 1.3 times the size apart")
    }

    func testAStyledLineWrapsBetweenPiecesAcrossItsSpans() throws {
        let measured = block("The **quick brown fox** jumps over the *lazy dog* again and again", form: .markdown, maximumWidth: 120)
        XCTAssertEqual(measured.lines, ["The quick", "brown fox", "jumps over the", "lazy dog again", "and again"])
        let runs = try XCTUnwrap(measured.lineRuns)
        assertRuns(runs[0], [("The ", [], 32.016), ("quick", .bold, 41.792)])
        assertRuns(runs[3], [("lazy dog", .italic, 59.584), (" again", [], 43.584)])
        for (width, expected) in zip(measured.lineWidths, [73.808, 76.448, 104.928, 103.168, 70.272]) {
            XCTAssertEqual(width, expected, accuracy: accuracy)
        }
    }

    func testHTMLEmphasisIsMeasuredAsMarkdownsIs() throws {
        let measured = block("<b>A very long bold heading</b> followed by plain words", maximumWidth: 100)
        XCTAssertEqual(measured.lines, ["A very long", "bold heading", "followed by", "plain words"])
        XCTAssertEqual(try XCTUnwrap(measured.lineRuns).map { line in line.map(\.style) }, [[.bold], [.bold], [[]], [[]]])
        for (width, expected) in zip(measured.lineWidths, [87.136, 99.568, 80.032, 80.912]) { XCTAssertEqual(width, expected, accuracy: accuracy) }
    }

    func testASoftHyphenShowsWhereAWordBreaksAtIt() {
        let measured = block("super\u{AD}cali\u{AD}fragi\u{AD}listic\u{AD}expi\u{AD}ali\u{AD}docious word", maximumWidth: 80)
        XCTAssertEqual(measured.lines, ["super\u{AD}cali-", "fragi\u{AD}listic-", "expi\u{AD}ali-", "docious", "word"])
        XCTAssertNil(measured.lineRuns, "A label without emphasis keeps no runs")
    }

    func testRunsOfSpacesAreMeasured() {
        XCTAssertEqual(block("a   b").lineWidths[0], measurer.width(of: "a   b"))
        XCTAssertEqual(block("a   b").lines, ["a   b"])
    }

    func testFittingBreaksAStyledWordBetweenItsCharactersInItsEmphasis() throws {
        let label = DiagramLabelDecoder.label(from: "**Supercalifragilistic**", form: .markdown)
        let fitted = DiagramTextBlock(label: label, measurer: measurer, fittingWidth: 60)
        XCTAssertGreaterThan(fitted.lines.count, 1)
        XCTAssertEqual(fitted.lines.joined(), "Supercalifragilistic")
        let runs = try XCTUnwrap(fitted.lineRuns)
        XCTAssertTrue(runs.allSatisfy { line in line.allSatisfy { run in run.style == .bold } })
        XCTAssertTrue(fitted.lineWidths.allSatisfy { width in width <= 60 })
        XCTAssertEqual(fitted.lineHeight, 24, "A single line broken keeps the height of one line, as Pele's fitLabel does")
    }

    func testTheScenesLinesCarryTheRunsAndTheSVGWritesThemAsSpans() throws {
        var placed = block("This **is** _Markdown_", form: .markdown)
        placed.center = CGPoint(x: 100, y: 50)
        let text = DiagramSceneText(block: placed, paint: .foreground, part: .label)
        let line = try XCTUnwrap(text.lines.first)
        XCTAssertEqual(line.runs.map(\.text), ["This ", "is", " ", "Markdown"])
        XCTAssertEqual(text.styledRuns?.first?.map(\.style), [[], .bold, [], .italic])
        let scene = DiagramScene(size: CGSize(width: 200, height: 100), font: DiagramFont(postScriptName: "ArialMT", size: 16), items: [.text(text)])
        let svg = DiagramSVGWriter().document(of: scene, diagramType: "flowchart")
        XCTAssertTrue(svg.contains(">This </tspan><tspan font-weight=\"bold\">is</tspan><tspan> </tspan><tspan font-style=\"italic\">Markdown</tspan>"), svg)
    }

    func testABoldRunIsDrawnInBold() {
        func ink(_ text: String) -> Int {
            var placed = block(text, form: .markdown)
            placed.center = CGPoint(x: 50, y: 20)
            let scene = DiagramScene(size: CGSize(width: 100, height: 40), font: DiagramFont(postScriptName: "ArialMT", size: 16),
                                     items: [.text(DiagramSceneText(block: placed, paint: .foreground, part: .label))])
            return DiagramStyledTextPicture.darkPixelCount(of: scene)
        }
        XCTAssertGreaterThan(ink("**word**"), ink("word") + 20)
    }
}

/// Paints a scene on white at one pixel per point and counts its dark pixels.
enum DiagramStyledTextPicture {
    static func darkPixelCount(of scene: DiagramScene) -> Int {
        let width = Int(scene.size.width)
        let height = Int(scene.size.height)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        DiagramSceneRenderer.draw(scene, in: context, palette: .peleLight)
        guard let data = context.data else { return 0 }
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        return (0..<(width * height)).filter { index in pixels[index * 4] < 128 }.count
    }
}
