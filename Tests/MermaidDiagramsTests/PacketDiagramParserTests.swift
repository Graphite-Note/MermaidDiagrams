/**
 * File: PacketDiagramParserTests.swift
 * ------------------------------------
 * Layer: Tests
 * Description: Reading packet diagrams: the inputs of Pele's ported specifications, options, hostile numbers and blocks of front matter.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

/// Mermaid's packet specifications (`packet.spec.ts`, `packet.test.ts`) ported: what each text reads as, and the errors Mermaid's
/// database throws, as typed problems with their line.
final class PacketDiagramParserTests: XCTestCase {
    private func fields(_ source: String) throws -> [(String, Int, Int)] {
        try SimpleChartReading.packet(source).fields.map { field in (field.label, field.firstBit, field.lastBit) }
    }

    func testBothKeywordsReadAnEmptyPacketInAnySpacing() throws {
        for source in ["packet-beta", "  packet-beta  ", "\tpacket-beta\t", "\n    \tpacket-beta\n    ", "packet", "  packet  ", "\tpacket\t", "\n    \tpacket\n    "] {
            XCTAssertEqual(try SimpleChartReading.packet(source), PacketDiagram(), source)
        }
    }

    func testTitlesAndAFieldOfARange() throws {
        let packet = try SimpleChartReading.packet("packet\n    title Packet diagram\n    accTitle: Packet accTitle\n    accDescr: Packet accDescription\n    0-10: \"test\"\n    ")
        XCTAssertEqual(packet.title, "Packet diagram")
        XCTAssertEqual(packet.accessibilityTitle, "Packet accTitle")
        XCTAssertEqual(packet.accessibilityDescription, "Packet accDescription")
        XCTAssertEqual(packet.fields, [PacketField(label: "test", firstBit: 0, lastBit: 10)])
        XCTAssertEqual(packet.fields[0].bitCount, 11)
    }

    func testSingleBitsAndBitCountsFollowOneAnother() throws {
        XCTAssertEqual(try fields("packet\n0-10: \"test\"\n11: \"single\"\n").map(\.0), ["test", "single"])
        XCTAssertEqual(try fields("packet\n0-10: \"test\"\n11: \"single\"\n").map(\.2), [10, 11])
        let counted = try fields("packet\n    +8: \"byte\"\n    +16: \"word\"\n    ")
        XCTAssertEqual(counted.map(\.1), [0, 8])
        XCTAssertEqual(counted.map(\.2), [7, 23])
        XCTAssertEqual(try fields("packet\n+1: \"a\"\n+1: \"b\"").map(\.2), [0, 1])
    }

    func testFieldsAreSplitAtTheEndsOfRows() {
        let fields = [PacketField(label: "test", firstBit: 0, lastBit: 10), PacketField(label: "multiple", firstBit: 11, lastBit: 90)]
        let rows = PacketFieldRows.rows(of: fields, bitsPerRow: 32).map { row in row.map { piece in [piece.fieldIndex, piece.firstBit, piece.lastBit] } }
        XCTAssertEqual(rows, [[[0, 0, 10], [1, 11, 31]], [[1, 32, 63]], [[1, 64, 90]]])
        let exact = [PacketField(label: "test", firstBit: 0, lastBit: 16), PacketField(label: "multiple", firstBit: 17, lastBit: 63)]
        XCTAssertEqual(PacketFieldRows.rows(of: exact, bitsPerRow: 32).map { row in row.map { piece in [piece.firstBit, piece.lastBit] } },
                       [[[0, 16], [17, 31]], [[32, 63]]])
        XCTAssertEqual(PacketFieldRows.rows(of: [], bitsPerRow: 32), [])
        XCTAssertEqual(PacketFieldRows.rows(of: [PacketField(label: "a", firstBit: 0, lastBit: 2)], bitsPerRow: 1).count, 3)
    }

    func testFieldsThatAreNotContiguousAreRefusedWithTheBitTheyShouldStartAt() {
        func error(_ body: String) -> MermaidDiagramReadError? { SimpleChartReading.readError("packet\n" + body) }
        XCTAssertEqual(error("0-16: \"test\"\n18-20: \"error\""), .invalidSyntax(line: 3, problem: .packet(.notContiguous(firstBit: 18, lastBit: 20, expectedFirstBit: 17))))
        XCTAssertEqual(error("+16: \"test\"\n18-20: \"error\""), .invalidSyntax(line: 3, problem: .packet(.notContiguous(firstBit: 18, lastBit: 20, expectedFirstBit: 16))))
        XCTAssertEqual(error("0-16: \"test\"\n18: \"error\""), .invalidSyntax(line: 3, problem: .packet(.notContiguous(firstBit: 18, lastBit: 18, expectedFirstBit: 17))))
        XCTAssertEqual(error("+16: \"test\"\n18: \"error\""), .invalidSyntax(line: 3, problem: .packet(.notContiguous(firstBit: 18, lastBit: 18, expectedFirstBit: 16))))
        XCTAssertEqual(error("0-16: \"test\"\n17: \"good\"\n19: \"error\""), .invalidSyntax(line: 4, problem: .packet(.notContiguous(firstBit: 19, lastBit: 19, expectedFirstBit: 18))))
        XCTAssertEqual(error("1: \"late\""), .invalidSyntax(line: 2, problem: .packet(.notContiguous(firstBit: 1, lastBit: 1, expectedFirstBit: 0))))
    }

    func testARangeEndingBeforeItStartsAndAZeroBitFieldAreRefused() {
        XCTAssertEqual(SimpleChartReading.readError("packet\n0-16: \"test\"\n25-20: \"error\""),
                       .invalidSyntax(line: 3, problem: .packet(.endBeforeStart(firstBit: 25, lastBit: 20))))
        XCTAssertEqual(SimpleChartReading.readError("packet\n+0: \"test\""), .invalidSyntax(line: 2, problem: .packet(.zeroBitField(firstBit: 0))))
    }

    func testMalformedFieldsAreRefusedWhereTheyBreak() {
        XCTAssertEqual(SimpleChartReading.readError("packet\n0-15 \"a\""), .invalidSyntax(line: 2, problem: .packet(.expectedColon)))
        XCTAssertEqual(SimpleChartReading.readError("packet\n0:"), .invalidSyntax(line: 2, problem: .packet(.expectedFieldLabel)))
        XCTAssertEqual(SimpleChartReading.readError("packet\n+: \"a\""), .invalidSyntax(line: 2, problem: .packet(.expectedBitNumber)))
        XCTAssertEqual(SimpleChartReading.readError("packet\n0-\n1: \"a\""), .invalidSyntax(line: 2, problem: .packet(.expectedBitNumber)))
        XCTAssertEqual(SimpleChartReading.readError("packet\n0: \"a"), .invalidSyntax(line: 2, problem: .unclosedQuotation))
        XCTAssertEqual(SimpleChartReading.readError("packet\n08: \"a\""), .invalidSyntax(line: 2, problem: .packet(.expectedColon)))
        XCTAssertNotNil(SimpleChartReading.readError("packet\n8.: \"a\""))
        XCTAssertNotNil(SimpleChartReading.readError("packet 0-15: \"a\" 16: \"b\""))
        XCTAssertNotNil(SimpleChartReading.readError("packet\n-15: \"a\""))
        XCTAssertNotNil(SimpleChartReading.readError("packet\n1-2-3: \"a\""))
    }

    func testLabelsMayBeQuotedEitherWayAndEscapedAndFollowedByAComment() throws {
        XCTAssertEqual(try fields("packet\n0-15: \"Source\"\n16: 'x'\n+8: \"y\\\"z\" %% comment\n").map(\.0), ["Source", "x", "y\"z"])
        XCTAssertEqual(try fields("packet\n0 - 15 : \"a\"").map(\.2), [15])
    }

    func testABlockOfFrontMatterBetweenFieldsIsDropped() throws {
        XCTAssertEqual(try fields("packet\n0-1: \"a\"\n---\nfoo\n---\n2: \"b\"").map(\.1), [0, 2])
        XCTAssertEqual(try fields("packet\n0---\n--- : \"b\"").map(\.2), [0])
        XCTAssertNotNil(SimpleChartReading.readError("packet\n0---\n---: \"b\""), "The block's closing line is followed by a character that is not white space")
        XCTAssertNotNil(SimpleChartReading.readError("packet\n0---\n---\n1: \"b\""))
        XCTAssertNotNil(SimpleChartReading.readError("packet\n---\n"))
    }

    func testOptionsComeFromTheFrontMatterAndDirectivesCutToTheirBounds() throws {
        let options = try SimpleChartReading.packet("---\nconfig:\n  packet:\n    showBits: false\n    bitOrder: descending\n    bitsPerRow: 16.9\n    bitWidth: 9999\n    rowHeight: 0\n    paddingX: -1\n    paddingY: 8\n---\npacket\n0-7: \"A\"").options
        XCTAssertEqual(options.bitsPerRow, 16)
        XCTAssertEqual(options.bitWidth, 400)
        XCTAssertEqual(options.rowHeight, 32, "Below its least, an option keeps its default")
        XCTAssertEqual(options.horizontalPadding, 5)
        XCTAssertEqual(options.verticalPadding, 8)
        XCTAssertFalse(options.showsBitNumbers)
        XCTAssertTrue(options.isDescending)
        XCTAssertEqual(try SimpleChartReading.packet("%%{init: {'packet': {'bitsPerRow': 8}}}%%\npacket\n+8: \"a\"").options.bitsPerRow, 8)
        XCTAssertEqual(PacketOptions(), try SimpleChartReading.packet("packet").options)
    }

    func testHugeNumbersAreCutAndFieldsOrRowsPastTheLimitAreRefused() {
        XCTAssertEqual(SimpleChartReading.readError("packet\n+1000000000: \"wide\"\n+1: \"after\""), .tooManyNodes(limit: 5_000))
        XCTAssertEqual(SimpleChartReading.readError("packet\n+" + String(repeating: "9", count: 400) + ": \"x\"\n+1: \"y\""), .tooManyNodes(limit: 5_000))
        XCTAssertEqual(SimpleChartReading.readError("---\nconfig:\n  packet:\n    bitsPerRow: 1\n---\npacket\n+20000: \"a\""), .tooManyNodes(limit: 5_000))
        XCTAssertEqual(SimpleChartReading.readError("packet\n99999999999999999999-5: \"a\""), .invalidSyntax(line: 2, problem: .packet(.endBeforeStart(firstBit: 9_007_199_254_740_992, lastBit: 5))))
        var limits = MermaidDiagramLimits.standard
        limits.maximumNodeCount = 3
        XCTAssertEqual(SimpleChartReading.readError("packet\n+1: \"a\"\n+1: \"b\"\n+1: \"c\"\n+1: \"d\"", limits: limits), .tooManyNodes(limit: 3))
        XCTAssertNil(SimpleChartReading.readError("packet\n+32: \"a\"\n+32: \"b\"\n+32: \"c\"", limits: limits))
    }
}
