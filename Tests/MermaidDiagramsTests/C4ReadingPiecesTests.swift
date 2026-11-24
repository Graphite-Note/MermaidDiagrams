/**
 * File: C4ReadingPiecesTests.swift
 * --------------------------------
 * Layer: Tests
 * Description: The pieces the C4 reader reads on bytes against what they stand in for: keywords found by their bytes,
 *              whole numbers read on bytes, the kinds that take a technology, names interned as 0.7.0's String keys were
 *              equal, and hostile texts read in bounded time.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class C4ReadingPiecesTests: XCTestCase {
    func testEveryKeywordIsFoundByItsBytesAndNothingElseIs() {
        for (word, kind) in C4TokenKind.keywords {
            let found = Array(word.utf8).withUnsafeBufferPointer { bytes in C4Keywords.kind(of: bytes) }
            XCTAssertEqual(found, kind, word)
        }
        for word in ["", "Person_", "person", "Rel_X", "C4context", "UpdateElementStyles", String(repeating: "A", count: 40), "Systemdb"] {
            XCTAssertNil(Array(word.utf8).withUnsafeBufferPointer { bytes in C4Keywords.kind(of: bytes) }, word)
        }
    }

    func testWholeNumbersReadOnBytesAreTheNumbersReadOnTheirString() {
        var texts = ["", " ", "5", "-5", "+7", "  12px", "0x1F", "0X", "0x", "-0x10", "1e3", "abc", "12.5", "\u{00A0}9", "\u{3000}-4", "٣", "1234567890123456789",
                     "99999999999999999999999", "-", "+", "0", "007", "0xg", "\t\n 42", "4\u{2028}2", "１２"]
        var state: UInt64 = 3
        let pieces = ["0", "1", "9", "x", "X", "-", "+", " ", "\t", "a", "f", "F", "g", ".", "e", "\u{00A0}", "中", "8"]
        for _ in 0..<5_000 {
            var text = ""
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            for offset in 0..<Int(state >> 60) { text += pieces[Int((state >> UInt64(offset * 4)) & 0xF) % pieces.count] }
            texts.append(text)
        }
        for text in texts {
            let read = Array(text.utf8).withUnsafeBufferPointer { bytes in JavaScriptInteger.parsed(utf8: bytes) }
            let expected = JavaScriptInteger.parsed(text)
            XCTAssertEqual(read?.bitPattern, expected?.bitPattern, text.debugDescription)
        }
    }

    func testTheKindsThatTakeATechnologyAreThoseNamedForContainersAndComponents() {
        for kind in C4ShapeKind.allCases {
            XCTAssertEqual(kind.takesTechnology, kind.rawValue.contains("container") || kind.rawValue.contains("component"), kind.rawValue)
        }
    }

    func testNamesSwiftHoldsEqualAreOneNameAndOthersAreNot() throws {
        let diagram = try C4Reading.c4("C4Context\nPerson(caf\u{E9}, \"A\")\nPerson(cafe\u{301}, \"B\")\nPerson(K, \"C\")\nPerson(\u{212A}, \"D\")\nPerson(k, \"E\")")
        XCTAssertEqual(diagram.shapes.map(\.element.label), ["B", "D", "E"])
        let ascii = try C4Reading.c4("C4Context\nPerson(a, \"A\")\nPerson(a , \"B\")\nPerson(b, \"C\")\nRel(a, b, \"x\")\nRel(a, b, \"y\")")
        XCTAssertEqual(ascii.shapes.map(\.element.label), ["B", "C"])
        XCTAssertEqual(ascii.relations.map(\.label), ["y"])
    }

    func testHostileTextsAreReadInTimeThatGrowsWithTheirLength() throws {
        let limit = MermaidDiagramLimits.standard.maximumSourceBytes
        func lines(_ line: (Int) -> String) -> String {
            var text = "C4Context\n"
            var index = 0
            while text.utf8.count < limit - 200 {
                text += line(index)
                index += 1
            }
            return text
        }
        let cases = [
            ("many shapes", lines { index in "Person(p\(index), \"P\")\n" }),
            ("many relations", lines { index in "Rel(a\(index % 50), b\(index % 37), \"r\")\n" }),
            ("many named arguments", lines { index in "System(s, $other\(index)=\"v\", $tags=\"t\")\n" }),
            ("deep boundaries", lines { index in "Boundary(b\(index), \"B\") {\n" }),
            ("long argument", "C4Context\nPerson(p, \"" + String(repeating: "word ", count: limit / 6) + "\")"),
            ("many arguments", "C4Context\nPerson(" + String(repeating: "a,", count: limit / 3) + ")"),
            ("direction everywhere", lines { _ in "direction direction direction\n" }),
        ]
        for (name, source) in cases {
            let start = Date()
            _ = try? C4Reading.c4(source)
            XCTAssertLessThan(Date().timeIntervalSince(start), 2.0, name)
        }
    }
}
