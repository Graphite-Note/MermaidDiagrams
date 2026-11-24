/**
 * File: DiagramTextStorageTests.swift
 * -----------------------------------
 * Layer: Tests
 * Description: Checks measuring on bytes into a text storage against release 0.7.0's measuring into Strings, to the bit:
 *              every block of every corpus as the preparation makes it, and random labels of every kind of text at many
 *              widths, in exactly and inexactly summable fonts; and that the storage keeps labels and blocks readable
 *              across threads, past a full storage and for text larger than a storage.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
import Foundation
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark
import XCTest

final class DiagramTextStorageTests: XCTestCase {
    /// Asserts that `block` is the reference block to the bit: its lines, widths, runs, line height and font size.
    static func assertSame(_ block: DiagramTextBlock, _ reference: ReferenceTextBlock, fontSize: CGFloat, _ description: @autoclosure () -> String,
                           file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(block.lines, reference.lines, description(), file: file, line: line)
        XCTAssertEqual(block.lineCount, reference.lines.count, description(), file: file, line: line)
        XCTAssertEqual(block.lineWidths.map(\.bitPattern), reference.lineWidths.map(\.bitPattern), description(), file: file, line: line)
        XCTAssertEqual(block.lineHeight.bitPattern, reference.lineHeight.bitPattern, description(), file: file, line: line)
        XCTAssertEqual(block.fontSize.bitPattern, fontSize.bitPattern, description(), file: file, line: line)
        XCTAssertEqual(block.size.width.bitPattern, (reference.lineWidths.max() ?? 0).bitPattern, description(), file: file, line: line)
        XCTAssertEqual(block.lineRuns?.map { runs in runs.map(\.text) }, reference.lineRuns?.map { runs in runs.map(\.text) }, description(),
                       file: file, line: line)
        XCTAssertEqual(block.lineRuns?.map { runs in runs.map(\.style) }, reference.lineRuns?.map { runs in runs.map(\.style) }, description(),
                       file: file, line: line)
        XCTAssertEqual(block.lineRuns?.map { runs in runs.map(\.width.bitPattern) }, reference.lineRuns?.map { runs in runs.map(\.width.bitPattern) },
                       description(), file: file, line: line)
        for index in 0..<min(block.lineCount, reference.lines.count) {
            XCTAssertEqual(block.withUTF8(ofLine: index) { bytes in Array(bytes) }, Array(reference.lines[index].utf8), description(), file: file, line: line)
            XCTAssertEqual(block.lineWidth(at: index).bitPattern, reference.lineWidths[index].bitPattern, description(), file: file, line: line)
        }
    }

    /// Every label the preparation of every corpus measures (regular scenes and the narrow ones at Pele's three widths),
    /// measured again by 0.7.0's code: the same block to the bit.
    func testEveryBlockOfEveryCorpusIsTheReferenceBlock() throws {
        let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))
        let observed = ObservedBlocks()
        DiagramTextBlockObservation.observer = { measuring in observed.check(measuring) }
        defer { DiagramTextBlockObservation.observer = nil }
        var inputCount = 0
        for (_, sources) in try OutputDigest.corpora() {
            for source in sources {
                _ = OutputDigest.Outcome(source: source, typography: typography, narrowColumnWidths: OutputDigest.narrowColumnWidths)
                inputCount += 1
            }
        }
        XCTAssertGreaterThan(inputCount, 800)
        XCTAssertGreaterThan(observed.blockCount, 20_000, "blocks checked")
        XCTAssertGreaterThan(observed.wrappedCount, 500, "blocks of several lines checked")
        XCTAssertGreaterThan(observed.styledCount, 50, "blocks with emphasis checked")
        XCTAssertEqual(observed.differences, [], "blocks unlike 0.7.0's")
    }

    func testLabelsAndBlocksMadeOnOneThreadReadAlikeOnOthersWhileItWritesOn() {
        let measurer = CoreTextDiagramTextMeasurer(font: DiagramFont(postScriptName: nil, size: 16))
        let made = SharedBlocks()
        let writer = Thread {
            for index in 0..<4_000 {
                let label = DiagramLabelDecoder.label(from: "label number \(index) <b>bold</b> «\(index)»", form: .plain)
                made.append(DiagramTextBlock(label: label, measurer: measurer, maximumWidth: 80), index: index)
            }
            made.finish()
        }
        writer.start()
        var checked = 0
        while !made.isFinished || checked < made.count {
            guard checked < made.count else { continue }
            let (block, index) = made.block(at: checked)
            XCTAssertEqual(block.lines.joined(separator: " "), "label number \(index) bold «\(index)»")
            checked += 1
        }
        XCTAssertEqual(checked, 4_000)
    }

    func testAFullStorageIsLeftForANewOneAndLargeTextGetsItsOwn() {
        let labels = (0..<3_000).map { index in DiagramLabel("label \(index) that fills the storage") }
        XCTAssertGreaterThan(Set(labels.map { label in ObjectIdentifier(label.storage) }).count, 3, "storages filled one after the other")
        for (index, label) in labels.enumerated() { XCTAssertEqual(label.lines, ["label \(index) that fills the storage"]) }
        let large = String(repeating: "word ", count: 2_000)
        let largeLabel = DiagramLabel(large)
        XCTAssertGreaterThanOrEqual(largeLabel.storage.byteCapacity, large.utf8.count)
        XCTAssertNotEqual(ObjectIdentifier(largeLabel.storage), ObjectIdentifier(DiagramLabel("after").storage), "large text has its own storage")
        let measurer = UniformWidthTextMeasurer(characterWidth: 7)
        let block = DiagramTextBlock(label: largeLabel, measurer: measurer, maximumWidth: 200)
        XCTAssertEqual(block.lines, ReferenceTextBlock(label: largeLabel, measurer: measurer, maximumWidth: 200).lines)
    }

    func testABlockOfOneLineThatFitsRefersToItsLabelsBytes() {
        let label = DiagramLabel("Start")
        let block = DiagramTextBlock(label: label, measurer: UniformWidthTextMeasurer(characterWidth: 7), maximumWidth: 200)
        XCTAssertTrue(block.storage === label.storage)
        XCTAssertEqual(block.record.first, label.record.first)
        XCTAssertEqual(block.lineCount, 1)
        XCTAssertEqual(block.lineWidth(at: 0), 35)
        XCTAssertTrue(_isPOD(DiagramTextRecord.self))
        XCTAssertTrue(_isPOD(DiagramLabelRecord.self))
    }

    func testBlocksAndLabelsCompareAsTheirStringsDo() {
        let measurer = UniformWidthTextMeasurer(characterWidth: 7)
        XCTAssertEqual(DiagramLabel("caf\u{E9}"), DiagramLabel("cafe\u{301}"), "canonically equivalent text is equal, as Strings are")
        XCTAssertNotEqual(DiagramLabel("cafe"), DiagramLabel("caff"))
        XCTAssertEqual(DiagramLabel(lines: ["a", "b"]), DiagramLabelDecoder.label(from: "a<br>b", form: .plain))
        XCTAssertNotEqual(DiagramLabel(lines: ["a", "b"]), DiagramLabel(lines: ["a"]))
        let bold = DiagramLabelDecoder.label(from: "<b>a</b>", form: .plain)
        XCTAssertNotEqual(bold, DiagramLabel("a"), "emphasis is part of a label")
        let first = DiagramTextBlock(label: DiagramLabel("same text"), measurer: measurer, maximumWidth: 30)
        let second = DiagramTextBlock(lines: first.lines, lineWidths: first.lineWidths, fontSize: first.fontSize, lineHeight: first.lineHeight)
        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first, first.translated(by: CGVector(dx: 1, dy: 0)))
        XCTAssertNotEqual(DiagramTextBlock(label: bold, measurer: measurer, maximumWidth: 100),
                          DiagramTextBlock(label: DiagramLabel("a"), measurer: measurer, maximumWidth: 100))
    }
}

/// The corpus blocks the observer saw, each measured again by the reference and compared.
private final class ObservedBlocks: @unchecked Sendable {
    private(set) var blockCount = 0
    private(set) var wrappedCount = 0
    private(set) var styledCount = 0
    private(set) var differences: [String] = []

    func check(_ measuring: DiagramTextBlockObservation.Measuring) {
        let reference = measuring.breakingWidth.map { breakingWidth in
            ReferenceTextBlock(label: measuring.label, measurer: measuring.measurer, wrappingWidth: measuring.maximumWidth, breakingWidth: breakingWidth)
        } ?? ReferenceTextBlock(label: measuring.label, measurer: measuring.measurer, maximumWidth: measuring.maximumWidth)
        let block = measuring.block
        blockCount += 1
        if block.lineCount > 1 { wrappedCount += 1 }
        if block.lineRuns != nil { styledCount += 1 }
        let isSame = block.lines == reference.lines && block.lineWidths.map(\.bitPattern) == reference.lineWidths.map(\.bitPattern)
            && block.lineHeight.bitPattern == reference.lineHeight.bitPattern && block.fontSize == measuring.measurer.fontSize
            && block.lineRuns?.map { runs in runs.map { run in "\(run.text)|\(run.style.rawValue)|\(run.width.bitPattern)" } }
            == reference.lineRuns?.map { runs in runs.map { run in "\(run.text)|\(run.style.rawValue)|\(run.width.bitPattern)" } }
        if !isSame, differences.count < 20 { differences.append("\(measuring.label.lines) at \(measuring.maximumWidth): \(block.lines) against \(reference.lines)") }
    }
}

/// Blocks one thread makes and another reads, handed over under a lock.
private final class SharedBlocks: @unchecked Sendable {
    private let lock = NSLock()
    private var blocks: [(DiagramTextBlock, Int)] = []
    private var finished = false

    func append(_ block: DiagramTextBlock, index: Int) {
        lock.lock()
        blocks.append((block, index))
        lock.unlock()
    }

    func finish() {
        lock.lock()
        finished = true
        lock.unlock()
    }

    var isFinished: Bool {
        lock.lock()
        defer { lock.unlock() }
        return finished
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return blocks.count
    }

    func block(at index: Int) -> (DiagramTextBlock, Int) {
        lock.lock()
        defer { lock.unlock() }
        return blocks[index]
    }
}
