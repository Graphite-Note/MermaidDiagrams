/**
 * File: SequenceParticipantAttributesFastPathTests.swift
 * ------------------------------------------------------
 * Layer: Tests
 * Description: A participant's attributes read on their bytes give the type and alias the YAML reader gives, for every
 *              text of quoted keys and values put together at random and every attribute text of the corpora.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class SequenceParticipantAttributesFastPathTests: XCTestCase {
    private func assertSameAsYAML(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(SequenceParticipantAttributes(text: text), SequenceParticipantAttributes(yamlText: text), text.debugDescription,
                       file: file, line: line)
    }

    /// Texts of quoted and unquoted keys and values, blanks, commas, repeated keys and the bytes the fast path refuses,
    /// among them the backslash of a YAML escape (`\n`, `\\`, `\u0041`), which the YAML reader turns into another character.
    func testRandomAttributeTextsReadAsTheYAMLReaderReadsThem() {
        let keys = ["\"type\"", "\"alias\"", "\"other\"", "type", "alias", "\"Type\"", "\"\"", "'type'"]
        let values = ["\"boundary\"", "\"database\"", "\"\"", "\"Public API\"", "\"a: b\"", "\"#x\"", "\"[x]\"", "\"a\\\"b\"", "\"tab\there\"", "\"é\"",
                      "\"line\\nbreak\"", "\"C:\\\\x\"", "\"\\u0041\"", "\"end\\\\\"", "\"\\t\"",
                      "control", "null", "0", "true", "\"null\"", "\"0\"", "'q'", "[1, 2]", "{a: 1}", "\"  spaced  \""]
        let blanks = ["", " ", "  ", "\t", " \t "]
        var state: UInt64 = 0x5E_A77_12
        func below(_ bound: Int) -> Int {
            state &+= 0x9E37_79B9_7F4A_7C15
            var mixed = state
            mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
            mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
            return Int((mixed ^ (mixed >> 31)) % UInt64(bound))
        }
        for _ in 0..<5_000 {
            var text = blanks[below(blanks.count)]
            for pair in 0..<(1 + below(3)) {
                if pair > 0 { text += [",", ", ", " ,", ",,", ";"][below(5)] }
                text += keys[below(keys.count)] + blanks[below(blanks.count)] + [":", ":", " :", ""][below(4)] + blanks[below(blanks.count)]
                text += values[below(values.count)]
            }
            text += [blanks[below(blanks.count)], ",", "\n", ""][below(4)]
            assertSameAsYAML(text)
        }
    }

    /// Every participant's attributes in the corpora, and the documented forms.
    func testDocumentedAndCorpusAttributesReadAsTheYAMLReaderReadsThem() throws {
        for text in [" \"type\" : \"boundary\" ", "\"type\": \"database\", \"alias\": \"Store\"", "\"alias\": \"\"", "\"alias\": \"A\", \"type\": \"actor\"",
                     "\"type\": \"\"", "", " ", "\"type\": \"queue\",", "\"type\": \"queue\" \"alias\": \"x\"",
                     "\"alias\": \"Line\\nBreak\"", "\"type\": \"\\x41ctor\"", "\"alias\": \"back\\\\slash\""] {
            assertSameAsYAML(text)
        }
        var attributeTexts: [String] = []
        for source in try OutputDigest.corpora().flatMap(\.sources) {
            var rest = Substring(source)
            while let opening = rest.range(of: "@{") {
                let after = rest[opening.upperBound...]
                guard let closing = after.firstIndex(of: "}") else { break }
                attributeTexts.append(String(after[..<closing]))
                rest = after[closing...]
            }
        }
        XCTAssertGreaterThan(attributeTexts.count, 10)
        for text in attributeTexts { assertSameAsYAML(text) }
    }
}
