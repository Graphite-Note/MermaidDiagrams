/**
 * File: SequenceReadingPiecesEquivalenceTests.swift
 * -------------------------------------------------
 * Layer: Tests
 * Description: The pieces of the sequence reader and layout that read on bytes, in short lists or in place give what
 *              0.7.0's gave: a text's wrap prefix told as Swift's characters told it, each participant found at the index a
 *              dictionary of identifiers gave, and each message moved where it stands as moving it into a new one moved it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import CoreGraphics
import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class SequenceReadingPiecesEquivalenceTests: XCTestCase {
    /// 0.7.0's `SequenceTextSyntax.withoutWrapPrefix`, frozen as main dad6fb8 has it.
    private static func referenceWithoutWrapPrefix(_ text: String) -> (text: String, wraps: Bool) {
        let unprefixed = text.hasPrefix(":") ? text.dropFirst() : Substring(text)
        for (prefix, wraps) in [("wrap:", true), ("nowrap:", false)] where unprefixed.hasPrefix(prefix) {
            var trimmed = unprefixed.dropFirst(prefix.count)
            while let first = trimmed.first, first == " " || first == "\t" { trimmed = trimmed.dropFirst() }
            while let last = trimmed.last, last == " " || last == "\t" { trimmed = trimmed.dropLast() }
            return (String(trimmed), wraps)
        }
        return (text, false)
    }

    private struct Random {
        var state: UInt64

        mutating func below(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(max(bound, 1)))
        }
    }

    func testWrapPrefixesAreToldAsSwiftsCharactersTellThem() {
        let pieces = [":", "wrap", "wrap:", "nowrap:", "no", "w", ":wrap:", "\u{301}", "é", "e", " ", "\t", "Hello", "x", "\r\n", "\n", "中", "\u{0308}",
                      "WRAP:", "wrap\u{301}:", ":\u{301}"]
        var random = Random(state: 0xA1B2_C3D4)
        for _ in 0..<30_000 {
            let text = (0..<random.below(6)).map { _ in pieces[random.below(pieces.count)] }.joined()
            let read = SequenceTextSyntax.withoutWrapPrefix(text)
            let expected = Self.referenceWithoutWrapPrefix(text)
            XCTAssertEqual(read.text, expected.text, text.debugDescription)
            XCTAssertEqual(read.wraps, expected.wraps, text.debugDescription)
            XCTAssertEqual(Array(read.text.unicodeScalars), Array(expected.text.unicodeScalars), text.debugDescription)
        }
    }

    /// Identifiers met in a random order, some of them spelled two ways Swift holds equal: the table finds each at the
    /// index a dictionary finds it at, through and past the length it compares in turn.
    func testParticipantsAreFoundWhereADictionaryFindsThem() {
        let spellings = ["Alice", "Bob", "é", "e\u{301}", "Zoë", "Zoe\u{308}", "A", "a", "B 2", "", " ", "中", "Ω", "\u{2126}"]
        var random = Random(state: 0x5E9_7AB1E)
        for round in 0..<300 {
            var table = SequenceParticipantNameTable()
            var dictionary: [String: Int] = [:]
            let pool = spellings + (0..<(round % 40)).map { index in "P\(index)" }
            for _ in 0..<200 {
                let name = pool[random.below(pool.count)]
                XCTAssertEqual(table.index(of: name), dictionary[name], name.debugDescription)
                if dictionary[name] == nil {
                    dictionary[name] = dictionary.count
                    table.append(name)
                }
            }
        }
    }

    private static let largeLimits = MermaidDiagramLimits(maximumSourceBytes: 1_000_000, maximumNodeCount: 5_000, maximumEdgeCount: 5_000,
                                                          maximumLayoutPointCount: 50_000)

    /// Thousands of participants, each named by many messages, are read in time that grows with them.
    func testManyParticipantsStayBounded() throws {
        let messages = (0..<4_000).map { index in "P\(index % 2_000)->>P\((index * 7) % 2_000): m" }.joined(separator: "\n")
        let started = Date()
        guard case .sequence(let diagram) = try MermaidDiagramReader.read("sequenceDiagram\n" + messages, limits: Self.largeLimits) else {
            return XCTFail("not a sequence diagram")
        }
        XCTAssertEqual(diagram.participants.count, 2_000)
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
    }

    /// Every message of every corpus sequence, moved where it stands, is the message `translated(by:)` makes, bit for bit,
    /// for offsets of every size and sign.
    func testMessagesMovedInPlaceAreThoseMovedIntoNewOnes() throws {
        var random = Random(state: 0x70_7AB1E)
        var compared = 0
        for source in try OutputDigest.corpora().flatMap(\.sources) {
            guard case .sequence(let diagram) = try? MermaidDiagramReader.read(source, limits: .standard),
                  let layout = try? SequenceLayoutEngine.layout(diagram, typography: DiagramSceneSamples.typography) else { continue }
            for message in layout.messages {
                let offset = CGVector(dx: CGFloat(random.below(20_000)) / 7 - 1_000, dy: CGFloat(random.below(20_000)) / 3 - 3_000)
                var moved = message
                moved.translate(by: offset)
                let expected = message.translated(by: offset)
                XCTAssertEqual(moved, expected)
                XCTAssertEqual(moved.path.start.x.bitPattern, expected.path.start.x.bitPattern)
                XCTAssertEqual(moved.heads.map(\.tip.y.bitPattern), expected.heads.map(\.tip.y.bitPattern))
                compared += 1
            }
        }
        XCTAssertGreaterThan(compared, 100)
    }
}
