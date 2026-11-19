/**
 * File: SequenceParticipantAttributesTests.swift
 * ----------------------------------------------
 * Layer: Tests
 * Description: A sequence participant's `@{ … }` attributes read as YAML the way Mermaid and Pele read them: the type,
 *              the alias, JavaScript's text and truth of their values, and the texts refused.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class SequenceParticipantAttributesTests: XCTestCase {
    private func attributes(_ text: String) -> SequenceParticipantAttributes? {
        SequenceParticipantAttributes(text: text)
    }

    func testOneLineIsAFlowMappingWithQuotedOrPlainKeysAndValues() {
        XCTAssertEqual(attributes(" \"type\" : \"database\" ")?.type, "database")
        XCTAssertEqual(attributes(" type: \"database\" ")?.type, "database")
        XCTAssertEqual(attributes(" \"type\" : 'database' ")?.type, "database")
        XCTAssertEqual(attributes(" type: 'database' ")?.type, "database")
        XCTAssertEqual(attributes(" \"type\" : \"database\"    ")?.type, "database")
        let both = attributes(" type: boundary, alias: Public API ")
        XCTAssertEqual(both?.type, "boundary")
        XCTAssertEqual(both?.alias, "Public API")
        XCTAssertEqual(attributes("\"alias\": \"It's\", 'type': 'it''s'")?.type, "it's")
        XCTAssertEqual(attributes("")?.type, nil, "@{} holds an empty mapping")
    }

    func testValuesBecomeTextAsJavaScriptWritesThem() {
        XCTAssertEqual(attributes("alias: 1.50")?.alias, "1.5")
        XCTAssertEqual(attributes("alias: 0x1F")?.alias, "31")
        XCTAssertEqual(attributes("alias: true")?.alias, "true")
        XCTAssertEqual(attributes("alias: [a, b]")?.alias, "a,b")
        XCTAssertEqual(attributes("alias: {a: 1}")?.alias, "[object Object]")
        XCTAssertEqual(attributes("alias: \"Tab\\there \\u00e9\"")?.alias, "Tab\there é")
        XCTAssertEqual(attributes("type: 5")?.type, "5")
    }

    func testAnAliasThatIsNotTrueAndANullTypeAreIgnored() {
        for written in ["alias: 0", "alias: false", "alias: ''", "alias: ~", "alias: null", "alias:"] {
            XCTAssertNotNil(attributes(written), written)
            XCTAssertNil(attributes(written)?.alias, written)
        }
        XCTAssertNil(attributes("type: ~")?.type)
        XCTAssertNil(attributes("type: null, alias: x")?.type)
    }

    func testSeveralLinesAreABlockMappingAndAMoreIndentedLineContinuesAPlainValue() {
        let block = attributes("\ntype: database\nalias: Store\n")
        XCTAssertEqual(block?.type, "database")
        XCTAssertEqual(block?.alias, "Store")
        // Trimming leaves the first line unindented and the next indented, so Pele (and js-yaml) read the next line as
        // the plain value's continuation.
        XCTAssertEqual(attributes("\n    type: database\n    alias: Store\n")?.type, "database alias: Store")
        XCTAssertEqual(attributes("type: database\nalias: |\n  Line one\n  Line two")?.alias, "Line one\nLine two\n")
        XCTAssertEqual(attributes("type: database\nalias: >-\n  Folded\n  text")?.alias, "Folded text")
        XCTAssertEqual(attributes("type: database # a comment\nalias: \"Store\"")?.type, "database")
        XCTAssertEqual(attributes("type: queue\nalias: [one,\n  two]")?.alias, "one,two", "A flow value runs over several lines")
        XCTAssertEqual(attributes("type: queue\nlist:\n  - a\n  - b\nalias: x")?.alias, "x")
    }

    func testTextThatIsNotYAMLIsRefused() {
        XCTAssertNil(attributes(" \"type: \"entity\" "), "An unclosed quote then text without a comma")
        XCTAssertNil(attributes(" \"type\" \"control\" "), "No colon: two entries without a comma")
        XCTAssertNil(attributes("type: \"a\\qb\""), "An unknown escape")
        XCTAssertNil(attributes("type: [a, b"), "An unclosed list")
        XCTAssertNil(attributes("type: a,, alias: b"), "Two commas")
        XCTAssertNil(attributes("type: database\n  alias: Store\nother"), "A line that is no key")
        XCTAssertNil(attributes("type: x\nalias:\n\tnested: y"), "A tab for indentation")
        XCTAssertNil(attributes(String(repeating: "[", count: 100) + String(repeating: "]", count: 100)), "Nested deeper than 64")
    }

    func testTheTypeNamesTheShapeAndAnyOtherTextIsAPlainParticipant() throws {
        let diagram = try SequenceReading.sequence("""
            sequenceDiagram
            participant A@{ "type": "boundary" }
            participant B@{ "type": "control" }
            participant C@{ "type": "entity" }
            participant D@{ "type": "database" }
            participant E@{ "type": "collections" }
            participant F@{ "type": "queue" }
            participant G@{ "type": "actor" }
            actor H@{ "type": "Database" }
            actor I@{ "alias": "Only an alias" }
            participant J@{ "type": "queue", "alias": "J" } as Jay
            """)
        XCTAssertEqual(diagram.participants.map(\.kind), [.boundary, .control, .entity, .database, .collections, .queue, .actor, .participant, .actor, .queue])
        XCTAssertEqual(diagram.participants[8].label, DiagramLabel("Only an alias"))
        XCTAssertEqual(diagram.participants[9].label, DiagramLabel("Jay"), "An alias written after the attributes comes first")
        XCTAssertEqual(SequenceReading.readError("sequenceDiagram\nparticipant A@{ type: \"x }"),
                       .invalidSyntax(line: 2, problem: .sequence(.invalidParticipantAttributes(identifier: "A"))))
    }

    func testAnAttributesAliasEqualToTheIdentifierGivesWayToTheAttributes() throws {
        let diagram = try SequenceReading.sequence("sequenceDiagram\nparticipant API@{ \"alias\": \"Public API\" } as API")
        XCTAssertEqual(diagram.participants[0].label, DiagramLabel("Public API"))
    }

    func testARedeclarationWithOnlyATypeChangesNothing() throws {
        let diagram = try SequenceReading.sequence("sequenceDiagram\nA->>B: hi\nparticipant A@{ \"type\": \"database\" }")
        XCTAssertEqual(diagram.participants[0].kind, .participant, "As Mermaid's addActor returns for a name without a description")
    }
}
