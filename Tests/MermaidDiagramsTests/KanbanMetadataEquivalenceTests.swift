/**
 * File: KanbanMetadataEquivalenceTests.swift
 * ------------------------------------------
 * Layer: Tests
 * Description: A kanban node's metadata read on its bytes (KanbanCardFields) gives the fields 0.7.0's whole YAML reader
 *              gave (ReferenceKanbanCardMetadata), or refuses the same texts, on tens of thousands of generated metadata
 *              texts; the board reader gives 0.7.0's board (ReferenceKanbanParser) or its error on every corpus, the
 *              specification's texts, mutated texts and random boards; long and many-entried metadata stays linear.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class KanbanMetadataEquivalenceTests: XCTestCase {
    private static let keywords: Set<String> = ["kanban"]

    /// The fields both readers give, as one comparable text, or nil for a refusal.
    private func bytesFields(_ text: String) -> [String?]? {
        guard let fields = try? KanbanCardFields(metadata: text) else { return nil }
        return [fields.label, fields.icon, fields.ticket, fields.assigned, fields.priority, fields.shape]
    }

    private func referenceFields(_ text: String) -> [String?]? {
        guard let fields = try? ReferenceKanbanCardMetadata(text: text).fields else { return nil }
        return ["label", "icon", "ticket", "assigned", "priority", "shape"].map { key in fields[key] }
    }

    func testGeneratedMetadataGivesZeroSevensFieldsOrItsRefusal() {
        let keys = ["label", "icon", "ticket", "assigned", "priority", "shape", "other", "Label", "label ", "'label'", "\"ticket\"", "ti-cket", "a_b",
                    "1", "true", "é", "", "label\t"]
        let colons = [": ", ":", " : ", ":\t", ":  ", ":x", ":,", " "]
        let values = ["'High'", "Very Low", "knsv", "'it''s'", "\"a\\\"b\"", "\"tab\\there\"", "0", "1.50", "true", "false", "~", "null", "''", "\"\"",
                      "0x1F", "-0o17", "1e3", ".inf", "é", "x é ", "\u{A0}y\u{A0}", "[a]", "{b: c}", "a}b", "#x", "x #c", "x#c", "a: b", "\\t", "rect",
                      "Rect", "my_shape", "'a}b'", "\"a}b\"", "'open", "\"open", "MC-2037", "  spaced  ", "a\rb", "\u{0B}v", "[]", "'''x'", "\"q\" z",
                      "'q' z", "<br/>", "https://example.com/x", ""]
        let separators = [", ", ",", ",,", " , ", " ,\t", ";", " "]
        var state: UInt64 = 0x4B_A1_BA_17
        func below(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(bound))
        }
        // Every piece, then the pieces of the subset read on bytes, a few others among them.
        let readableKeys = Array(keys.prefix(7)) + ["ti-cket", "a_b", "1", "true"]
        let readableValues = values.filter { value in !value.contains("#") && !value.contains("[") && !value.contains("{") && !value.contains("\\") }
        var readOnBytes = 0
        for round in 0..<60_000 {
            let isReadable = round >= 30_000
            let roundKeys = isReadable ? readableKeys : keys
            let roundColons = isReadable ? [": ", " : ", ":\t", ":  ", ":"] : colons
            let roundValues = isReadable ? readableValues : values
            let roundSeparators = isReadable ? [", ", ",", " , ", " ,\t", ",,"] : separators
            var text = [" ", "", "  ", "\t"][below(4)]
            for entry in 0..<(1 + below(5)) {
                if entry > 0 { text += roundSeparators[below(roundSeparators.count)] }
                text += roundKeys[below(roundKeys.count)] + roundColons[below(roundColons.count)] + roundValues[below(roundValues.count)]
            }
            text += ["", " ", ",", ", ", "\t"][below(5)]
            if round % 7 == 0 { text = text.replacingOccurrences(of: ", ", with: "\n  ") }
            if round % 11 == 0 { text = "\n  " + text.replacingOccurrences(of: ", ", with: "\n  ") + "\n" }
            XCTAssertEqual(bytesFields(text), referenceFields(text), text.debugDescription)
            if KanbanCardFields.fieldsOnBytes(text) != nil { readOnBytes += 1 }
        }
        XCTAssertGreaterThan(readOnBytes, 8_000, "the texts the bytes reader takes")
    }

    func testDocumentationMetadataIsReadOnItsBytesAsZeroSevenReadIt() throws {
        for text in [" ticket: MC-2037, assigned: 'knsv', priority: 'High' ", " assigned: 'knsv' ", " priority: 'Very Low', assigned: knsv ",
                     " ticket: MC-2036, priority: 'Very High'", " label: \"Label\", icon: star, shape: rect ", " shape: Rect ", " shape: my_shape "] {
            XCTAssertEqual(bytesFields(text), referenceFields(text), text)
            XCTAssertNotNil(KanbanCardFields.fieldsOnBytes(text), "read on its bytes: \(text)")
        }
    }

    func testEveryCorpusAndMutatedBoardIsReadAsZeroSevenReadIt() throws {
        let sources = try ChartReadingEquivalence.corpusSources(keywords: Self.keywords) + Self.specificationTexts
        assertAgree(sources, atLeast: 3 + Self.specificationTexts.count)
        var mutations = ChartTextMutations(seed: 0x4B_A1_BA_18)
        var mutated: [String] = []
        for source in sources {
            for _ in 0..<150 { mutated.append(mutations.mutated(source)) }
            for _ in 0..<150 { mutated.append(mutations.spliced(source)) }
        }
        assertAgree(mutated, atLeast: 3_000)
    }

    func testRandomBoardsWithMetadataAreReadAsZeroSevenReadThem() {
        let metadata = ["", "@{ ticket: T-1 }", "@{ priority: 'High', assigned: me }", "@{label: \"New\"}", "@{ icon: star }", "@{ shape: Rect }",
                        "@{ shape: my_shape }", "@{ shape: circle }", "@{ a: 1,, b: 2 }", "@{ label: 'open }", "@{\n  ticket: T-2\n  priority: Low\n}",
                        "@{ priority: [High] }", "@{ label: \"two\nlines\" }", "@{ label: x # c }", "@{ label: '' }"]
        var state: UInt64 = 0x4B_A1_BA_19
        func below(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(bound))
        }
        var sources: [String] = []
        for _ in 0..<2_000 {
            var lines = ["kanban"]
            for column in 0..<(1 + below(3)) {
                lines.append("  c\(column)[Column \(column)]" + (below(4) == 0 ? metadata[below(metadata.count)] : ""))
                for card in 0..<below(4) { lines.append("    k\(column)_\(card)[Card \(card)]" + metadata[below(metadata.count)]) }
            }
            sources.append(lines.joined(separator: "\n"))
        }
        assertAgree(sources, atLeast: 2_000)
    }

    func testLongAndManyEntriedMetadataIsReadInLinearTime() throws {
        let many = (0..<20_000).map { index in "k\(index): 'v\(index)'" }.joined(separator: ", ") + ", ticket: T"
        let long = " label: " + String(repeating: "x", count: 400_000)
        let clock = ContinuousClock()
        let start = clock.now
        XCTAssertEqual(try KanbanCardFields(metadata: many).ticket, "T")
        XCTAssertEqual(try KanbanCardFields(metadata: long).label?.utf8.count, 400_000)
        XCTAssertNil(try? KanbanCardFields(metadata: " a: " + String(repeating: "[", count: 20_000)))
        XCTAssertLessThan(clock.now - start, .seconds(2))
        let entries = (0..<2_000).map { index in "k\(index): v\(index)" }.joined(separator: ", ") + ", ticket: T"
        let board = try KanbanReading.board("kanban\n  c[C]\n    k[K]@{" + entries + " }")
        XCTAssertEqual(board.columns.first?.cards.first?.ticket, "T")
    }

    private func assertAgree(_ sources: [String], atLeast count: Int, file: StaticString = #filePath, line: UInt = #line) {
        var compared = 0
        for source in sources {
            guard let agrees = ChartReadingEquivalence.agree(source, keywords: Self.keywords, read: { (cursor, _) throws(MermaidDiagramReadError) in
                try KanbanParser.parse(cursor, limits: .standard)
            }, reference: { (cursor, _) throws(MermaidDiagramReadError) in
                try ReferenceKanbanParser.parse(cursor, limits: .standard)
            }) else { continue }
            XCTAssertTrue(agrees, "\(source.prefix(300))", file: file, line: line)
            compared += 1
        }
        XCTAssertGreaterThanOrEqual(compared, count, file: file, line: line)
    }

    /// Mermaid's kanban documentation and specification, with metadata of every form the reader takes.
    static let specificationTexts = [
        "kanban\n  Todo\n    [Create Documentation]\n    docs[Create Blog about the new diagram]\n",
        "kanban\n  id1[Todo]\n    id2[Card]@{ ticket: MC-2038, assigned: 'K.Sveidqvist', priority: 'High' }\n",
        "kanban\n  id1[Todo]\n    id2[Card]@{\n      assigned: knsv\n      priority: Very High\n    }\n",
        "kanban\n  id1[Todo]\n    id2[Card]@{ label: \"Relabelled\", icon: star }\n",
        "kanban\n  id1[Todo]\n    id2[Card]@{ shape: Rect }\n",
        "kanban\n  id1[Todo]\n    id2[Card]@{ shape: my_shape }\n",
        "kanban\n  id1[Todo]\n    id2[Card]@{ a: 1,, b: 2 }\n",
        "kanban\n  id1[Todo]\n    id2[Card]@{ priority: [High], ticket: {a: 1} }\n",
        "kanban\n  id1[Todo]\n    id2[Card]@{ label: \"two\n lines\" }\n",
        "kanban\n  id1[Todo]\n    id2[Card]@{ label: 'it''s', assigned: \"a\\tb\" }\n",
        "kanban\n  id1[Todo]\n    id2[Card]@{ priority: 0, ticket: false, assigned: ~ }\n",
        "kanban\n  id1[Todo]\n    id2[Card]@{ priority: low, ticket: 0x1F }\n",
        "kanban\r\n  id1[Todo]\r\n    id2[Card]@{ ticket: T-1 }\r\n",
    ]
}
