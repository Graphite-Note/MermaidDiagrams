/**
 * File: GraphDiagramNameTableTests.swift
 * --------------------------------------
 * Layer: Tests
 * Description: The graph diagrams' name table gives each name one number, as 0.7.0's String keys did, and stays fast
 *              on names written to share the bits of FNV-1a's hash that do not depend on its basis: thousands of names
 *              that differ only in the case of their letters, or only in bits above the low five of each byte.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import Foundation
import XCTest
@testable import MermaidDiagrams

final class GraphDiagramNameTableTests: XCTestCase {
    /// Every name a number of its own, the same number when it comes again; in a text beyond ASCII, two spellings
    /// Swift holds equal are one name.
    func testEachNameHasOneNumber() {
        let names = Self.caseVariants(of: "abcdefghijkl") + Self.highBitVariants(count: 4_096) + (0..<4_096).map { index in "s\(index)" }
        XCTAssertEqual(Set(names).count, names.count)
        let text = Array(names.joined(separator: " ").utf8)
        var ranges: [MermaidTextRange] = []
        var start = 0
        for name in names {
            ranges.append(MermaidTextRange(start: start, end: start + name.utf8.count))
            start += name.utf8.count + 1
        }
        text.withUnsafeBufferPointer { buffer in
            var table = GraphDiagramNameTable(isASCII: true)
            for (index, range) in ranges.enumerated() {
                let interned = table.intern(buffer, range)
                XCTAssertEqual(interned.number, index)
                XCTAssertTrue(interned.isNew)
            }
            for (index, range) in ranges.enumerated().reversed() {
                let interned = table.intern(buffer, range)
                XCTAssertEqual(interned.number, index)
                XCTAssertFalse(interned.isNew)
            }
            XCTAssertEqual(table.count, names.count)
        }
        var written = GraphDiagramNameTable(isASCII: false)
        XCTAssertEqual(written.intern("caf\u{E9}").number, 0)
        XCTAssertEqual(written.intern("cafe\u{301}").number, 0)
        XCTAssertFalse(written.intern("cafe\u{301}").isNew)
        XCTAssertEqual(written.intern("cafe").number, 1)
    }

    /// A state named in two spellings Swift holds equal (a composed and a decomposed letter, the Kelvin sign and `K`) is
    /// one state, in a transition, a declaration and a note alike, as 0.7.0's String keys made it.
    func testSpellingsSwiftHoldsEqualNameOneState() throws {
        let sources = [
            "stateDiagram-v2\n  caf\u{E9} --> cafe\u{301}\n  cafe\u{301} --> [*]",
            "stateDiagram-v2\n  state \"Waiting\" as caf\u{E9}\n  cafe\u{301} --> B\n  note left of caf\u{E9} : n",
            "stateDiagram-v2\n  \u{212A} --> K : t\n  state K {\n    [*] --> \u{212A}x\n  }",
        ]
        XCTAssertEqual(StateReadingEquivalenceTests.assertReadAlike(sources), sources.count)
        let stateCounts = try sources.map { source -> Int in
            guard case .stateDiagram(let diagram) = try MermaidDiagramReader.read(source, limits: .standard) else { return -1 }
            return diagram.states.filter { state in state.kind != .start && state.kind != .end }.count
        }
        XCTAssertEqual(stateCounts, [1, 2, 2])
    }

    /// State diagrams whose 8,192 names collide in the hash's low bits for every basis are read as the reference reads
    /// them, and in time that grows with their count: ten times the names in at most forty times the time, where a
    /// table whose names all fell in one run of slots would take about a hundred times.
    func testNamesThatShareTheHashsLowBitsAreReadAlikeAndInTime() {
        func machine(_ names: [String]) -> String {
            "stateDiagram-v2\n" + names.enumerated().map { index, name in "  \(name) --> \(names[(index &* 7 &+ 1) % names.count])" }.joined(separator: "\n")
        }
        let limits = MermaidDiagramLimits(maximumSourceBytes: 10_000_000, maximumNodeCount: 100_000, maximumEdgeCount: 100_000,
                                          maximumLayoutPointCount: 1_000_000)
        let caseVariants = Self.caseVariants(of: "abcdefghijklm")
        let highBitVariants = Self.highBitVariants(count: caseVariants.count)
        let sources = [machine(caseVariants), machine(highBitVariants), machine((0..<caseVariants.count).map { index in "state\(index)" })]
        XCTAssertEqual(StateReadingEquivalenceTests.assertReadAlike(sources, limits: limits), sources.count)
        func seconds(_ source: String) -> Double {
            let start = Date()
            for _ in 0..<3 { _ = try? MermaidDiagramReader.read(source, limits: limits) }
            return Date().timeIntervalSince(start)
        }
        for names in [caseVariants, highBitVariants] {
            let small = machine(Array(names.prefix(names.count / 10)))
            _ = seconds(small)
            XCTAssertLessThan(seconds(machine(names)), max(seconds(small), 0.002) * 40)
        }
    }

    /// The 2^n spellings of `word` in upper and lower case: their bytes differ only in bit 5, so the low five bits of
    /// their FNV-1a hashes are alike whatever the basis.
    static func caseVariants(of word: String) -> [String] {
        let letters = Array(word.utf8)
        return (0..<(1 << letters.count)).map { mask in
            String(decoding: letters.enumerated().map { index, byte in mask & (1 << index) != 0 ? byte & ~0x20 : byte }, as: UTF8.self)
        }
    }

    /// `count` names of ten bytes, `q` and nine of `0`, `P` and `p` (0x30, 0x50, 0x70), which share their low five bits,
    /// so that the names' hashes' low five bits agree whatever the basis.
    static func highBitVariants(count: Int) -> [String] {
        let choices: [UInt8] = [0x30, 0x50, 0x70]
        return (0..<count).map { number in
            var remaining = number
            var bytes: [UInt8] = [UInt8(ascii: "q")]
            for _ in 0..<9 {
                bytes.append(choices[remaining % choices.count])
                remaining /= choices.count
            }
            return String(decoding: bytes, as: UTF8.self)
        }
    }
}
