/**
 * File: DiagramFlatTextMeasuringTests.swift
 * -----------------------------------------
 * Layer: Tests
 * Description: Checks the flat text measuring against the label decoder and the text block it stands in for, to the
 *              bit: every text every corpus decodes, at several widths and in several faces, with the fast path taken
 *              and with the full path forced; random texts of markup, breaks and white space in exactly and inexactly
 *              summable faces; character breaking; constant texts; measuring on many threads at once; and long texts.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 26/11/2026
 */

import CoreGraphics
import Foundation
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark
import XCTest

final class DiagramFlatTextMeasuringTests: XCTestCase {
    private static let widths: [CGFloat] = [.infinity, 150, 60, 20]
    /// 16, 14 and 12 points sum exactly; 12.8 and 17.3 do not.
    private static let measurers = [CoreTextDiagramTextMeasurer(font: DiagramFont(postScriptName: nil, size: 16)),
                                    CoreTextDiagramTextMeasurer(font: DiagramFont(postScriptName: nil, size: 16), isBold: true),
                                    CoreTextDiagramTextMeasurer(font: DiagramFont(postScriptName: nil, size: 12)),
                                    CoreTextDiagramTextMeasurer(font: DiagramFont(postScriptName: nil, size: 12.8)),
                                    CoreTextDiagramTextMeasurer(font: DiagramFont(postScriptName: nil, size: 17.3))]

    /// Every text the preparation of every corpus decodes, measured flat from one byte buffer in five faces at four
    /// widths, wrapped, broken between characters and with the full path forced: each the block of its label to the bit.
    func testEveryTextOfEveryCorpusMeasuresAsItsBlock() throws {
        let texts = try Self.corpusTexts()
        XCTAssertGreaterThan(texts.count, 2_500, "distinct texts decoded")
        var buffer = TextBuffer()
        for (text, form) in texts { buffer.append(text, form: form) }
        var checked = Counts()
        for measurer in Self.measurers {
            for maximumWidth in Self.widths {
                checked.add(buffer.check(measurer: measurer, maximumWidth: maximumWidth))
            }
        }
        XCTAssertEqual(checked.differences, [], "texts measured unlike their blocks")
        XCTAssertGreaterThan(checked.measured, 50_000)
        XCTAssertGreaterThan(checked.fastPath, checked.measured / 2, "most corpus texts take the fast path")
        XCTAssertGreaterThan(checked.wrappedOnFastPath, 2_000, "texts wrapped on the fast path")
        XCTAssertGreaterThan(checked.withEmphasis, 100, "texts with emphasis copied with their runs")
    }

    /// Random texts of words, spaces, tabs, line breaks of every spelling, markup bytes, entities, tags, icons and bytes
    /// past ASCII, in every form, at many widths, in faces that sum exactly and faces that do not.
    func testRandomTextsMeasureAsTheirBlocks() {
        let parts = ["word", "a", "Wrapping", "x1", " ", "  ", "   ", "\t", "\n", "\r", "\\n", "\\N", "\\", "<br>", "<BR/>", "<br  />", "<br", "<b>", "</b>",
                     "<i>x</i>", "#", "#35;", "#quot;", "&", "&amp;", "&lt;", "*", "**", "_", "__", ":", ":fa-", "fa:fa-car", "fab:fa-x", ";", "\u{0B}",
                     "\u{0C}", "é", "\u{A0}", "«", "»", "日本", "-", ".", "(", ")", "LongUnbrokenWordOfManyLetters"]
        let forms: [DiagramLabelDecoder.Form] = [.plain, .literal, .markdown]
        let widths: [CGFloat] = [0, 1, 12, 33.5, 47, 60, 99.25, 120, 200, .infinity]
        var generator = Generator(state: 0x5EED_F1A7)
        var buffer = TextBuffer()
        // Every other text is drawn from the parts the fast path takes, so that it wraps often.
        let plainParts = ["word", "a", "Wrapping", "x1", " ", "  ", "   ", "\n", "\\n", "<br>", "<BR/>", "-", ".", "(", ")", ":", "#", "LongUnbrokenWordOfManyLetters"]
        for index in 0..<3_000 {
            let drawn = index.isMultiple(of: 2) ? parts : plainParts
            let text = (0..<generator.next(below: 14)).map { _ in drawn[generator.next(below: drawn.count)] }.joined()
            buffer.append(text, form: forms[generator.next(below: forms.count)])
        }
        var checked = Counts()
        for measurer in Self.measurers {
            for maximumWidth in widths { checked.add(buffer.check(measurer: measurer, maximumWidth: maximumWidth)) }
        }
        XCTAssertEqual(checked.differences, [], "texts measured unlike their blocks")
        XCTAssertGreaterThan(checked.fastPath, 10_000)
        XCTAssertGreaterThan(checked.wrappedOnFastPath, 3_000)
    }

