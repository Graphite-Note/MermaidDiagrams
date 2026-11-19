/**
 * File: EventModelParserTests.swift
 * ---------------------------------
 * Layer: Tests
 * Description: Event models are read as Mermaid's grammar and database read them: the inputs of Mermaid's
 *              eventmodeling specs as Pele ports them, the oracle's accepted and refused seeds, and Mermaid's source
 *              rules between kinds.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

/// Reads an event model for a test through `MermaidDiagramReader`.
enum EventModelReading {
    static func diagram(_ source: String, limits: MermaidDiagramLimits = .standard) throws(MermaidDiagramReadError) -> EventModelDiagram {
        guard case .eventModel(let diagram) = try MermaidDiagramReader.read(source, limits: limits) else { throw .noDiagram }
        return diagram
    }

    static func readError(_ source: String, limits: MermaidDiagramLimits = .standard) -> MermaidDiagramReadError? {
        do {
            _ = try diagram(source, limits: limits)
            return nil
        } catch {
            return error
        }
    }

    /// Each relation as its source's and target's frame numbers.
    static func relations(_ diagram: EventModelDiagram) -> [String] {
        diagram.relations.map { relation in diagram.frames[relation.sourceFrameIndex].identifier + "-" + diagram.frames[relation.targetFrameIndex].identifier }
    }
}

final class EventModelParserTests: XCTestCase {
    // MARK: eventmodeling.spec.ts

    func testTheSpecsDefinitionsAreRead() throws {
        let sources = [
            "eventmodeling\n    tf 01 ui UI\n    tf 02 cmd RunAction\n    tf 03 evt ActionExecuted",
            "eventmodeling\n    tf 01 cmd AddItem { productId: 7 }\n    tf 02 evt ItemAdded { productId: 7 }",
            "eventmodeling\n    tf 01 cmd AddItem\n    tf 02 evt ItemAdded [[ItemAddedData]]\n\ndata ItemAddedData\n{\n  productId: 7\n}",
            "eventmodeling\n    tf 01 ui CartUI\n    tf 02 cmd Inventory.AddItem\n    tf 03 evt Inventory.ItemAdded",
            "eventmodeling\n    tf 01 ui CartUI\n    tf 02 cmd AddItem\n    tf 03 cmd RemoveItem\n    tf 04 evt ItemChanged ->> 02 ->> 03",
            "eventmodeling\n    rf 01 ui CartUI\n    rf 02 cmd AddItem\n    rf 03 evt ItemAdded",
            "eventmodeling\n    tf 01 ui UI\n    tf 02 ui UI2\n    tf 03 cmd Command\n    tf 04 command Command2\n    tf 05 evt Event\n    tf 06 event Event2\n"
                + "    tf 07 pcr Processor\n    tf 08 processor Processor2\n    tf 09 rmo ReadModel\n    tf 10 readmodel ReadModel2",
        ]
        for source in sources { XCTAssertNoThrow(try EventModelReading.diagram(source), source) }
        let data = try EventModelReading.diagram(sources[2])
        XCTAssertEqual(data.frames[1].data, "productId: 7")
        let kinds = try EventModelReading.diagram(sources[6]).frames.map(\.kind)
        XCTAssertEqual(kinds, [.userInterface, .userInterface, .command, .command, .event, .event, .processor, .processor, .readModel, .readModel])
    }

    func testAFrameNumberUsedTwiceIsRefusedOnTheLineOfTheSecond() {
        XCTAssertEqual(EventModelReading.readError("eventmodeling\n        tf 01 ui UI\n        tf 02 cmd Command\n        rf 01 evt Event"),
                       .invalidSyntax(line: 4, problem: .eventModeling(.duplicateFrame(identifier: "01"))))
        XCTAssertEqual(EventModelReading.readError("eventmodeling\n        tf 01 ui UI\n        %% This comment occupies a source line.\n        rf 01 evt Event"),
                       .invalidSyntax(line: 4, problem: .eventModeling(.duplicateFrame(identifier: "01"))))
    }

    func testAResetFrameKeepsItsNamedSourcesAndInfersNone() throws {
        let diagram = try EventModelReading.diagram("eventmodeling\n      tf 01 ui UI\n      tf 02 cmd Command\n      tf 03 evt Event\n      rf 04 rmo ReadModel ->> 03\n      rf 05 ui OtherUI")
        let relations = EventModelReading.relations(diagram)
        XCTAssertTrue(relations.contains("03-04"))
        XCTAssertFalse(relations.contains("04-05"))
        XCTAssertEqual(relations, ["01-02", "02-03", "03-04"])
    }

    // MARK: eventmodeling.test.ts

    func testTheComplexModelOfTheParserTestIsRead() throws {
        let source = """
        eventmodeling
        tf 01 cmd UpdateCartCommand
        tf 02 evt CartUpdatedEvent ->> 01 `jsobj`{ a: b }
        tf 03 rmo CartItemsReadModel ->> 02 [[CartItemsReadModel03]]
        tf 04 evt ProductDescriptionUpdatedEvent ->> 01 `jsobj`{ a: { c: d } }
        tf 05 evt ProductTitleUpdatedEvent ->> 01 { "a": { "c": true } }
        tf 06 evt ProductCountIncrementedEvent ->> 01 `json`" { "a": { "c": true } } "

        data CartItemsReadModel03 {
          { a: b }
        }

        data NotAssignedData02 `jsobj` {
          { a: {
            d: true
          }}
        }

        data AnotherNotAssignedData06 {
          a: 'abc'
        }

        note 02 `md` {
            # head 1
            this is markdown note
        }

        note 05 {
          This is whatever <b>you</b> want
          On multiple lines
        }

        gwt 01
          given
            evt CartUpdatedEvent
            evt CartUpdatedEvent
          when
            evt ProductDescriptionUpdatedEvent
            evt ProductTitleUpdatedEvent
          then
            evt ProductTitleUpdatedEvent


        gwt 03
          given
            evt CartUpdatedEvent
            evt ProductTitleUpdatedEvent
          then
            evt ProductTitleUpdatedEvent
            evt CartUpdatedEvent

        """
        let diagram = try EventModelReading.diagram(source)
        XCTAssertEqual(diagram.frames.count, 6)
        XCTAssertEqual(diagram.notes.count, 2)
        XCTAssertEqual(diagram.specifications.count, 2)
        XCTAssertEqual(diagram.frames[1].data, "a: b")
        XCTAssertEqual(diagram.frames[1].dataType, "jsobj")
        XCTAssertEqual(diagram.frames[2].data, "{ a: b }")
        XCTAssertEqual(diagram.frames[5].data, "\"a\": { \"c\": true }")
        XCTAssertEqual(diagram.notes[0], EventModelNote(frameIdentifier: "02", text: "# head 1\nthis is markdown note", dataType: "md"))
        XCTAssertEqual(diagram.notes[1].text, "This is whatever <b>you</b> want\nOn multiple lines")
        XCTAssertEqual(diagram.specifications[0], EventModelSpecification(
            frameIdentifier: "01", given: ["CartUpdatedEvent", "CartUpdatedEvent"], when: ["ProductDescriptionUpdatedEvent", "ProductTitleUpdatedEvent"],
            then: ["ProductTitleUpdatedEvent"]))
        XCTAssertEqual(diagram.specifications[1].when, [])
    }

    func testFramesKeepTheirNumberKeywordAndQualifiedName() throws {
        let simple = try EventModelReading.diagram("eventmodeling\ntimeframe 01 event Start\n\n  ")
        XCTAssertEqual(simple.frames.map(\.identifier), ["01"])
        XCTAssertEqual(simple.frames[0].kind, .event)
        XCTAssertEqual(simple.frames[0].entity, "Start")
        let qualified = try EventModelReading.diagram("eventmodeling\n\ntimeframe 02 ui UI\ntf 01 evt Product.PriceChanged\ntf 03 evt Cart.ItemAdded\n\n  ")
        XCTAssertEqual(qualified.frames[1].identifier, "01")
        XCTAssertEqual(qualified.frames[1].entity, "Product.PriceChanged")
        XCTAssertEqual(qualified.frames[1].name, "PriceChanged")
        XCTAssertEqual(qualified.frames[1].namespace, "Product")
        let both = try EventModelReading.diagram("eventmodeling\n\ntf 02 ui UI\nresetframe 01 evt Product.PriceChanged\ntf 03 evt Cart.ItemAdded\n\n  ")
        XCTAssertEqual(both.frames.map(\.isReset), [false, true, false])
        let sources = try EventModelReading.diagram("eventmodeling\ntf 01 evt Start\ntf 02 evt End\nrf 03 readmodel ReadModel01 ->> 01 ->> 02 { a: true }\nrf 04 rmo ReadModel02 ->> 01 ->> 02\n  ")
        XCTAssertEqual(EventModelReading.relations(sources), ["01-03", "02-03", "01-04", "02-04"])
    }

    /// Mermaid's validator states which kind may feed which; it is never run while a diagram is read, so a model that
    /// breaks the rules is still read and drawn.
    func testTheSourceRulesOfMermaidsValidator() throws {
        let allowed: [(EventModelEntityKind, EventModelEntityKind)] = [
            (.event, .command), (.command, .userInterface), (.command, .processor), (.userInterface, .readModel), (.readModel, .event),
            (.processor, .readModel),
        ]
        for target in EventModelEntityKind.allCases {
            for source in EventModelEntityKind.allCases {
                let isAllowed = allowed.contains { pair in pair == (target, source) }
                XCTAssertEqual(target.acceptsInput(from: source), isAllowed, "\(target) from \(source)")
            }
        }
        XCTAssertNoThrow(try EventModelReading.diagram("eventmodeling\ntf 01 rmo A\ntf 02 evt B ->> 01"))
    }

    // MARK: The oracle's seeds

    func testTheOraclesValidSeedsAreRead() throws {
        let valid = [
            "eventmodeling", "eventmodeling\n",
            "eventmodeling\ntf 01 cmd A . B.C ->> 02 ->> 3 [[D]] `json`{ a: 1 }\nrf 02 evt X {q}\nentity N.M\ndata D `md` {\n  x\n}\nnote 01 {\n hi\n}\n",
            "eventmodeling\ngwt 01 given evt A cmd B when ui C then evt D\ngwt 2\n given\n  rmo A\n then\n  pcr B\n  processor C\n",
            "eventmodeling title Foo\ntf 01 ui A accDescr: d\ntf 02 cmd B accTitle: t\n",
            "eventmodeling accDescr {\n multi\n line\n}\ntf 1 event E \"inline\"\ntf 2 command C 'single'\ntf 3 readmodel R `text`\"t\"\n",
            "eventmodeling\n/* block\n comment */\ntf 01 ui A // line comment\n%% percent comment\ntf 02 cmd B %% trailing\n",
            "eventmodeling\r\ntimeframe 01 ui A\r\nresetframe 02 processor P ->> 01\r\ndata D {\r\n x\r\n}\r\n",
            "eventmodeling\ndata D {\n}\ndata E `jsobj` {  \n  { a: {\n    d: true\n  }}\n}\nnote 1 `html` {\n <b>x</b>\n}",
            "eventmodeling\ntf 123 evt _a1.b_2 { { nested } } \ntf 4 evt B { a } [[x]] { b }\n",
            "---\ntitle: x\n---\neventmodeling\ntf 01 ui A\n",
            "eventmodeling%%c\ntf 01 ui tfx\ntf 02 ui eventx\n",
            "eventmodeling title T\ntf 01 ui titles\ntf 02 cmd title_x ->> 01 [[titleData]]\nentity titles.title2\ndata titleData {\n x\n}\ngwt 02 given evt titles then rmo title_x\n",
        ]
        for source in valid { XCTAssertNoThrow(try EventModelReading.diagram(source), source.debugDescription) }
        let titled = try EventModelReading.diagram(valid[4])
        XCTAssertEqual(titled.title, "Foo")
        XCTAssertEqual(titled.accessibilityTitle, "t")
        XCTAssertEqual(titled.accessibilityDescription, "d")
        XCTAssertEqual(try EventModelReading.diagram(valid[5]).accessibilityDescription, "multi\nline")
        XCTAssertEqual(try EventModelReading.diagram(valid[5]).frames.map(\.data), ["inline", "single", "t"])
        XCTAssertEqual(try EventModelReading.diagram(valid[10]).title, "x")
        XCTAssertEqual(try EventModelReading.diagram(valid[11]).frames.map(\.name), ["tfx", "eventx"])
        XCTAssertEqual(try EventModelReading.diagram(valid[2]).entities, ["N.M"])
        XCTAssertEqual(try EventModelReading.diagram(valid[2]).frames[0].entity, "A.B.C")
        XCTAssertNil(try EventModelReading.diagram(valid[2]).frames[0].namespace, "Only a name of two parts has a namespace")
    }

    func testTheOraclesInvalidSeedsAreRefusedWithTheirProblem() {
        let invalid: [(String, MermaidDiagramReadError)] = [
            ("eventmodeling\ntitle Foo\n", .invalidSyntax(line: 2, problem: .eventModeling(.expectedStatement))),
            ("eventmodeling\ntf 01 evt data\n", .invalidSyntax(line: 2, problem: .eventModeling(.expectedName))),
            ("eventmodeling\ntf 01 evt title\n", .invalidSyntax(line: 2, problem: .eventModeling(.expectedName))),
            ("eventmodeling\ntf 1234 evt A\n", .invalidSyntax(line: 2, problem: .eventModeling(.expectedEntityKind))),
            ("eventmodeling\ntf 01 evt A {\n", .invalidSyntax(line: 2, problem: .unexpectedText("{"))),
            ("eventmodeling\ngwt 01 given then evt A\n", .invalidSyntax(line: 2, problem: .eventModeling(.expectedEntityKind))),
            ("eventmodelingx\n", .invalidSyntax(line: 1, problem: .eventModeling(.expectedKeyword))),
            ("eventmodeling\ntf 01 A\n", .invalidSyntax(line: 2, problem: .eventModeling(.expectedEntityKind))),
        ]
        for (source, expected) in invalid { XCTAssertEqual(EventModelReading.readError(source), expected, source.debugDescription) }
    }

    func testLanesAreOneAGroupAndOneANamespaceInMermaidsOrder() throws {
        let diagram = try EventModelReading.diagram("eventmodeling\ntf 01 evt Cart.A\ntf 02 ui B\ntf 03 evt C\ntf 04 evt Shop.D\ntf 05 cmd E\ntf 06 pcr Robot.F")
        XCTAssertEqual(diagram.lanes.map(\.label), ["UI/Automation", "UI/A: Robot", "Command/Read Model", "Events", "Stream: Cart", "Stream: Shop"])
        XCTAssertEqual(diagram.lanes.map(\.orderKey), [0, 1, 100, 200, 201, 202])
        XCTAssertEqual(diagram.frames.map { frame in diagram.lanes[frame.laneIndex].label },
                       ["Stream: Cart", "UI/Automation", "Events", "Stream: Shop", "Command/Read Model", "UI/A: Robot"])
        XCTAssertEqual(EventModelReading.relations(diagram), ["01-02", "02-03", "03-04", "04-05", "05-06"])
    }

    func testAFrameIsFedByTheNearestEarlierFrameInAnotherLaneOrByTheSourcesItNames() throws {
        let diagram = try EventModelReading.diagram("eventmodeling\ntf 01 ui A\ntf 02 ui B\ntf 03 cmd C\ntf 04 cmd D\ntf 05 evt E ->> 04 ->> 01 ->> 09 ->> 05")
        // 02 is in the lane of 01, 04 in the lane of 03; 05 names 04, 01, a frame that does not exist and itself.
        XCTAssertEqual(EventModelReading.relations(diagram), ["02-03", "02-04", "01-05", "04-05", "05-05"])
    }

    func testCountsPastTheLimitsAreRefusedBeforeTheyAreMade() {
        var limits = MermaidDiagramLimits.standard
        limits.maximumNodeCount = 3
        XCTAssertEqual(EventModelReading.readError("eventmodeling\ntf 01 ui A\ntf 02 cmd B\nnote 01 {\n n\n}\ngwt 01 given evt A then evt B", limits: limits),
                       .tooManyNodes(limit: 3))
        limits = .standard
        limits.maximumEdgeCount = 2
        XCTAssertEqual(EventModelReading.readError("eventmodeling\ntf 01 ui A\ntf 02 cmd B\ntf 03 evt C\ntf 04 rmo D", limits: limits), .tooManyEdges(limit: 2))
    }

    func testDataIsTheTextBetweenItsOuterBracesWithoutItsSharedIndentation() {
        XCTAssertEqual(EventModelDiagramBuilder.blockText("{\n    a: 1\n      b: 2\n\n}\n"), "a: 1\n  b: 2")
        XCTAssertEqual(EventModelDiagramBuilder.blockText("\"quoted { } text\""), "", "Between the braces, a blank line")
        XCTAssertEqual(EventModelDiagramBuilder.blockText("'plain text'"), "plain text")
        XCTAssertEqual(EventModelDiagramBuilder.blockText("{\r\n  x   \r\n}"), "x")
        XCTAssertEqual(EventModelDiagramBuilder.blockText("{}"), "")
    }
}
