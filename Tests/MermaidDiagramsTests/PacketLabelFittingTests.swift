/**
 * File: PacketLabelFittingTests.swift
 * -----------------------------------
 * Layer: Tests
 * Description: A packet field that crosses rows has its label fitted to each of its boxes' own widths: the fits the
 *              layout keeps for the field's pieces give each piece the label a field of that piece alone would get.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics
import XCTest
@testable import MermaidDiagrams

final class PacketLabelFittingTests: XCTestCase {
    private static let label = "a long label that is shrunk then cut to its box"

    private func layout(_ source: String) throws -> PacketDiagramLayout {
        PacketDiagramLayoutEngine.layout(try SimpleChartReading.packet(source), text: UniformWidthTextMeasurer(characterWidth: 8, fontSize: 16, lineHeight: 24),
                                         boldText: UniformWidthTextMeasurer(characterWidth: 9, fontSize: 16, lineHeight: 24), font: UniformWidthLayout.font)
    }

    /// The pieces of one field, 3 to 29 after a field of 0 to 2 on rows of 8 bits (5, 8, 8 and 6 bits wide), and of a
    /// field crossing a row followed by another that does too, are labelled as fields of those pieces' bits each are.
    func testEachPieceOfAFieldCrossingRowsIsLabelledForItsOwnWidth() throws {
        let header = "---\nconfig:\n  packet:\n    bitsPerRow: 8\n---\npacket\n"
        let cases: [(crossing: String, separate: String)] = [
            ("0-2: \"x\"\n3-29: \"\(Self.label)\"", "0-2: \"x\"\n3-7: \"\(Self.label)\"\n8-15: \"\(Self.label)\"\n16-23: \"\(Self.label)\"\n24-29: \"\(Self.label)\""),
            ("0-10: \"\(Self.label)\"\n11-20: \"short\"",
             "0-7: \"\(Self.label)\"\n8-10: \"\(Self.label)\"\n11-15: \"short\"\n16-20: \"short\""),
        ]
        for (crossing, separate) in cases {
            let crossingLayout = try layout(header + crossing)
            let separateLayout = try layout(header + separate)
            XCTAssertEqual(crossingLayout.fields.map(\.frame), separateLayout.fields.map(\.frame), crossing)
            XCTAssertEqual(crossingLayout.fields.map(\.label), separateLayout.fields.map(\.label), crossing)
        }
        // The widths differ enough that the pieces' labels do: a fit kept for one width is not another's.
        let pieces = try layout(header + cases[0].crossing).fields.dropFirst()
        XCTAssertGreaterThan(Set(pieces.compactMap { field in field.label?.lines.first }).count, 1)
    }
}
