/**
 * File: PacketDiagramLayoutTests.swift
 * ------------------------------------
 * Layer: Tests
 * Description: Laying out and painting packet diagrams with Pele's measurements, and the documentation examples.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class PacketDiagramLayoutTests: XCTestCase {
    private func layout(_ source: String) throws -> PacketDiagramLayout {
        PacketDiagramLayoutEngine.layout(try SimpleChartReading.packet(source), text: UniformWidthTextMeasurer(characterWidth: 8, fontSize: 16, lineHeight: 24),
                                         boldText: UniformWidthTextMeasurer(characterWidth: 9, fontSize: 16, lineHeight: 24), font: UniformWidthLayout.font)
    }

    func testBoxesStandOnAGridOfBitsWithTheGapTakenFromTheirWidth() throws {
        let packet = try layout("packet\n0-15: \"Source\"\n16-31: \"Destination\"\n32-63: \"Sequence\"")
        XCTAssertEqual(packet.fields.map(\.frame), [CGRect(x: 8, y: 22, width: 507, height: 32), CGRect(x: 520, y: 22, width: 507, height: 32),
                                                   CGRect(x: 8, y: 22 + 51, width: 1019, height: 32)])
        // 32 bits of 32 points less the gap of 5, 8 points of page either side; two rows of 14 + 32 points and 5 between.
        XCTAssertEqual(packet.size, CGSize(width: 1_035, height: 8 + 2 * (14 + 32) + 5 + 8))
    }

    func testBitNumbersStandAboveBoxesTheFirstAtTheLeftAndTheLastAtTheRight() throws {
        let packet = try layout("packet\n0-7: \"a\"\n8: \"b\"\n9-31: \"c\"")
        XCTAssertEqual(packet.bitNumbers.map { block in block.lines[0] }, ["0", "7", "8", "9", "31"])
        let first = packet.bitNumbers[0], last = packet.bitNumbers[1], single = packet.bitNumbers[2]
        let box = packet.fields[0].frame
        XCTAssertEqual(first.center.x - first.size.width / 2, box.minX, accuracy: 1e-9)
        XCTAssertEqual(last.center.x + last.size.width / 2, box.maxX, accuracy: 1e-9)
        XCTAssertEqual(single.center.x, packet.fields[1].frame.midX, accuracy: 1e-9)
        XCTAssertEqual(first.fontSize, 10)
        // The baseline is 4 points above the box.
        XCTAssertEqual(first.center.y + first.fontSize * 0.35, box.minY - 4, accuracy: 1e-9)
    }

    func testADescendingPacketCountsFromTheRightAndANoBitsOneHasNoNumbers() throws {
        let descending = try layout("---\nconfig:\n  packet:\n    bitOrder: descending\n    bitsPerRow: 16\n---\npacket\n0-7: \"DATA\"\n8-11: \"TYPE\"\n12-15: \"X\"")
        XCTAssertEqual(descending.fields.map(\.frame.minX), [8 + 8 * 32, 8 + 4 * 32, 8])
        XCTAssertEqual(descending.bitNumbers.map { block in block.lines[0] }, ["7", "0", "11", "8", "15", "12"])
        let hidden = try layout("---\nconfig:\n  packet:\n    showBits: false\n---\npacket\n0-31: \"a\"")
        XCTAssertTrue(hidden.bitNumbers.isEmpty)
        XCTAssertEqual(hidden.fields[0].frame.minY, 8)
    }

    func testALabelShrinksThenIsCutToItsBoxAndOneThatCannotBeCutIsLeftOut() throws {
        let packet = try layout("packet\n0: \"AB\"\n1: \"A long label indeed\"\n2-31: \"Wide\"\n+1: \"\"")
        // A one-bit box is 27 points wide and keeps 21 for its label: two characters of 7 points fit at 14 points.
        XCTAssertEqual(packet.fields[0].label?.fontSize, 14)
        // The long one shrinks to 8 points (4 points a character) and is cut to what leaves room for the ellipsis.
        XCTAssertEqual(packet.fields[1].label?.fontSize, 8)
        XCTAssertEqual(packet.fields[1].label?.lines, ["A lo\u{2026}"])
        XCTAssertEqual(packet.fields[2].label?.lines, ["Wide"])
        XCTAssertNil(packet.fields[3].label, "An empty label draws nothing")
        let low = try layout("---\nconfig:\n  packet:\n    rowHeight: 10\n---\npacket\n0-31: \"Wide\"")
        XCTAssertNil(low.fields[0].label, "A label larger than its row is high is left out")
    }

    func testAFieldCrossingARowIsOneBoxPerRowWithTheSameLabel() throws {
        let packet = try layout("packet\n0-10: \"test\"\n11-90: \"multiple\"")
        XCTAssertEqual(packet.fields.count, 4)
        XCTAssertEqual(packet.fields.map(\.firstBit), [0, 11, 32, 64])
        XCTAssertEqual(packet.fields.compactMap { field in field.label?.lines[0] }, ["test", "multiple", "multiple", "multiple"])
    }

    func testTheTitleIsUnderTheRowsAndAWiderTitleMovesTheGridOver() throws {
        let packet = try layout("packet\ntitle T\n0-31: \"a\"")
        XCTAssertEqual(packet.title?.center.y ?? 0, packet.size.height - 8 - 12, accuracy: 1e-9)
        let wide = try layout("---\nconfig:\n  packet:\n    bitsPerRow: 2\n    bitWidth: 10\n---\npacket\ntitle " + String(repeating: "x", count: 40) + "\n0-1: \"a\"")
        XCTAssertEqual(wide.fields[0].frame.minX, 8 + (360 - 15) / 2)
        XCTAssertEqual(wide.size.width, 376)
    }

    func testAPacketPaintsBoxesLabelsBitNumbersAndTheTitleInPelesColorsAndOrder() throws {
        let scene = DiagramScene(layout: PacketDiagramLayoutEngine.layout(try SimpleChartReading.packet("packet\ntitle T\n0-15: \"Source\"\n16-31: \"Destination\""),
                                                                           typography: SimpleChartReading.typography))
        XCTAssertEqual(scene.shapes.count, 1)
        guard case .fillAndStroke(let fill, let outline, let stroke) = scene.shapes[0].painting else { return XCTFail("Boxes are filled and outlined") }
        XCTAssertEqual([fill, outline], [.surface, .border])
        XCTAssertEqual(stroke.lineWidth, 1)
        XCTAssertEqual(scene.texts.map(\.part), [.label, .label, .bitNumber, .bitNumber, .bitNumber, .bitNumber, .title])
        XCTAssertEqual(scene.texts.map(\.paint), [.foreground, .foreground, .muted, .muted, .muted, .muted, .foreground])
        let svg = DiagramSVGWriter().document(of: scene, diagramType: "packet")
        XCTAssertTrue(svg.contains("class=\"pele-node\""))
        XCTAssertTrue(svg.contains("class=\"pele-packet-bits\""))
    }

    func testTheDocumentationExamplesAreLaidOutWithoutOverlap() throws {
        let examples = try PacketDiagramCorpus.documentationExamples()
        XCTAssertEqual(examples.count, 4)
        for example in examples + [PacketDiagramCorpus.generated(fieldCount: 100)] {
            let packet = PacketDiagramLayoutEngine.layout(try SimpleChartReading.packet(example), typography: SimpleChartReading.typography)
            XCTAssertFalse(packet.fields.isEmpty, example)
            for (index, box) in packet.fields.enumerated() {
                XCTAssertTrue(CGRect(origin: .zero, size: packet.size).contains(box.frame), example)
                for other in packet.fields[(index + 1)...] { XCTAssertFalse(box.frame.intersects(other.frame), "\(box.frame) \(other.frame)") }
            }
        }
    }

    func testTheAccessibilityValueNamesEachFieldWithItsBits() throws {
        let prepared = try MermaidDiagramPreparation.prepare(source: "packet\ntitle T\n0-15: \"Source Port\"\n16: \"URG\"", typography: SimpleChartReading.typography)
        XCTAssertEqual(prepared.kind, .packet)
        XCTAssertEqual(prepared.accessibility.label, "T")
        XCTAssertEqual(prepared.accessibility.value, "Source Port: bits 0 to 15; URG: bit 16")
    }
}