    /// A measurer without advances (fixed widths) measures every text on the full path, alike.
    func testAMeasurerWithoutAdvancesTakesTheFullPathAlike() {
        var buffer = TextBuffer()
        for text in ["", "  ", "one", "two words here", "a<br>b", "x & y", "<b>bold</b>"] { buffer.append(text, form: .plain) }
        let counts = buffer.check(measurer: UniformWidthTextMeasurer(characterWidth: 7.3), maximumWidth: 30)
        XCTAssertEqual(counts.differences, [])
        XCTAssertEqual(counts.fastPath, 2, "only the texts of no line need no advances")
    }

    /// The constant texts' kept widths are their blocks' widths, in faces registered and not, and a constant that must
    /// wrap is wrapped as its block.
    func testConstantTextsMeasureAsTheirBlocks() {
        let names = ["«include»", "«extend»", "«person»", "«external system db»", "[Container]", "Requirement", "two words"]
        let constants = DiagramConstantTexts(names)
        for measurer in Self.measurers {
            let widths = constants.widths(for: measurer)
            XCTAssertEqual(constants.widths(for: measurer).widths, widths.widths, "kept once and given again")
            var lines = DiagramMeasuredLines()
            for (index, name) in names.enumerated() {
                for maximumWidth: CGFloat in [.infinity, 40] {
                    let block = DiagramTextBlock(label: DiagramLabelDecoder.label(from: name, form: .plain), measurer: measurer, maximumWidth: maximumWidth)
                    let measured = widths.measure(index, measurer: DiagramFlatMeasurer(measurer), maximumWidth: maximumWidth, into: &lines)
                    XCTAssertNil(Self.difference(measured, lines, source: [], block), "\(name) at \(maximumWidth)")
                }
            }
        }
        let uniform = UniformWidthTextMeasurer(characterWidth: 7.3)
        XCTAssertEqual(constants.widths(for: uniform).width(of: 0), uniform.width(of: names[0]))
    }

    /// Texts measured on eight threads at once, each into its own lines, measure as on one thread.
    func testTextsMeasuredOnManyThreadsAtOnceMeasureAlike() throws {
        var buffer = TextBuffer()
        for (text, form) in try Self.corpusTexts().prefix(1_500) { buffer.append(text, form: form) }
        let shared = buffer
        let results = ThreadResults()
        DispatchQueue.concurrentPerform(iterations: 8) { thread in
            let counts = shared.check(measurer: Self.measurers[thread % Self.measurers.count], maximumWidth: thread.isMultiple(of: 2) ? 60 : .infinity)
            results.add(counts.differences)
        }
        XCTAssertEqual(results.differences, [])
    }

    /// A long line of words, many breaks, a long word and a line past the exact wrap's length measure as their blocks,
    /// in time that grows with their length.
    func testLongTextsMeasureAsTheirBlocksInTimeThatGrowsWithTheirLength() {
        let texts: [(String, (Int) -> String)] = [
            ("words", { count in String(repeating: "word ", count: count) }),
            ("lines", { count in String(repeating: "line<br>", count: count) }),
            ("written breaks", { count in String(repeating: "a b\\n", count: count) }),
            ("one word", { count in String(repeating: "x", count: count * 5) }),
        ]
        let measurer = Self.measurers[0]
        for (name, text) in texts {
            var buffer = TextBuffer()
            buffer.append(text(20_000), form: .plain)
            XCTAssertEqual(buffer.check(measurer: measurer, maximumWidth: 120).differences, [], name)
            func seconds(_ count: Int) -> Double {
                var lines = DiagramMeasuredLines()
                let bytes = Array(text(count).utf8)
                let started = Date()
                bytes.withUnsafeBufferPointer { bytes in
                    _ = DiagramFlatTextMeasuring.measure(bytes, MermaidTextRange(start: 0, end: bytes.count), form: .plain,
                                                         measurer: DiagramFlatMeasurer(measurer), maximumWidth: 120, into: &lines)
                }
                return Date().timeIntervalSince(started)
            }
            _ = seconds(200)
            let small = (0..<3).map { _ in seconds(1_000) }.min() ?? 0
            let large = (0..<3).map { _ in seconds(10_000) }.min() ?? 0
            XCTAssertLessThan(large, max(small, 0.000_5) * 40, "\(name): \(small) s for 1,000, \(large) s for 10,000")
        }
        var buffer = TextBuffer()
        buffer.append(String(repeating: "ab ", count: DiagramFlatTextWrapping.longestWrappedByteCount / 3 + 1), form: .plain)
        let counts = buffer.check(measurer: measurer, maximumWidth: 1_000)
        XCTAssertEqual(counts.differences, [])
        XCTAssertEqual(counts.fastPath, 0, "a line too long to wrap exactly takes the full path")
    }

