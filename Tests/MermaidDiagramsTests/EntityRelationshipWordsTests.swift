/**
 * File: EntityRelationshipWordsTests.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: The entity relationship lexer's cardinalities, lines and keywords told by literals per first byte
 *              against the table of entries tried in order as 0.7.0 tried them: every entry in random cases, followed
 *              by word bytes or not, and random texts of the entries' bytes, each told alike and leaving the cursor alike.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

@testable import MermaidDiagrams
import XCTest

final class EntityRelationshipWordsTests: XCTestCase {
    private var state: UInt64 = 0xE2_3A7D

    private func next(_ bound: Int) -> Int {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Int((state >> 33) % UInt64(bound))
    }

    /// 0.7.0's reading: the parent cardinality, then the first entry of `entries` with the cursor's first byte that
    /// matches, in the table's order.
    private static func referenceToken(_ bytes: inout GraphDiagramBytes) -> EntityRelationshipToken? {
        guard let first = bytes.peek().map(MermaidByte.lowercased) else { return nil }
        if first == UInt8(ascii: "u"), let next = bytes.peek(1), next == MermaidByte.period || next == MermaidByte.hyphen || next == MermaidByte.verticalBar {
            bytes.advance()
            return .cardinality(.parent)
        }
        for entry in EntityRelationshipWords.entries where entry.word[0] == first && bytes.hasCaseInsensitivePrefix(entry.word) {
            if entry.endsAtWordBoundary, let next = bytes.peek(entry.word.count), EntityRelationshipWords.isWordByte(next) { continue }
            bytes.advance(by: entry.word.count)
            return entry.token
        }
        return nil
    }

    /// Both readings of `text` from its start: the token and where the cursor stands after.
    private func assertToldAlike(_ text: [UInt8], file: StaticString = #filePath, line: UInt = #line) {
        text.withUnsafeBufferPointer { buffer in
            var read = GraphDiagramBytes(buffer, position: 0)
            var reference = read
            let token = EntityRelationshipWords.readToken(&read)
            let expected = Self.referenceToken(&reference)
            XCTAssertEqual(token, expected, String(decoding: text, as: UTF8.self).debugDescription, file: file, line: line)
            XCTAssertEqual(read.position, reference.position, String(decoding: text, as: UTF8.self).debugDescription, file: file, line: line)
        }
    }

    func testEveryEntryInAnyCaseFollowedByAnythingIsToldAlike() {
        let followers: [[UInt8]] = [[], Array(" x".utf8), Array("a".utf8), Array("_".utf8), Array("1".utf8), Array("{".utf8), Array("-".utf8), Array("é".utf8)]
        for entry in EntityRelationshipWords.entries {
            for follower in followers {
                for _ in 0..<6 {
                    let cased = entry.word.map { byte in next(2) == 0 ? MermaidByte.uppercased(byte) : byte }
                    assertToldAlike(cased + follower)
                }
            }
        }
    }

    func testRandomTextsOfTheEntriesBytesAreToldAlike() {
        let alphabet = Array(Set(EntityRelationshipWords.entries.flatMap(\.word) + Array("uUOMZ _1x{".utf8)))
        for _ in 0..<40_000 {
            if next(3) == 0 {
                // An entry's word cut, changed or run on.
                var word = EntityRelationshipWords.entries[next(EntityRelationshipWords.entries.count)].word
                switch next(3) {
                case 0: word = Array(word.prefix(1 + next(word.count)))
                case 1: word[next(word.count)] = alphabet[next(alphabet.count)]
                default: word += (0..<next(4)).map { _ in alphabet[next(alphabet.count)] }
                }
                assertToldAlike(word)
            } else {
                assertToldAlike((0..<(1 + next(16))).map { _ in alphabet[next(alphabet.count)] })
            }
        }
    }
}
