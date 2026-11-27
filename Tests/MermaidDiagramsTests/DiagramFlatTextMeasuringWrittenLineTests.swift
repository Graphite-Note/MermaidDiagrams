/**
 * File: DiagramFlatTextMeasuringWrittenLineTests.swift
 * ----------------------------------------------------
 * Layer: Tests
 * Description: Texts drawn as written (`DiagramLabel(text)`: names, members, cardinalities) measured by
 *              `DiagramFlatTextMeasuring.measure(writtenLine:)`, from bytes and from Strings, against the blocks of their
 *              labels, to the bit: random texts of markup bytes, spaces at their ends, tabs and bytes past ASCII, in three
 *              faces at four widths, and every member and name of the class corpus.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics
import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class DiagramFlatTextMeasuringWrittenLineTests: XCTestCase {
    /// 16 and 12 points sum exactly, 12.8 does not.
    private static let measurers = [16, 12, 12.8].map { size in CoreTextDiagramTextMeasurer(font: DiagramFont(postScriptName: nil, size: size)) }

    func testWrittenLinesMeasureAsTheBlocksOfTheirLabels() throws {
        let parts = ["word", "a", " ", "  ", "\t", "<br>", "<b>", "**", "*", "_x_", "&amp;", "#35;", "fa:fa-car", "~T~", "List<int>", "()", "+", "$",
                     "\\n", "é", "«", "LongUnbrokenWordOfManyLetters", ":", ";", "%%"]
        var state: UInt64 = 0x7E_17E
        func next(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(bound))
        }
        var texts = (0..<3_000).map { _ in (0..<(1 + next(8))).map { _ in parts[next(parts.count)] }.joined() }
        texts += try Self.classCorpusTexts()
        var compared = 0
        for measurer in Self.measurers {
            let flat = DiagramFlatMeasurer(measurer)
            for width: CGFloat in [.greatestFiniteMagnitude, 120, 40, 0] {
                for text in texts {
                    let block = DiagramTextBlock(label: DiagramLabel(text), measurer: measurer, maximumWidth: width)
                    let source = Array(text.utf8)
                    var lines = DiagramMeasuredLines()
                    let fromBytes = source.withUnsafeBufferPointer { bytes in
                        DiagramFlatTextMeasuring.measure(writtenLine: bytes, MermaidTextRange(start: 0, end: bytes.count), measurer: flat, maximumWidth: width,
                                                         into: &lines)
                    }
                    XCTAssertNil(DiagramFlatTextMeasuringTests.difference(fromBytes, lines, source: source, block), "\(text.debugDescription) at \(width)")
                    var derived = DiagramMeasuredLines()
                    let fromString = DiagramFlatTextMeasuring.measure(writtenLine: text, measurer: flat, maximumWidth: width, into: &derived)
                    XCTAssertNil(DiagramFlatTextMeasuringTests.difference(fromString, derived, source: [], block), "\(text.debugDescription) at \(width)")
                    compared += 1
                }
            }
        }
        XCTAssertGreaterThan(compared, 36_000)
    }

    /// Every member shown and every class's identifier of the corpora's class diagrams.
    private static func classCorpusTexts() throws -> [String] {
        var texts: [String] = []
        for source in try OutputDigest.corpora().flatMap(\.sources) {
            guard case .classDiagram(let diagram)? = try? MermaidDiagramReader.read(source, limits: .standard) else { continue }
            for declared in diagram.classes { texts += [declared.identifier] + declared.attributes.map(\.text) + declared.methods.map(\.text) }
        }
        XCTAssertGreaterThan(texts.count, 150)
        return texts
    }
}
