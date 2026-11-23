/**
 * File: ReadingFrontEndCopyTests.swift
 * ------------------------------------
 * Layer: Tests
 * Description: What the reader does before a diagram's type reads it, made faster, gives what it gave: no copy of a
 *              text no pass changes, the bytes one scan finds, and the YAML and front matter read from bytes as they
 *              were read from Swift's scalars, characters and Foundation's search.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class ReadingFrontEndCopyTests: XCTestCase {
    private func storage(_ bytes: [UInt8]) -> UnsafePointer<UInt8>? {
        bytes.withUnsafeBufferPointer(\.baseAddress)
    }

    func testATextNoPassChangesIsReadWithoutACopy() throws {
        for source in ["pie\n  \"A\" : 1\n", "---\ntitle: Pie\n---\npie\n  \"A\" : 1\n", "flowchart TD\n  A[\"#1\"] --> B\n", "graph TD\n  A --> B\n  %% a comment\n"] {
            let (_, cursor) = try MermaidDiagramReader.preprocessed(source)
            XCTAssertEqual(cursor.bytes, Array(source.utf8), source)
            XCTAssertEqual(storage(cursor.bytes), storage(cursor.sourceBytes), source)
        }
    }

    func testEachPassGivesBackItsInputWhenItChangesNothing() {
        let text = Array("graph TD\n  A[\"#1\"] --> B\n  <b>bold</b>\n".utf8)
        XCTAssertEqual(storage(MermaidPreprocessing.normalizedLineBreaks(text)), storage(text))
        XCTAssertEqual(storage(MermaidPreprocessing.singleQuotingTagAttributes(text)), storage(text))
        XCTAssertEqual(storage(MermaidPreprocessing.removingDirectives(from: text, from: 0)), storage(text))
        XCTAssertEqual(storage(MermaidPreprocessing.droppingColorSemicolons(text, from: 0)), storage(text))
    }

    func testTheColorSemicolonsOfBothKeywordsAreDroppedInTheirOrder() {
        let text = Array("style A fill:#f00;B-->C\nclassDef x fill:#0f0;stroke:#000;\nstyle B fill:#fff\n".utf8)
        XCTAssertEqual(String(decoding: MermaidPreprocessing.droppingColorSemicolons(text, from: 0), as: UTF8.self),
                       "style A fill:#f00B-->C\nclassDef x fill:#0f0;stroke:#000\nstyle B fill:#fff\n")
    }

    func testTheBytesFoundAreThoseTheTextHoldsWhereverTheyStand() {
        let marks: [(UInt8, MermaidPreprocessing.FoundBytes)] = [(0x0D, .carriageReturn), (UInt8(ascii: "<"), .lessThan),
                                                                  (UInt8(ascii: ">"), .greaterThan), (UInt8(ascii: "%"), .percent),
                                                                  (UInt8(ascii: "#"), .hash)]
        XCTAssertEqual(MermaidPreprocessing.bytesFound(in: []), [])
        for length in [1, 15, 16, 17, 33, 40] {
            XCTAssertEqual(MermaidPreprocessing.bytesFound(in: Array(repeating: UInt8(ascii: "a"), count: length)), [])
            for position in 0..<length {
                for (byte, found) in marks {
                    var text = Array(repeating: UInt8(ascii: "a"), count: length)
                    text[position] = byte
                    XCTAssertEqual(MermaidPreprocessing.bytesFound(in: text), found, "\(byte) at \(position) of \(length)")
                }
            }
        }
    }

    func testALiteralIsFoundWhereverItStands() {
        let literal = Array("%%{".utf8)
        for length in [3, 16, 19, 40] {
            for position in 0...(length - 3) {
                var text = Array(repeating: UInt8(ascii: "%"), count: length)
                text[position + 2] = UInt8(ascii: "{")
                XCTAssertEqual(MermaidPreprocessing.firstIndex(of: literal, in: text, from: 0), position, "\(position) of \(length)")
            }
            XCTAssertNil(MermaidPreprocessing.firstIndex(of: literal, in: Array(repeating: UInt8(ascii: "%"), count: length), from: 0))
        }
    }

    /// The values the reader gave when it read Unicode scalars, Swift's characters and Foundation's search, which the
    /// bytes are now read to give.
    func testTheYAMLReaderGivesWhatItsCharactersAndFoundationsSearchGave() {
        func read(_ source: String) -> SequenceAttributeValue? { try? SequenceAttributesBlockSyntax.value(of: source) }
        // A sign with a combining mark is one character, which `dropFirst` takes whole.
        XCTAssertEqual(read("x: -\u{301}.inf"), .mapping(["x": .number(-.infinity)]))
        XCTAssertEqual(read("x: -\u{301}0x1F"), .mapping(["x": .number(-31)]))
        XCTAssertEqual(read("x: +\u{301}5"), .mapping(["x": .text("+\u{301}5")]))
        // Foundation's search leaves a carriage return a combining mark follows, and a doubled apostrophe one follows.
        XCTAssertEqual(read("x: a\r\u{301}b"), .mapping(["x": .text("a\r\u{301}b")]))
        XCTAssertEqual(read("k: 'it''\u{301}s'"), .mapping(["k": .text("it''\u{301}s")]))
        XCTAssertEqual(read("k: 'it''s'"), .mapping(["k": .text("it's")]))
        // `\x` takes two scalars after it, the second not a digit here.
        XCTAssertEqual(read("k: \"\\x4éz\""), .mapping(["k": .text("\u{4}z")]))
        // White space beyond ASCII starts a comment, and counts as one scalar of a list item's indentation.
        XCTAssertEqual(read("k: [a,\u{3000}#c\n]"), .mapping(["k": .list([.text("a"), .null])]))
        XCTAssertEqual(read("- \u{3000}a: 1"), .list([.mapping(["a": .number(1)])]))
        XCTAssertEqual(read("a:\n  \u{FEFF}  b"), .mapping(["a": .text("b")]))
        XCTAssertEqual(MermaidYAMLDocument.value(of: "a: [1, {b: c}]\nd: 2.5\n"),
                       .object(["a": .array([.number(1), .object(["b": .text("c")])]), "d": .number(2.5)]))
    }

    /// Pele's front matter as its backward scan found it, now found forward.
    func testTheFrontMatterIsFoundAsTheBackwardScanFoundIt() {
        for (source, body, end) in [("---\n\n---\npie\n", "", 9), ("---\n\n\n---\n", "", 10), ("  ---\n  a: 1\n  ---\npie", "a: 1", 19),
                                    ("---\na: 1\n---\n---\n", "a: 1", 13), ("---  \n\n  \ntitle: x\n---\n", "title: x", 23)] {
            let frontMatter = MermaidFrontMatter.find(in: Array(source.utf8))
            XCTAssertEqual(frontMatter?.body, body, source.debugDescription)
            XCTAssertEqual(frontMatter?.end, end, source.debugDescription)
        }
        XCTAssertNil(MermaidFrontMatter.find(in: Array("---\na: 1\n".utf8)))
        XCTAssertNil(MermaidFrontMatter.find(in: Array("---\n---".utf8)))
    }
}