    /// Every text and form the preparation of every corpus decodes (regular scenes and the narrow ones), once each.
    static func corpusTexts() throws -> [(String, DiagramLabelDecoder.Form)] {
        let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))
        let decoded = DecodedTexts()
        DiagramLabelDecodingObservation.observer = { text, form, _ in decoded.add(text, form) }
        defer { DiagramLabelDecodingObservation.observer = nil }
        for (_, sources) in try OutputDigest.corpora() {
            for source in sources {
                _ = OutputDigest.Outcome(source: source, typography: typography, narrowColumnWidths: OutputDigest.narrowColumnWidths)
                addTextsReadAsWritten(of: source, to: decoded)
            }
        }
        return decoded.texts
    }

    /// The texts state and class diagrams keep as ranges of their source, which the decoder reads as written and their
    /// readers therefore no longer decode: still among the texts measured both ways, as when they were decoded.
    private static func addTextsReadAsWritten(of source: String, to decoded: DecodedTexts) {
        var texts: [MermaidTextRange] = []
        let bytes: MermaidSourceText
        switch try? MermaidDiagramReader.read(source, limits: .standard) {
        case .stateDiagram(let diagram)?:
            let model = diagram.model
            bytes = model.text
            texts = (model.descriptions + model.transitions.map(\.label) + model.notes.map(\.text)).filter(\.isSourceRange).map(\.range)
        case .classDiagram(let diagram)?:
            let model = diagram.model
            bytes = model.text
            texts = (model.classes.map(\.label) + model.relations.map(\.label) + model.notes.map(\.text)).filter(\.isSourceRange).map(\.range)
        default: return
        }
        for range in texts { decoded.add(bytes.string(range), .plain) }
    }

    /// Why `measured`, in `lines` over `source`, is not `block` to the bit, or nil when it is.
    static func difference(_ measured: DiagramMeasuredText, _ lines: DiagramMeasuredLines, source: [UInt8], _ block: DiagramTextBlock) -> String? {
        guard Int(measured.lineCount) == block.lineCount else { return "\(measured.lineCount) lines against \(block.lineCount)" }
        guard measured.width.bitPattern == block.size.width.bitPattern, measured.height.bitPattern == block.size.height.bitPattern else {
            return "size \(measured.size) against \(block.size)"
        }
        guard measured.lineHeight.bitPattern == block.lineHeight.bitPattern, measured.fontSize.bitPattern == block.fontSize.bitPattern else {
            return "line height \(measured.lineHeight) against \(block.lineHeight)"
        }
        guard measured.hasEmphasis == (block.lineRuns != nil) else { return "emphasis \(measured.hasEmphasis)" }
        return source.withUnsafeBufferPointer { source in
            for (line, index) in zip(measured.lineIndices, 0..<block.lineCount) {
                let bytes = lines.withUTF8(ofLine: line, source: source) { bytes in Array(bytes) }
                guard bytes == block.withUTF8(ofLine: index, { bytes in Array(bytes) }) else { return "line \(index) \(String(decoding: bytes, as: UTF8.self))" }
                guard lines[line].width.bitPattern == block.lineWidth(at: index).bitPattern else { return "line \(index) width \(lines[line].width)" }
                if let runs = block.lineRuns, lines.runs(ofLine: line) != runs[index] { return "line \(index) runs \(lines.runs(ofLine: line))" }
            }
            return nil
        }
    }
}

