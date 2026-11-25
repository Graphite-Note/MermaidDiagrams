/**
 * File: SequenceKeywordAndColorTableTests.swift
 * ---------------------------------------------
 * Layer: Tests
 * Description: The sequence reader finds its keywords on the line's bytes in any case, as it found them through a
 *              lowercased string, and looks CSS's color names up in a table read once, as it looked them up in the
 *              list of names each time.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class SequenceKeywordAndColorTableTests: XCTestCase {
    private func sequence(_ source: String) throws -> SequenceDiagram {
        guard case .sequence(let diagram) = try MermaidDiagramReader.read(source, limits: .standard) else {
            throw XCTSkip("not a sequence diagram")
        }
        return diagram
    }

    /// Each statement's keyword in lower, upper and mixed case reads the same diagram.
    func testKeywordsReadInAnyCase() throws {
        let statements = ["participant A", "actor B as Bob", "box Aqua Front\nparticipant C\nend", "loop Every day\nA->>B: hi\nend",
                          "rect rgb(10, 20, 30)\nA->>B: hi\nend", "opt maybe\nA->>B: hi\nend", "alt yes\nA->>B: a\nelse no\nA->>B: b\nend",
                          "par one\nA->>B: a\nand two\nA->>B: b\nend", "par_over one\nA->>B: a\nend", "critical now\nA->>B: a\noption late\nA->>B: b\nend",
                          "break stop\nA->>B: a\nend", "note over A: hello", "activate A\nA->>B: hi\ndeactivate A", "autonumber\nA->>B: hi",
                          "title The title", "accTitle: short", "accDescr: longer", "create participant D\nA->>D: hi", "destroy B\nA->>B: hi"]
        func cased(_ text: String, upper: Bool, alternating: Bool) -> String {
            var index = 0
            return String(text.map { character -> Character in
                guard character.isLetter else { return character }
                index += 1
                if alternating { return index % 2 == 0 ? Character(character.uppercased()) : Character(character.lowercased()) }
                return upper ? Character(character.uppercased()) : character
            })
        }
        for statement in statements {
            let keywordEnd = statement.firstIndex { character in !(character.isLetter || character == "_") } ?? statement.endIndex
            let keyword = String(statement[..<keywordEnd])
            let rest = String(statement[keywordEnd...])
            let lower = try sequence("sequenceDiagram\n" + statement)
            for variant in [cased(keyword, upper: true, alternating: false), cased(keyword, upper: false, alternating: true)] {
                XCTAssertEqual(try sequence("sequenceDiagram\n" + variant + rest), lower, variant + rest)
            }
        }
    }

    /// A word that only starts like a keyword, or runs into a digit, is a participant's name.
    func testWordsLongerThanAKeywordAreNames() throws {
        let diagram = try sequence("sequenceDiagram\nparticipants->>loops: hi\nnote1->>Note: there")
        XCTAssertEqual(diagram.participants.map(\.identifier), ["participants", "loops", "note1", "Note"])
    }

    /// Every one of CSS's color names, in any case, colors a box as its six hexadecimal digits say.
    func testEveryColorNameColorsABox() throws {
        let names: [(String, UInt32)] = [("aliceblue", 0xF0F8FF), ("Black", 0x000000), ("REBECCAPURPLE", 0x663399), ("darkSlateGrey", 0x2F4F4F),
                                         ("yellowgreen", 0x9ACD32), ("lightgoldenrodyellow", 0xFAFAD2), ("aqua", 0x00FFFF), ("cyan", 0x00FFFF)]
        for (name, value) in names {
            let diagram = try sequence("sequenceDiagram\nbox \(name) Group\nparticipant A\nend")
            let color = try XCTUnwrap(diagram.boxes.first?.color, name)
            XCTAssertEqual(color, SequenceHighlightColor(red: Double(value >> 16 & 0xFF) / 255, green: Double(value >> 8 & 0xFF) / 255,
                                                         blue: Double(value & 0xFF) / 255), name)
        }
        XCTAssertNil(try sequence("sequenceDiagram\nbox notacolor Group\nparticipant A\nend").boxes.first?.color)
    }
}
