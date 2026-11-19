/**
 * File: SequenceStatementsMermaidSpecTests.swift
 * ----------------------------------------------
 * Layer: Tests
 * Description: The cases of Mermaid 12.1.0's sequence specs for central connections, participant attributes and
 *              types, boxes, created and destroyed participants and the menu keywords used as names, as Pele's
 *              compatibility suite keeps them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

/// The cases of `sequenceDiagram.spec.js` ("Central Connection Parsing", "when parsing extended participant syntax",
/// "participant type parsing", boxes, creation and destruction) and of `keywordActors.spec.ts` that read the
/// statements laid out since sequence diagrams draw boxes, shapes, lifetimes and central connections, with their inputs
/// as Pele's compatibility suite keeps them (`tests/compat/sequence`, MIT). Mermaid's `type` and `description` of an
/// actor are `SequenceParticipant.kind` and `label` here; its `centralConnection` is the message's two flags.
final class SequenceStatementsMermaidSpecTests: XCTestCase {
    private func read(_ source: String) throws -> SequenceDiagram {
        try SequenceReading.sequence(source)
    }

    private func participant(_ diagram: SequenceDiagram, _ identifier: String) -> SequenceParticipant? {
        diagram.participants.first { participant in participant.identifier == identifier }
    }

    /// An actor's `type` and `description`, as Mermaid's spec checks them.
    private func typeAndDescription(_ diagram: SequenceDiagram, _ identifier: String) -> (SequenceParticipantKind?, [String]?) {
        let found = participant(diagram, identifier)
        return (found?.kind, found?.label.lines)
    }

    /// Each message's source, target, central connections (`DUAL`, `CENTRAL_CONNECTION`, `CENTRAL_CONNECTION_REVERSE`
    /// or nil) and stroke.
    private func connections(_ diagram: SequenceDiagram) -> [String] {
        diagram.messages.map { message in
            let connection = switch (message.hasCentralConnectionAtSource, message.hasCentralConnectionAtTarget) {
            case (true, true): "DUAL"
            case (false, true): "CENTRAL_CONNECTION"
            case (true, false): "CENTRAL_CONNECTION_REVERSE"
            case (false, false): "none"
            }
            let source = diagram.participants[message.sourceIndex].identifier
            let target = diagram.participants[message.targetIndex].identifier
            return "\(source)->\(target) \(connection) \(message.arrow.stroke) \(message.arrow.head)\(message.arrow.pointsBothWays ? " both" : "")"
        }
    }

    // MARK: Central Connection Parsing

    func testShouldParseEveryCentralConnectionSyntax() throws {
        let cases: [(String, String)] = [
            ("()->>()", "Alice->Bob DUAL solid arrow"), ("()-->>()", "Alice->Bob DUAL dotted arrow"), ("->>()", "Alice->Bob CENTRAL_CONNECTION solid arrow"),
            ("()-->>", "Alice->Bob CENTRAL_CONNECTION_REVERSE dotted arrow"), ("()->>", "Alice->Bob CENTRAL_CONNECTION_REVERSE solid arrow"),
            ("()<<-->>()", "Alice->Bob DUAL dotted arrow both"), ("()<<->>()", "Alice->Bob DUAL solid arrow both"),
        ]
        for (arrow, expected) in cases {
            let diagram = try read("\n        sequenceDiagram\n        participant Alice\n        participant Bob\n        Alice \(arrow) Bob: Hello Bob, how are you?\n      ")
            XCTAssertEqual(connections(diagram), [expected], arrow)
            XCTAssertEqual(diagram.messages.map(\.text.lines), [["Hello Bob, how are you?"]], arrow)
            XCTAssertEqual(diagram.events.count, 1, "\(arrow): a central connection starts no activation")
        }
    }

    func testShouldHandleMultipleCentralConnectionTypesInOneDiagram() throws {
        let diagram = try read("""

                    sequenceDiagram
                    participant Alice
                    participant Bob
                    participant Charlie
                    Alice ()->>() Bob: Message 1
                    Bob ()-->> Charlie: Message 2
                    Charlie ()<<-->>() Alice: Message 3
            """)
        XCTAssertEqual(connections(diagram), ["Alice->Bob DUAL solid arrow", "Bob->Charlie CENTRAL_CONNECTION_REVERSE dotted arrow",
                                              "Charlie->Alice DUAL dotted arrow both"])
    }

    func testShouldHandleCentralConnectionsWithDifferentArrowTypes() throws {
        let diagram = try read("\n        sequenceDiagram\n        participant Alice\n        participant Bob\n        Alice ()-x() Bob: Cross message\n        Alice ()--x() Bob: Dotted cross message\n      ")
        XCTAssertEqual(connections(diagram), ["Alice->Bob DUAL solid cross", "Alice->Bob DUAL dotted cross"])
    }

    func testShouldNotBreakExistingParsingWithoutCentralConnections() throws {
        let diagram = try read("""

                    sequenceDiagram
                    participant Alice
                    participant Bob
                    Alice ->> Bob: Normal message
                    Bob -->> Alice: Normal dotted message
                    Alice -x Bob: Normal cross message
            """)
        XCTAssertEqual(connections(diagram), ["Alice->Bob none solid arrow", "Bob->Alice none dotted arrow", "Alice->Bob none solid cross"])
    }

    /// Mermaid's grammar takes `+` or `-` after the arrow only without a connection at the source.
    func testAnActivationMarkAfterASourceConnectionIsRefused() {
        XCTAssertNotNil(SequenceReading.readError("sequenceDiagram\nAlice ()->>+ Bob: hi"))
        XCTAssertNotNil(SequenceReading.readError("sequenceDiagram\nAlice ()->>- Bob: hi"))
        XCTAssertNil(SequenceReading.readError("sequenceDiagram\nAlice ->>+ Bob: hi"))
    }

    // MARK: when parsing extended participant syntax

    func testShouldParseParticipantsWithDifferentQuoteStylesAndWhitespace() throws {
        let diagram = try read("""

              sequenceDiagram
                  participant Alice@{ "type" : "database" }
                  participant Bob@{ "type" : "database" }
                  participant Carl@{ type: "database" }
                  participant David@{ "type" : 'database' }
                  participant Eve@{ type: 'database' }
                  participant Favela@{ "type" : "database"    }
                  Bob->>+Alice: Hi Alice
                  Alice->>+Bob: Hi Bob
            """)
        for name in ["Alice", "Bob", "Carl", "David", "Eve", "Favela"] {
            XCTAssertEqual(participant(diagram, name)?.kind, .database, name)
            XCTAssertEqual(participant(diagram, name)?.label.lines, [name], name)
        }
        XCTAssertEqual(diagram.events.count, 4, "2 messages + 2 activation messages")
        XCTAssertEqual(connections(diagram), ["Bob->Alice none solid arrow", "Alice->Bob none solid arrow"])
    }

    func testShouldParseAParticipantConfigObjectSeparatedFromTheNameByWhitespace() throws {
        let diagram = try read("\n  sequenceDiagram\n      participant Gina@{ \"type\" : \"database\" }\n      participant Harry @{ \"type\" : \"database\" }\n    ")
        XCTAssertEqual(typeAndDescription(diagram, "Gina").0, .database)
        XCTAssertEqual(typeAndDescription(diagram, "Harry").1, ["Harry"])
        XCTAssertEqual(typeAndDescription(diagram, "Harry").0, .database)
    }

    func testShouldParseMixedParticipantTypesWithExtendedSyntax() throws {
        let diagram = try read("""

                sequenceDiagram
                    participant lead
                    participant dsa@{ "type" : "queue" }
                    API->>+Database: getUserb
                    Database-->>-API: userb
                    dsa --> Database: hello
            """)
        XCTAssertEqual(diagram.participantIdentifiers, ["lead", "dsa", "API", "Database"])
        XCTAssertEqual(diagram.participants.map(\.kind), [.participant, .queue, .participant, .participant])
        XCTAssertEqual(diagram.participants.map(\.label.lines), [["lead"], ["dsa"], ["API"], ["Database"]])
        XCTAssertEqual(diagram.events.count, 5, "3 messages + 2 activation messages")
        XCTAssertEqual(diagram.messages.map(\.text.lines), [["getUserb"], ["userb"], ["hello"]])
    }

    func testShouldParseHyphenatedNamesWithAnAttachedConfigObject() throws {
        let diagram = try read("""

                sequenceDiagram
                    actor lead-actor@{ "type" : "database" }
                    participant order-svc@{ "type" : "queue" }
                    actor kebab-case@{ "type" : "control" } as Kebab-Cased
                    participant web-ui@{ "type" : "entity" } as Web UI
            """)
        XCTAssertEqual(diagram.participants.map(\.kind), [.database, .queue, .control, .entity])
        XCTAssertEqual(diagram.participants.map(\.label.lines), [["lead-actor"], ["order-svc"], ["Kebab-Cased"], ["Web UI"]])
    }

    func testShouldFailForMalformedAttributes() {
        let malformed = "\n    sequenceDiagram\n      participant D@{ \"type: \"entity\" }\n      participant E@{ \"type\": \"dat\n      abase }\n  "
        XCTAssertNotNil(SequenceReading.readError(malformed))
        XCTAssertNotNil(SequenceReading.readError("\n    sequenceDiagram\n      participant C@{ \"type\" \"control\" }\n      C ->> C: action\n  "),
                        "missing colon separator")
        XCTAssertNotNil(SequenceReading.readError("\n    sequenceDiagram\n      participant E@{ \"type\": \"entity\"\n      E ->> E: process\n  "),
                        "missing closing brace")
    }

    // MARK: participant type parsing

    func testShouldParseEachParticipantType() throws {
        let cases: [(String, String, SequenceParticipantKind)] = [
            ("boundary", "boundary", .boundary), ("C", "control", .control), ("E", "entity", .entity), ("D", "database", .database),
            ("L", "collections", .collections), ("Q", "queue", .queue), ("A", "queue", .queue), ("P", "database", .database),
        ]
        for (name, type, kind) in cases {
            let diagram = try read("\n      sequenceDiagram\n      participant \(name)@{ \"type\" : \"\(type)\" }\n      \(name)->\(name): test \n  ")
            XCTAssertEqual(participant(diagram, name)?.kind, kind, name)
            XCTAssertEqual(participant(diagram, name)?.label.lines, [name], name)
        }
        let pair = try read("\n      sequenceDiagram\n        participant Alice@{ \"type\" : \"collections\" }\n        participant Bob@{ \"type\" : \"control\" }\n        Alice->>Bob: Hello Bob, how are you?\n  ")
        XCTAssertEqual(pair.participants.map(\.kind), [.collections, .control])
    }

    func testShouldParseAttributesWithAnAlias() throws {
        let stereotypes = try read("""

                  sequenceDiagram
                  participant Alice@{ "type" : "boundary" } as Public API
                  participant Bob@{ "type" : "control" } as Controller
                  actor A@{ "type" : "database" } AS Database Server
                  actor B@{ "type" : "queue" } as Message Queue
                  participant API@{ "type" : "boundary" } AS Public API
                  Alice->>Bob: Request
            """)
        XCTAssertEqual(stereotypes.participants.map(\.kind), [.boundary, .control, .database, .queue, .boundary])
        XCTAssertEqual(stereotypes.participants.map(\.label.lines), [["Public API"], ["Controller"], ["Database Server"], ["Message Queue"], ["Public API"]])
        let inline = try read("""

                  sequenceDiagram
                  participant API@{ "type" : "boundary", "alias": "Public API" }
                  participant Auth@{ "type" : "control", "alias": "Auth Controller" }
                  actor U@{ "type" : "actor", "alias": "End User" }
                  actor DB@{ "type" : "database", "alias": "User Database" }
                  participant X@{ "type" : "boundary", "alias": "Internal Name" } as External Name
                  participant Y@{ "alias": "Only Alias" }
                  participant B@{ "type" : "control" } as Service B
                  participant C@{ "type" : "database" }
            """)
        XCTAssertEqual(inline.participants.map(\.kind), [.boundary, .control, .actor, .database, .boundary, .participant, .control, .database])
        XCTAssertEqual(inline.participants.map(\.label.lines), [["Public API"], ["Auth Controller"], ["End User"], ["User Database"], ["External Name"],
                                                                 ["Only Alias"], ["Service B"], ["C"]])
    }

    // MARK: boxes, creation and destruction

    func testShouldHandleABoxWithoutAColorOrADescription() throws {
        let withoutColor = try read("\n  sequenceDiagram\n  box Group 1\n  participant a as Alice\n  participant b as Bob\n  end\n  participant c as Charlie\n  link a: Endpoint @ https://alice.contoso.com\n  ")
        XCTAssertEqual(withoutColor.boxes.map(\.title), [DiagramLabel("Group 1")])
        XCTAssertEqual(withoutColor.boxes.map(\.color), [nil], "transparent")
        XCTAssertEqual(withoutColor.participants.map(\.boxIndex), [0, 0, nil])
        let withoutDescription = try read("\n  sequenceDiagram\n  box aqua\n  participant a as Alice\n  participant b as Bob\n  end\n  participant c as Charlie\n  ")
        XCTAssertEqual(withoutDescription.boxes.map(\.title), [nil])
        XCTAssertEqual(withoutDescription.boxes.map(\.color), [SequenceHighlightColor(red: 0, green: 1, blue: 1)])
    }

    func testShouldHandleSimpleActorCreation() throws {
        let diagram = try read("""

              sequenceDiagram
              participant a as Alice
              a ->>b: Hello Bob?
              create participant c
              b-->>c: Hello c!
              c ->> b: Hello b?
              create actor d as Donald
              a ->> d: Hello Donald?
            """)
        XCTAssertEqual(typeAndDescription(diagram, "c").0, .participant)
        XCTAssertEqual(typeAndDescription(diagram, "c").1, ["c"])
        XCTAssertEqual(typeAndDescription(diagram, "d").0, .actor)
        XCTAssertEqual(typeAndDescription(diagram, "d").1, ["Donald"])
        XCTAssertEqual(diagram.messages.map(\.createsTarget), [false, true, false, true], "createdActors c: 1, d: 3")
    }

    func testShouldHandleSimpleActorDestruction() throws {
        let diagram = try read("""

              sequenceDiagram
              participant a as Alice
              a ->>b: Hello Bob?
              destroy a
              b-->>a: Hello Alice!
              b ->> c: Where is Alice?
              destroy c
              b ->> c: Where are you?
            """)
        XCTAssertEqual(diagram.messages.map(\.destroysTarget), [false, true, false, true], "destroyedActors a: 1, c: 3")
        XCTAssertEqual(diagram.messages.map(\.destroysSource), [false, false, false, false])
    }

    // MARK: keywordActors.spec.ts

    func testMenuKeywordsAreParticipantNamesWhereNoParticipantFollowsThem() throws {
        for (statement, source, target) in [("Link->>A: message", "Link", "A"), ("Link  -->>A: message", "Link", "A"), ("A->>Link : message", "A", "Link")] {
            let diagram = try read("sequenceDiagram\n    participant A\n    participant Link as Channel\n    \(statement)")
            XCTAssertEqual(connections(diagram).map { text in String(text.prefix { character in character != " " }) }, ["\(source)->\(target)"], statement)
        }
        for name in ["Links", "Properties", "Details", "LINK"] {
            let diagram = try read("sequenceDiagram\n    participant A\n    participant \(name) as Alias\n    A->>\(name): message")
            XCTAssertEqual(diagram.participantIdentifiers, ["A", name])
            XCTAssertEqual(diagram.messages.count, 1, name)
        }
        let text = try read("sequenceDiagram\n    participant A\n    participant B\n    A->>B: see the link page")
        XCTAssertEqual(text.messages.map(\.text.lines), [["see the link page"]])
    }

    func testMenuStatementsStillParse() throws {
        for statement in ["link A: Help @ https://example.com", "link A : Help @ https://example.com", "links A: {\"help\": \"https://example.com\"}",
                          "properties A: {\"color\": \"red\"}", "details A: details-1"] {
            let diagram = try read("sequenceDiagram\n    participant A\n    \(statement)")
            XCTAssertEqual(diagram.participantIdentifiers, ["A"], statement)
            XCTAssertTrue(diagram.events.isEmpty, statement)
        }
    }
}
