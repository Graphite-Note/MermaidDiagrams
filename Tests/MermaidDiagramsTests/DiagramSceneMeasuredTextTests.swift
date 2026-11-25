/**
 * File: DiagramSceneMeasuredTextTests.swift
 * -----------------------------------------
 * Layer: Tests
 * Description: Checks that a scene built from texts measured from their source's bytes is the scene built from the
 *              blocks of their decoded labels, to the byte: every text every corpus decodes and random texts, in several
 *              faces and widths, drawn plain, bold, italic, monospaced, turned and outlined, compared by their scene
 *              lines, runs, records and SVG; texts measured from Strings and from labels; scenes built on many threads
 *              at once; and texts larger than a thread's text storage.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import CoreGraphics
import Foundation
@testable import MermaidDiagrams
import XCTest

final class DiagramSceneMeasuredTextTests: XCTestCase {
    /// 16 and 12 points sum exactly, 12.8 does not.
    private static let measurers = [CoreTextDiagramTextMeasurer(font: DiagramFont(postScriptName: nil, size: 16)),
                                    CoreTextDiagramTextMeasurer(font: DiagramFont(postScriptName: nil, size: 12)),
                                    CoreTextDiagramTextMeasurer(font: DiagramFont(postScriptName: nil, size: 12.8))]
    private static let widths: [CGFloat] = [.infinity, 120, 40]

    /// Every text the preparation of every corpus decodes, drawn from its bytes and from its block, in three faces at three
    /// widths: the same scene texts, records and SVG.
    func testEveryTextOfEveryCorpusDrawsAsItsBlock() throws {
        let texts = try DiagramFlatTextMeasuringTests.corpusTexts()
        XCTAssertGreaterThan(texts.count, 2_500)
        let sources = MeasuredTextSources(texts)
        var counts = SceneComparison()
        for measurer in Self.measurers {
            for width in Self.widths { counts.add(sources.compareScenes(measurer: measurer, maximumWidth: width)) }
        }
        XCTAssertEqual(counts.differences, [])
        XCTAssertGreaterThan(counts.texts, 20_000)
        XCTAssertGreaterThan(counts.severalLines, 2_000, "texts of several lines")
        XCTAssertGreaterThan(counts.withEmphasis, 100, "texts with emphasis")
    }

    /// Random texts of words, breaks, markup, entities and bytes past ASCII in every form, drawn both ways alike.
    func testRandomTextsDrawAsTheirBlocks() {
        let parts = ["word", "a", "Wrapping", " ", "  ", "\t", "\n", "\\n", "<br>", "<BR/>", "<b>", "</b>", "<i>x</i>", "**", "*", "_", "&amp;",
                     "#35;", "fa:fa-car", "é", "日本", "«", "-", "LongUnbrokenWordOfManyLetters", "`code`", "~~"]
        let forms: [DiagramLabelDecoder.Form] = [.plain, .literal, .markdown]
        var state: UInt64 = 0x5CE7E
        func next(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(bound))
        }
        var texts: [(String, DiagramLabelDecoder.Form)] = []
        for _ in 0..<2_000 { texts.append(((0..<next(12)).map { _ in parts[next(parts.count)] }.joined(), forms[next(forms.count)])) }
        let sources = MeasuredTextSources(texts)
        var counts = SceneComparison()
        for measurer in Self.measurers {
            for width: CGFloat in [.infinity, 77.5, 30, 0] { counts.add(sources.compareScenes(measurer: measurer, maximumWidth: width)) }
        }
        XCTAssertEqual(counts.differences, [])
        XCTAssertGreaterThan(counts.withEmphasis, 1_000)
    }

    /// A text measured from a String (its lines copied, since the String's bytes go) and a label measured as its block
    /// draw as the blocks of the same texts, with no source at all.
    func testTextsMeasuredFromStringsAndLabelsDrawAsTheirBlocks() {
        let measurer = Self.measurers[0]
        let flat = DiagramFlatMeasurer(measurer)
        var lines = DiagramMeasuredLines()
        var blocks: [DiagramTextBlock] = []
        var measured: [DiagramMeasuredText] = []
        for (index, text) in ["one", "two words that wrap", "a<br>b", "**bold** and _italic_", "x &amp; y", "日本語"].enumerated() {
            let label = DiagramLabelDecoder.label(from: text, form: index.isMultiple(of: 2) ? .plain : .markdown)
            let center = CGPoint(x: 10 * index, y: 30 * index)
            blocks.append(DiagramTextBlock(label: label, measurer: measurer, maximumWidth: 60).translated(by: CGVector(dx: center.x, dy: center.y)))
            measured.append(DiagramFlatTextMeasuring.measure(written: text, form: index.isMultiple(of: 2) ? .plain : .markdown, measurer: flat,
                                                             maximumWidth: 60, into: &lines).centered(at: center))
            blocks.append(blocks[blocks.count - 1])
            measured.append(DiagramFlatTextMeasuring.measure(label, measurer: flat, maximumWidth: 60, into: &lines).centered(at: center))
        }
        for index in 0..<lines.count { XCTAssertGreaterThanOrEqual(lines[index].start, DiagramMeasuredLines.derivedOffset, "line \(index) derived") }
        var fromBlocks = DiagramSceneBuilder()
        fromBlocks.texts(blocks, .foreground, part: .label)
        var fromMeasured = DiagramSceneBuilder()
        fromMeasured.texts(measured, of: lines, .foreground, part: .label)
        XCTAssertEqual(SceneComparison.difference(fromMeasured.scene(size: .zero, font: SceneComparison.font),
                                                  fromBlocks.scene(size: .zero, font: SceneComparison.font)), nil)
    }

    /// Scenes built from measured texts on eight threads at once, each thread writing into its own text storage, are the
    /// scenes built on one.
    func testScenesBuiltOnManyThreadsAtOnceAreAlike() throws {
        let sources = MeasuredTextSources(Array(try DiagramFlatTextMeasuringTests.corpusTexts().prefix(1_200)))
        let found = ThreadDifferences()
        DispatchQueue.concurrentPerform(iterations: 8) { thread in
            let comparison = sources.compareScenes(measurer: Self.measurers[thread % Self.measurers.count], maximumWidth: thread.isMultiple(of: 2) ? 80 : .infinity)
            found.add(comparison.differences)
        }
        XCTAssertEqual(found.differences, [])
    }

    /// A text larger than a quarter of a thread's storage gets a storage of its own, many texts fill several, and a
    /// line of 40,000 bytes is copied once: each draws as its block.
    func testLargeTextsAndManyTextsDrawAsTheirBlocks() {
        let long = String(repeating: "word ", count: 8_000)
        let manyLines = String(repeating: "line<br>", count: 2_000)
        var texts: [(String, DiagramLabelDecoder.Form)] = [(long, .plain), (manyLines, .plain), (String(repeating: "**b** ", count: 900), .markdown)]
        for index in 0..<3_000 { texts.append(("text number \(index) of many", .plain)) }
        let sources = MeasuredTextSources(texts)
        for width: CGFloat in [.infinity, 200] {
            XCTAssertEqual(sources.compareScenes(measurer: Self.measurers[0], maximumWidth: width).differences, [], "at \(width)")
        }
    }
}

/// Texts in one byte buffer, as a model holds them, with their forms.
struct MeasuredTextSources: Sendable {
    private(set) var bytes: [UInt8] = []
    private(set) var texts: [(text: String, form: DiagramLabelDecoder.Form, range: MermaidTextRange)] = []

    init(_ written: [(String, DiagramLabelDecoder.Form)]) {
        for (text, form) in written {
            // Bytes around each text that a measuring reading past its range would take in.
            bytes += Array("<br> x ".utf8)
            let start = bytes.count
            bytes += Array(text.utf8)
            texts.append((text, form, MermaidTextRange(start: start, end: bytes.count)))
            bytes += Array(" x\\n".utf8)
        }
    }

    /// Each text drawn into one scene from its bytes and into another from its block, in batches, with a look that
    /// changes from text to text; the scenes compared.
    func compareScenes<Measurer: DiagramTextMeasuring>(measurer: Measurer, maximumWidth: CGFloat) -> SceneComparison {
        let flat = DiagramFlatMeasurer(measurer)
        var comparison = SceneComparison()
        bytes.withUnsafeBufferPointer { source in
            var start = 0
            while start < texts.count {
                let batch = texts[start..<min(start + 200, texts.count)]
                var lines = DiagramMeasuredLines()
                var fromBlocks = DiagramSceneBuilder()
                var fromMeasured = DiagramSceneBuilder()
                for (offset, (text, form, range)) in batch.enumerated() {
                    let look = TextLook(offset + start)
                    let center = CGPoint(x: CGFloat(offset % 7) * 31.5, y: CGFloat(offset) * 1.25)
                    let label = DiagramLabelDecoder.label(from: text, form: form)
                    let block = DiagramTextBlock(label: label, measurer: measurer, maximumWidth: maximumWidth).translated(by: CGVector(dx: center.x, dy: center.y))
                    let measured = DiagramFlatTextMeasuring.measure(source, range, form: form, measurer: flat, maximumWidth: maximumWidth, into: &lines)
                        .centered(at: center)
                    comparison.count(block)
                    look.add(block, to: &fromBlocks)
                    look.add(measured, of: lines, source: source, to: &fromMeasured)
                }
                let difference = SceneComparison.difference(fromMeasured.scene(size: CGSize(width: 300, height: 300), font: SceneComparison.font),
                                                            fromBlocks.scene(size: CGSize(width: 300, height: 300), font: SceneComparison.font))
                if let difference { comparison.note("\(difference) in the batch from \(start) at \(maximumWidth) in \(measurer.fontSize)") }
                start += batch.count
            }
        }
        return comparison
    }
}

/// How a text is drawn, changed from one text to the next so that every option of the builder is taken.
private struct TextLook {
    let isBold: Bool
    let isItalic: Bool
    let isMonospaced: Bool
    let rotation: CGFloat?
    let outline: DiagramTextOutline?
    let part: DiagramScenePart
    let isTitle: Bool

    init(_ index: Int) {
        isBold = index % 3 == 1
        isItalic = index % 5 == 2
        isMonospaced = index % 7 == 3
        rotation = index % 4 == 1 ? -.pi / 2 : nil
        outline = index % 6 == 5 ? DiagramTextOutline(paint: .background, lineWidth: 3) : nil
        part = index.isMultiple(of: 2) ? .label : .edgeLabel
        isTitle = index % 11 == 10
    }

    func add(_ block: DiagramTextBlock, to builder: inout DiagramSceneBuilder) {
        guard !isTitle else { return builder.title(block) }
        builder.text(block, .foreground, isBold: isBold, isItalic: isItalic, isMonospaced: isMonospaced, rotation: rotation, outline: outline, part: part)
    }

    func add(_ text: DiagramMeasuredText, of lines: DiagramMeasuredLines, source: UnsafeBufferPointer<UInt8>, to builder: inout DiagramSceneBuilder) {
        guard !isTitle else { return builder.title(text, of: lines, source: source) }
        builder.text(text, of: lines, source: source, .foreground, isBold: isBold, isItalic: isItalic, isMonospaced: isMonospaced, rotation: rotation,
                     outline: outline, part: part)
    }
}

/// What comparing scenes found: how many texts, of which kinds, and the first differences.
struct SceneComparison {
    static let font = DiagramFont(postScriptName: nil, size: 16)

    var texts = 0
    var severalLines = 0
    var withEmphasis = 0
    private(set) var differences: [String] = []

    mutating func count(_ block: DiagramTextBlock) {
        texts += 1
        if block.lineCount > 1 { severalLines += 1 }
        if block.record.hasEmphasis { withEmphasis += 1 }
    }

    mutating func note(_ difference: String) {
        if differences.count < 20 { differences.append(difference) }
    }

    mutating func add(_ other: SceneComparison) {
        texts += other.texts
        severalLines += other.severalLines
        withEmphasis += other.withEmphasis
        for difference in other.differences { note(difference) }
    }

    /// Why `scene` is not `expected` in its texts, to the byte, or nil when it is: the texts' blocks, records, lines, runs
    /// and looks, and the whole SVG.
    static func difference(_ scene: DiagramScene, _ expected: DiagramScene) -> String? {
        guard scene.texts.count == expected.texts.count else { return "\(scene.texts.count) texts against \(expected.texts.count)" }
        for (index, (text, other)) in zip(scene.texts, expected.texts).enumerated() {
            guard text.block == other.block else { return "text \(index): block \(text.block.lines) against \(other.block.lines)" }
            guard text.block.record.isOneLine == other.block.record.isOneLine, text.block.record.hasEmphasis == other.block.record.hasEmphasis,
                  text.block.size == other.block.size else { return "text \(index): record \(text.block.record) against \(other.block.record)" }
            guard text.lines == other.lines, text.styledRuns == other.styledRuns else { return "text \(index): lines \(text.lines) against \(other.lines)" }
            guard text.isBold == other.isBold, text.isItalic == other.isItalic, text.isMonospaced == other.isMonospaced, text.rotation == other.rotation,
                  text.outline == other.outline, text.part == other.part, text.paint == other.paint else { return "text \(index): look" }
        }
        let writer = DiagramSVGWriter()
        guard writer.document(of: scene, diagramType: "test") == writer.document(of: expected, diagramType: "test") else { return "SVG" }
        return nil
    }
}

/// The differences threads found, gathered under a lock.
private final class ThreadDifferences: @unchecked Sendable {
    private let lock = NSLock()
    private var found: [String] = []

    func add(_ differences: [String]) {
        lock.lock()
        found += differences
        lock.unlock()
    }

    var differences: [String] {
        lock.lock()
        defer { lock.unlock() }
        return found
    }
}
