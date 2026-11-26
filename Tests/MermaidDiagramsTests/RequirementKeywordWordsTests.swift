/**
 * File: RequirementKeywordWordsTests.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: The requirement lexer's keywords told from packed bytes against 0.7.0's dictionary of lowercased words:
 *              every keyword in random cases, at the end of a text and inside one, and random words of word characters
 *              of every length, each told alike; and its bytes told by masks, and its whitespace runs, against 0.7.0's
 *              tests of them for every byte.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 26/11/2026
 */

@testable import MermaidDiagrams
import XCTest

final class RequirementKeywordWordsTests: XCTestCase {
    private var state: UInt64 = 0x7E9_51A1

    private func next(_ bound: Int) -> Int {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Int((state >> 33) % UInt64(bound))
    }

    /// The keyword 0.7.0 found for a word: its lowercased String looked up.
    private func referenceKeyword(_ word: [UInt8]) -> RequirementTokenKind? {
        word.count <= RequirementKeywords.longestKeywordLength ? RequirementKeywords.byLowercaseWord[String(decoding: word, as: UTF8.self).lowercased()] : nil
    }

    /// The keyword the packed comparison finds for `word`, written after `prefix` and before `suffix` in one text.
    private func keyword(_ word: [UInt8], prefix: [UInt8], suffix: [UInt8]) -> RequirementTokenKind? {
        let text = prefix + word + suffix
        return text.withUnsafeBufferPointer { bytes in RequirementKeywords.keyword(from: prefix.count, to: prefix.count + word.count, in: bytes) }
    }

    func testEveryKeywordInAnyCaseIsToldWhereverItStands() {
        for (word, kind) in RequirementKeywords.byLowercaseWord {
            for _ in 0..<12 {
                let cased = word.utf8.map { byte in next(2) == 0 ? MermaidByte.uppercased(byte) : byte }
                let prefix = [UInt8](repeating: UInt8(ascii: "x"), count: next(3) * 7)
                let suffix = next(2) == 0 ? [] : [UInt8](repeating: UInt8(ascii: " "), count: 1 + next(20))
                XCTAssertEqual(keyword(cased, prefix: prefix, suffix: suffix), kind, word)
            }
        }
    }

    func testRandomWordsAreToldAsTheDictionaryTellsThem() {
        let alphabet = Array("aeiorstcdlmnpqfyvhxABDEIRSTCLMNPFYV0189_".utf8)
        let keywords = Array(RequirementKeywords.byLowercaseWord.keys)
        for round in 0..<40_000 {
            var word: [UInt8]
            if round % 4 == 0 {
                // A keyword with one byte changed, added or taken off.
                word = Array(keywords[next(keywords.count)].utf8)
                switch next(3) {
                case 0: word[next(word.count)] = alphabet[next(alphabet.count)]
                case 1: word.insert(alphabet[next(alphabet.count)], at: next(word.count + 1))
                default: word.remove(at: next(word.count))
                }
            } else {
                word = (0..<(1 + next(26))).map { _ in alphabet[next(alphabet.count)] }
            }
            guard !word.isEmpty else { continue }
            let suffix = [UInt8](repeating: UInt8(ascii: "z"), count: next(10))
            XCTAssertEqual(keyword(word, prefix: [], suffix: suffix), referenceKeyword(word), String(decoding: word, as: UTF8.self))
        }
    }

    /// Every byte is a word byte and ends an unquoted text exactly where 0.7.0's comparisons said so.
    func testEveryByteIsToldAsZeroSevenToldIt() {
        for value in 0...255 {
            let byte = UInt8(value)
            let isWordByte = MermaidByte.isLetter(byte) || MermaidByte.isDigit(byte) || byte == MermaidByte.underscore
            XCTAssertEqual(RequirementLexer.isWordByte(byte), isWordByte, "\(value)")
            let endsUnquotedText = [MermaidByte.colon, MermaidByte.comma, MermaidByte.carriageReturn, MermaidByte.newline, MermaidByte.openingBrace,
                                    MermaidByte.lessThan, MermaidByte.greaterThan, MermaidByte.hyphen, MermaidByte.equals].contains(byte)
            XCTAssertEqual(RequirementLexer.endsUnquotedText(byte), endsUnquotedText, "\(value)")
        }
    }

    /// Runs of white space, ASCII and beyond (no-break spaces, ideographic spaces, line separators), mixed with other
    /// bytes, end where JavaScript's whitespace ends them.
    func testWhitespaceRunsEndWhereJavaScriptsEndThem() {
        let pieces: [[UInt8]] = [[0x20], [0x09], [0x0A], [0x0B], [0x0C], [0x0D], Array("\u{A0}".utf8), Array("\u{3000}".utf8), Array("\u{2028}".utf8),
                                 Array("\u{2009}".utf8), Array("\u{FEFF}".utf8), Array("é".utf8), Array("x".utf8), [0x80], [0xC1], Array("\u{1680}".utf8)]
        for _ in 0..<20_000 {
            let text = (0..<(1 + next(10))).flatMap { _ in pieces[next(pieces.count)] }
            text.withUnsafeBufferPointer { bytes in
                for start in 0..<bytes.count {
                    XCTAssertEqual(RequirementLexer.endOfWhitespace(in: bytes, from: start), JavaScriptWhitespace.endOfRun(in: bytes, from: start), "\(text)")
                }
            }
        }
    }
}
