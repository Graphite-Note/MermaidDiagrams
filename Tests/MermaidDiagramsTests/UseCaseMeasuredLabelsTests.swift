/**
 * File: UseCaseMeasuredLabelsTests.swift
 * --------------------------------------
 * Layer: Tests
 * Description: A use case label measured from the range of its text gives the block its String gives, to the bit: the
 *              labels of every use case diagram of the corpora and 6,000 random labels (plain and Markdown, with white
 *              space, Mermaid's codes, breaks, emphasis, control characters and bytes past ASCII, long enough to wrap),
 *              in faces whose advances sum exactly and one whose do not, at the rooms a use case layout wraps at, and on
 *              eight threads at once.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics
import Foundation
import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class UseCaseMeasuredLabelsTests: XCTestCase {
    static let rooms: [CGFloat] = [UseCaseNodeMeasurement.actorRoom, UseCaseNodeMeasurement.textRoom, UseCaseLayoutEngine.edgeLabelRoomWidth, 40,
                                   UseCaseNodeMeasurement.titleRoom]

    static var measurers: [CoreTextDiagramTextMeasurer] {
        [16, 14, 12.8].map { size in DiagramTypography(font: DiagramFont(postScriptName: nil, size: CGFloat(size))).measurer(size: CGFloat(size), isBold: false, isItalic: false) }
    }

    func testTheLabelsOfTheCorporaAreMeasuredAsTheirStringsAre() throws {
        var labels: [(String, UseCaseLabelType)] = []
        for source in try OutputDigest.corpora().flatMap(\.sources) + UseCaseCorpus.documentationExamples() {
            guard case .useCase(let diagram)? = try? MermaidDiagramReader.read(source, limits: .standard) else { continue }
            labels += diagram.actors.map { ($0.label, $0.labelType) } + diagram.useCases.map { ($0.label, $0.labelType) }
                + diagram.notes.map { ($0.label, $0.labelType) } + diagram.systemBoundaries.map { ($0.label, $0.labelType) }
                + diagram.relationships.compactMap { relationship in relationship.label.map { ($0, relationship.labelType ?? .text) } }
        }
        XCTAssertGreaterThan(labels.count, 200)
        XCTAssertEqual(Self.mismatchCount(labels, measurers: Self.measurers), 0)
    }

    func testRandomLabelsAreMeasuredAsTheirStringsAre() {
        var random = RandomUseCaseLabels(seed: 0x1AB_E15)
        let labels = (0..<6_000).map { index in (random.label(), index % 3 == 0 ? UseCaseLabelType.markdown : .text) }
        XCTAssertEqual(Self.mismatchCount(labels, measurers: Self.measurers), 0)
    }

    func testLabelsMeasuredOnManyThreadsAtOnceAreTheirStringsBlocks() {
        var random = RandomUseCaseLabels(seed: 77)
        let labels = (0..<400).map { index in (random.label(), index % 3 == 0 ? UseCaseLabelType.markdown : .text) }
        let mismatches = ManagedCounter()
        let measurers = Self.measurers
        DispatchQueue.concurrentPerform(iterations: 8) { thread in
            let count = Self.mismatchCount(labels, measurers: [measurers[thread % measurers.count]])
            for _ in 0..<count { mismatches.increment() }
        }
        XCTAssertEqual(mismatches.value, 0)
    }

    /// How many of the labels, written one after the other into one text, are measured from their ranges otherwise than
    /// from their Strings, in any measurer and room.
    static func mismatchCount(_ labels: [(String, UseCaseLabelType)], measurers: [CoreTextDiagramTextMeasurer]) -> Int {
        var bytes: [UInt8] = []
        var ranges: [MermaidTextRange] = []
        for (label, _) in labels {
            let start = bytes.count
            bytes += Array(label.utf8)
            ranges.append(MermaidTextRange(start: start, end: bytes.count))
        }
        var measuredLabels = UseCaseMeasuredLabels()
        var mismatches = 0
        bytes.withUnsafeBufferPointer { text in
            for measurer in measurers {
                for room in rooms {
                    for (index, (label, type)) in labels.enumerated() {
                        let expected = UseCaseTextLabel.block(label, labelType: type, measurer: measurer, room: room)
                        let measured = measuredLabels.block(UseCaseLabelText(text: ranges[index], type: type), in: text, measurer: measurer, room: room)
                        if measured != expected || measured.size.width.bitPattern != expected.size.width.bitPattern
                            || measured.size.height.bitPattern != expected.size.height.bitPattern || measured.lineCount != expected.lineCount {
                            mismatches += 1
                        }
                    }
                }
            }
        }
        return mismatches
    }
}

/// Labels of the pieces a use case label's measuring treats apart.
struct RandomUseCaseLabels {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    private mutating func below(_ bound: Int) -> Int {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Int((state >> 33) % UInt64(max(bound, 1)))
    }

    private static let pieces = ["Sign in", "a", "word", " ", "  ", "\t", "#quot;", "#40;", "#", ";", "&amp;", "<br>", "**bold**", "_em_", "REQ_001",
                                 "Ünïcödé", "中文", "\u{A0}", "\u{2003}", "\n", "\\n", "x", "Generate the monthly report for every region", "-", "*", "`"]

    mutating func label() -> String {
        var label = ""
        for _ in 0..<below(9) { label += Self.pieces[below(Self.pieces.count)] }
        return label
    }
}
