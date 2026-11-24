/**
 * File: DiagramSceneTextBytesTests.swift
 * --------------------------------------
 * Layer: Tests
 * Description: Text read from the bytes its storage keeps is what 0.7.0 made Strings of: every corpus's texts are painted
 *              to the pixel as the frozen String drawing painted them, at one pixel a point and a quarter at two; runs read
 *              as bytes are its runs; text escaped in one pass is what the frozen writer escaped byte by byte; and every
 *              part's ordinal is its place among all parts.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class DiagramSceneTextBytesTests: XCTestCase {
    /// The scene of every input of every corpus that is prepared.
    private static func corpusScenes() throws -> [(name: String, scene: DiagramScene)] {
        var scenes: [(String, DiagramScene)] = []
        for (corpusName, corpus) in try OutputDigest.corpora() {
            for (index, source) in corpus.enumerated() {
                guard let prepared = try? MermaidDiagramPreparation.prepare(source: source, typography: DiagramSceneSamples.typography,
                                                                            narrowestColumnWidth: nil, now: GanttChartCorpus.now,
                                                                            timeZone: GanttChartCorpus.timeZone) else { continue }
                scenes.append(("\(corpusName) \(index)", prepared.scene))
            }
        }
        return scenes
    }

    /// The texts of `scene` drawn as 0.7.0 drew them, with the frozen drawing, and as `DiagramSceneRenderer` places them.
    private static func drawTextsAsBefore(of scene: DiagramScene, in context: CGContext, palette: DiagramPalette) {
        var colors = DiagramPaintColors(palette: scene.palette(over: palette))
        var text = ReferenceDiagramTextDrawing(font: scene.font)
        context.saveGState()
        for placed in scene.texts {
            let color = colors.color(of: placed.paint)
            let outline = placed.outline.map { outline in (color: colors.color(of: outline.paint), lineWidth: outline.lineWidth) }
            guard let rotation = placed.rotation else {
                text.draw(placed.block, color: color, isBold: placed.isBold, isItalic: placed.isItalic, isMonospaced: placed.isMonospaced,
                          outline: outline, in: context)
                continue
            }
            context.saveGState()
            context.translateBy(x: placed.block.center.x, y: placed.block.center.y)
            context.rotate(by: rotation)
            var centered = placed.block
            centered.center = .zero
            text.draw(centered, color: color, isBold: placed.isBold, isItalic: placed.isItalic, isMonospaced: placed.isMonospaced, outline: outline,
                      in: context)
            context.restoreGState()
        }
        context.restoreGState()
    }

    func testEveryCorpusTextIsPaintedAsTheStringDrawingPaintedIt() throws {
        var comparedTextCount = 0
        var emphasisCount = 0
        var rotatedCount = 0
        var outlinedCount = 0
        for (sceneIndex, (name, scene)) in try Self.corpusScenes().enumerated() where !scene.texts.isEmpty {
            let textsAlone = DiagramScene(size: scene.size, font: scene.font, items: scene.texts.map { text in .text(text) },
                                          seriesColors: scene.seriesColors)
            // Every scene at one pixel a point in the light palette, one in four also at two in the dark one.
            let paintings = [(DiagramScenePaletteSamples.light, CGFloat(1))] + (sceneIndex % 4 == 0 ? [(DiagramScenePaletteSamples.dark, CGFloat(2))] : [])
            for (palette, scale) in paintings {
                let before = try XCTUnwrap(DiagramScenePixels(size: scene.size, scale: scale) { context in
                    Self.drawTextsAsBefore(of: scene, in: context, palette: palette)
                })
                let now = try XCTUnwrap(DiagramScenePixels(size: scene.size, scale: scale) { context in
                    DiagramSceneRenderer.draw(textsAlone, in: context, palette: palette)
                })
                XCTAssertEqual(now.differingPixelCount(from: before), 0, "\(name) at \(scale)x")
            }
            comparedTextCount += scene.texts.count
            emphasisCount += scene.texts.filter { text in text.block.record.hasEmphasis }.count
            rotatedCount += scene.texts.filter { text in text.rotation != nil }.count
            outlinedCount += scene.texts.filter { text in text.outline != nil }.count
        }
        XCTAssertGreaterThan(comparedTextCount, 5_000)
        XCTAssertGreaterThan(emphasisCount, 0, "texts with runs in their emphasis are compared")
        XCTAssertGreaterThan(rotatedCount, 0, "turned texts are compared")
        XCTAssertGreaterThan(outlinedCount, 0, "outlined texts are compared")
    }

    /// Texts beyond ASCII, with escaped and forbidden characters, with emphasis and on several lines, are painted as before.
    func testRandomTextsArePaintedAsTheStringDrawingPaintedThem() throws {
        var samples = DiagramSVGSceneSamples(seed: 0x7E47)
        let measurer = DiagramSceneSamples.typography.measurer(size: 13)
        let font = DiagramFont(postScriptName: nil, size: 13)
        for round in 0..<60 {
            var texts: [DiagramSceneItem] = []
            for index in 0..<4 {
                let source = index % 2 == 0 ? "**\(samples.text())** _\(samples.text())_ `\(samples.text())`<br>\(samples.text())" : samples.text()
                var block = DiagramTextBlock(label: DiagramLabelDecoder.label(from: source, form: .markdown), measurer: measurer, maximumWidth: 120)
                block.center = CGPoint(x: 80, y: 30 + CGFloat(index) * 40)
                texts.append(.text(DiagramSceneText(block: block, paint: .foreground, isBold: round % 3 == 0, isItalic: round % 5 == 0,
                                                    rotation: index == 3 ? 0.4 : nil, part: .label)))
            }
            let scene = DiagramScene(size: CGSize(width: 200, height: 200), font: font, items: texts)
            let before = try XCTUnwrap(DiagramScenePixels(size: scene.size, scale: 2) { context in
                Self.drawTextsAsBefore(of: scene, in: context, palette: DiagramScenePaletteSamples.light)
            })
            let now = try XCTUnwrap(DiagramScenePixels(size: scene.size, scale: 2) { context in
                DiagramSceneRenderer.draw(scene, in: context, palette: DiagramScenePaletteSamples.light)
            })
            XCTAssertEqual(now.differingPixelCount(from: before), 0, "round \(round)")
        }
    }

    /// Each block's runs read as bytes are its runs as Strings: the same text, emphasis and width, in order.
    func testABlocksRunsReadAsBytesAreItsRuns() throws {
        var runCount = 0
        for (_, scene) in try Self.corpusScenes() {
            for text in scene.texts where text.block.record.hasEmphasis {
                for line in 0..<text.block.lineCount {
                    var read: [DiagramTextRun] = []
                    text.block.forEachRun(ofLine: line) { bytes, style, width in
                        read.append(DiagramTextRun(text: String(decoding: bytes, as: UTF8.self), style: style, width: width))
                    }
                    XCTAssertEqual(read, text.block.runs(ofLine: line))
                    XCTAssertEqual(text.block.runCount(ofLine: line), read.count)
                    runCount += read.count
                }
            }
        }
        XCTAssertGreaterThan(runCount, 0)
    }

    /// Text of random bytes and of every byte, escaped in one pass, is what the frozen writer escaped byte by byte.
    func testTextEscapedInOnePassIsWhatTheWriterEscapedByteByByte() {
        var generator = DiagramPathLaneSamples(seed: 0xE5CA)
        var texts = (0..<256).map { byte in String(decoding: [UInt8(byte), 0x41], as: UTF8.self) }
        texts += ["", "plain", "\u{FFFE}\u{FFFF}\u{FFFD}", "&<>\"'", String(repeating: "a&", count: 300), "\u{EF}"]
        for _ in 0..<5_000 {
            let length = Int(generator.next() % 80)
            let bytes = (0..<length).map { _ -> UInt8 in
                let pick = generator.next() % 6
                return pick == 0 ? UInt8(truncatingIfNeeded: generator.next()) : (pick == 1 ? [0xEF, 0xBF, 0xBE, 0x26, 0x3C, 0x7F, 0x09][Int(generator.next() % 7)]
                                                                                        : UInt8(ascii: "a") + UInt8(generator.next() % 26))
            }
            texts.append(String(decoding: bytes, as: UTF8.self))
        }
        for text in texts {
            var written = DiagramSVGBuffer()
            written.appendEscaped(text)
            var reference = ReferenceSVGBuffer()
            reference.appendEscaped(text)
            XCTAssertEqual(written.text, reference.text, text.debugDescription)
        }
    }

    /// A part's ordinal, the tag it is stored as, is its place among all parts, and its class is `pele-` and its raw value.
    func testEveryPartsOrdinalIsItsPlaceAndItsClassIsItsName() {
        XCTAssertEqual(MemoryLayout<DiagramScenePart>.size, 1)
        for (index, part) in DiagramScenePart.allCases.enumerated() {
            XCTAssertEqual(part.ordinal, index, "\(part)")
            XCTAssertEqual(DiagramSVGClassNames.shared.name(of: part), "pele-\(part.rawValue)")
        }
    }
}