/// Texts in one byte buffer, as a model holds them, with their forms.
private struct TextBuffer: Sendable {
    var bytes: [UInt8] = []
    var texts: [(text: String, form: DiagramLabelDecoder.Form, range: MermaidTextRange)] = []

    mutating func append(_ text: String, form: DiagramLabelDecoder.Form) {
        // Bytes around each text that a measuring reading past its range would take in.
        bytes += Array("<br> x ".utf8)
        let start = bytes.count
        bytes += Array(text.utf8)
        texts.append((text, form, MermaidTextRange(start: start, end: bytes.count)))
        bytes += Array(" x\\n".utf8)
    }

    /// Each text measured flat, wrapped, broken between characters and forced onto the full path, compared with its block.
    func check<Measurer: DiagramTextMeasuring>(measurer: Measurer, maximumWidth: CGFloat) -> Counts {
        let flat = DiagramFlatMeasurer(measurer)
        var counts = Counts()
        var lines = DiagramMeasuredLines()
        bytes.withUnsafeBufferPointer { buffer in
            for (text, form, range) in texts {
                let label = DiagramLabelDecoder.label(from: text, form: form)
                let block = DiagramTextBlock(label: label, measurer: measurer, maximumWidth: maximumWidth)
                let broken = DiagramTextBlock(label: label, measurer: measurer, wrappingWidth: maximumWidth, breakingWidth: min(maximumWidth, 40))
                if lines.count > 10_000 { lines.removeAll() }
                let fast = DiagramFlatTextMeasuring.measuredOnFastPath(buffer, range, form: form, measurer: flat, maximumWidth: maximumWidth, into: &lines)
                if let fast {
                    counts.fastPath += 1
                    if fast.lineCount > 1 { counts.wrappedOnFastPath += 1 }
                }
                let measured = DiagramFlatTextMeasuring.measure(buffer, range, form: form, measurer: flat, maximumWidth: maximumWidth, into: &lines)
                let full = DiagramFlatTextMeasuring.measuredOnFullPath(buffer, range, form: form, measurer: flat, maximumWidth: maximumWidth, into: &lines)
                let breaking = DiagramFlatTextMeasuring.measureBreakingCharacters(buffer, range, form: form, measurer: flat, wrappingWidth: maximumWidth,
                                                                                  breakingWidth: min(maximumWidth, 40), into: &lines)
                if block.lineRuns != nil { counts.withEmphasis += 1 }
                counts.measured += 1
                for (name, result, expected) in [("measured", measured, block), ("full path", full, block), ("broken", breaking, broken)] {
                    guard let difference = DiagramFlatTextMeasuringTests.difference(result, lines, source: bytes, expected) else { continue }
                    if counts.differences.count < 20 { counts.differences.append("\(name) \(text.debugDescription) \(form) at \(maximumWidth) in \(measurer.fontSize): \(difference)") }
                }
                if let fast, let difference = DiagramFlatTextMeasuringTests.difference(fast, lines, source: bytes, block), counts.differences.count < 20 {
                    counts.differences.append("fast path \(text.debugDescription) at \(maximumWidth): \(difference)")
                }
            }
        }
        return counts
    }
}

private struct Counts {
    var measured = 0
    var fastPath = 0
    var wrappedOnFastPath = 0
    var withEmphasis = 0
    var differences: [String] = []

    mutating func add(_ other: Counts) {
        measured += other.measured
        fastPath += other.fastPath
        wrappedOnFastPath += other.wrappedOnFastPath
        withEmphasis += other.withEmphasis
        differences += other.differences.prefix(max(0, 20 - differences.count))
    }
}

private struct Generator {
    var state: UInt64

    mutating func next(below bound: Int) -> Int {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Int((state >> 33) % UInt64(bound))
    }
}

/// The texts decoded while the corpora are prepared, each text and form once, in the order first met.
private final class DecodedTexts: @unchecked Sendable {
    private let lock = NSLock()
    private var seen: Set<String> = []
    private(set) var texts: [(String, DiagramLabelDecoder.Form)] = []

    func add(_ text: String, _ form: DiagramLabelDecoder.Form) {
        lock.lock()
        defer { lock.unlock() }
        if seen.insert("\(form)|" + text).inserted { texts.append((text, form)) }
    }
}

/// The differences threads found, gathered under a lock.
private final class ThreadResults: @unchecked Sendable {
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
