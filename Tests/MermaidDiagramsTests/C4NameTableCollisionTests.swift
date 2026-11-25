/**
 * File: C4NameTableCollisionTests.swift
 * -------------------------------------
 * Layer: Tests
 * Description: Names made to collide in FNV-1a, all of one hash, are interned by the C4 name table in a number of probes
 *              that grows with their count, not its square: the table turns to the seeded hash, keeps the numbers given
 *              in the order met, and a C4 diagram whose aliases all collide is read as the 0.7.0 reader reads it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class C4NameTableCollisionTests: XCTestCase {
    /// Twelve pairs of seven-byte blocks, the blocks of a pair of one FNV-1a hash from the state the pairs before them
    /// leave: FNV-1a's state is its hash, so the names made of one block of each of the first pairs, in order, all have
    /// one hash (a multicollision, found by a birthday search per pair).
    private static let collidingBlockPairs = [("17bbx86", "rsu6ug6"), ("sz3pggy", "7xvujyn"), ("dpws4ca", "n9ldojf"), ("2kbm336", "jz0gl1t"),
                                              ("pynu9pr", "vys6gn4"), ("fmyxmts", "bef7g1l"), ("e6e3m3i", "c93b3ou"), ("9d2g6xr", "a8rf8sb"),
                                              ("j7i9w09", "b651ncj"), ("o9mytlh", "bf1zhsp"), ("yggyeta", "ofia4cj"), ("ljch45n", "ar701ng")]

    /// The `2^blockCount` names of the first `blockCount` pairs.
    private func collidingNames(blockCount: Int) -> [String] {
        (0..<(1 << blockCount)).map { number in
            (0..<blockCount).map { block in
                let pair = Self.collidingBlockPairs[block]
                return (number >> block) & 1 == 0 ? pair.0 : pair.1
            }.joined()
        }
    }

    private static func fowlerNollVoHash(_ text: String) -> UInt32 {
        var hash: UInt32 = 2_166_136_261
        for byte in text.utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
        return hash
    }

    func testTheNamesCollideInFowlerNollVo() {
        let names = collidingNames(blockCount: 12)
        XCTAssertEqual(Set(names).count, 4_096)
        XCTAssertEqual(Set(names.map(Self.fowlerNollVoHash)), [0x65d5_8a86] as Set<UInt32>)
    }

    func testCollidingNamesAreInternedInLinearlyManyProbes() {
        let names = collidingNames(blockCount: 12)
        let text = Array(names.joined(separator: " ").utf8)
        var table = C4NameTable(bytes: text)
        var numbers: [Int32] = []
        text.withUnsafeBufferPointer { bytes in
            var start = 0
            for name in names {
                numbers.append(table.intern(bytes, from: start, to: start + name.utf8.count))
                start += name.utf8.count + 1
            }
            // Each name again: its own number.
            start = 0
            for (index, name) in names.enumerated() {
                XCTAssertEqual(table.intern(bytes, from: start, to: start + name.utf8.count), Int32(index))
                start += name.utf8.count + 1
            }
        }
        XCTAssertEqual(numbers, (0..<Int32(names.count)).map { $0 })
        XCTAssertEqual(table.count, names.count)
        XCTAssertTrue(table.isSeeded)
        // 4,096 names met twice: FNV-1a alone would have looked at about 8 million slots.
        XCTAssertLessThan(table.probeCount, 24 * names.count)
    }

    /// Plain names keep FNV-1a.
    func testOrdinaryNamesKeepTheFastHash() {
        let names = (0..<2_000).map { index in "shape\(index)" }
        let text = Array(names.joined(separator: " ").utf8)
        var table = C4NameTable(bytes: text)
        text.withUnsafeBufferPointer { bytes in
            var start = 0
            for name in names {
                _ = table.intern(bytes, from: start, to: start + name.utf8.count)
                start += name.utf8.count + 1
            }
        }
        XCTAssertFalse(table.isSeeded)
        XCTAssertEqual(table.count, names.count)
    }

    /// A diagram of 2,048 people whose aliases all collide, each related to the next: read alike.
    func testADiagramWhoseAliasesAllCollideIsReadAsTheReferenceReadsIt() {
        let names = collidingNames(blockCount: 11)
        var lines = ["C4Context"]
        for name in names { lines.append("Person(\(name), \"\(name.prefix(6))\")") }
        for index in 1..<names.count { lines.append("Rel(\(names[index - 1]), \(names[index]), \"uses\")") }
        var limits = MermaidDiagramLimits.standard
        limits.maximumSourceBytes = 1_000_000
        let source = lines.joined(separator: "\n")
        XCTAssertEqual(C4ReadingEquivalenceTests.assertReadAlike([source], limits: limits), 1)
        guard case .c4(let diagram)? = try? MermaidDiagramReader.read(source, limits: limits) else { return XCTFail("not read") }
        XCTAssertEqual(diagram.shapes.count, names.count)
        XCTAssertEqual(diagram.relations.count, names.count - 1)
    }
}
