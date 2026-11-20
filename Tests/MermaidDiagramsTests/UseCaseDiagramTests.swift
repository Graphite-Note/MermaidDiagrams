/**
 * File: UseCaseDiagramTests.swift
 * -------------------------------
 * Layer: Tests
 * Description: What a read use case diagram holds, as Pele's ports of Mermaid's usecase.spec.ts and
 *              usecase.parser.spec.ts check it: actors, use cases, boundaries, relationships, notes, metadata, labels,
 *              classes and styles, in the order first mentioned.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class UseCaseDiagramTests: XCTestCase {
    func testActorsAreDeclaredOneOrSeveralAtATime() throws {
        let one = try UseCaseReading.lines("actor User")
        XCTAssertEqual(one.actors.map(\.identifier), ["User"])
        XCTAssertEqual(one.actors.first?.label, "User")
        XCTAssertEqual(one.actors.first?.type, .normal)
        XCTAssertEqual(try UseCaseReading.lines("actor User", "actor Admin", "actor Guest").actors.map(\.identifier), ["User", "Admin", "Guest"])
        XCTAssertEqual(try UseCaseReading.lines("actor User, Admin(\"Administrator\")").actors.map(\.label), ["User", "Administrator"])
    }

    func testTheEndsOfRelationshipsNothingDeclaresAreOvalUseCasesInTheOrderMentioned() throws {
        let diagram = try UseCaseReading.lines("Left --> Right")
        XCTAssertTrue(diagram.actors.isEmpty)
        XCTAssertEqual(diagram.useCases, [
            UseCase(identifier: "Left", label: "Left", labelType: .text, shape: .ellipse, isBusiness: false, stereotype: nil, parentIdentifier: nil,
                    classes: [], styles: []),
            UseCase(identifier: "Right", label: "Right", labelType: .text, shape: .ellipse, isBusiness: false, stereotype: nil, parentIdentifier: nil,
                    classes: [], styles: []),
        ])
        let declaredLater = try UseCaseReading.lines("Customer --> Login", "actor Customer", "actor Admin(\"Main administrator\")", "Login(\"Sign in\")",
                                                     "Report[Generate report]", "\"Reset password\"", "Admin --> Report")
        XCTAssertEqual(declaredLater.actors.map(\.identifier), ["Customer", "Admin"])
        XCTAssertEqual(declaredLater.useCases.map(\.identifier), ["Login", "Report", "Reset_password"])
        XCTAssertEqual(declaredLater.useCases.map(\.label), ["Sign in", "Generate report", "Reset password"])
        XCTAssertEqual(declaredLater.useCases.map(\.shape), [.ellipse, .rectangle, .ellipse])
    }

    func testRelationshipsKeepTheirArrowsLabelsTypesAndLengths() throws {
        let diagram = try UseCaseReading.lines("A --> B", "A <-- B", "A -- B", "A --o B", "A o-- B", "A --x B", "A x-- B", "A -- \"starts\" --> B",
                                               "A <-- back -- B", "A -- l --o B", "A ..> : include B", "A ..> : EXTEND B", "actor X", "actor Y", "X --|> Y")
        XCTAssertEqual(diagram.relationships.map(\.arrow), [.solidArrow, .backArrow, .lineSolid, .circleArrow, .circleArrowReversed, .crossArrow,
                                                            .crossArrowReversed, .solidArrow, .backArrow, .circleArrow, .solidArrow, .solidArrow, .solidArrow])
        XCTAssertEqual(diagram.relationships.map(\.label), [nil, nil, nil, nil, nil, nil, nil, "starts", "back", "l", "include", "extend", nil])
        XCTAssertEqual(diagram.relationships.map(\.type).suffix(3), [.include, .extend, .generalization])
        XCTAssertEqual(diagram.relationships.map(\.identifier).prefix(3), ["edge-0", "edge-1", "edge-2"])
        let lengths = try UseCaseReading.lines("A base@--> B", "B two@---> C", "C many@-----> D", "D labelled@-- \"long\" ----> E", "E <---- F", "F ---- G")
        XCTAssertEqual(lengths.relationships.map(\.minimumLength), [1, 2, 4, 3, 3, 3])
        XCTAssertEqual(lengths.relationships.map(\.hasExplicitIdentifier), [true, true, true, true, false, false])
    }

    func testBoundariesHoldTheirMembersAndTakeTheirTitleIdAndType() throws {
        let diagram = try UseCaseReading.lines("systemBoundary Auth", "actor User(\"Person\")@{ type: hollow } <<Human>>",
                                               "actor User(\"Person\")@{ type: hollow } <<Human>>", "Login[Sign in] <<Primary>>",
                                               "Login[Sign in] <<Primary>>", "end")
        XCTAssertEqual(diagram.actors, [UseCaseActor(identifier: "User", label: "Person", labelType: .text, type: .hollow, icon: nil, isBusiness: false,
                                                     stereotype: "Human", parentIdentifier: "Auth", classes: [], styles: [])])
        XCTAssertEqual(diagram.useCase("Login")?.parentIdentifier, "Auth")
        XCTAssertEqual(diagram.boundary("Auth")?.members, ["User", "Login"])
        let package = try UseCaseReading.lines("classDef system fill:#f8f8ff", "systemBoundary sb1[\"Payment service\"]@{ type: package }:::system",
                                               "  actor Clerk(\"Payment clerk\")", "  Authorize(\"Authorize payment\")", "end", "Clerk --> Authorize")
        XCTAssertEqual(package.boundary("sb1"), UseCaseSystemBoundary(identifier: "sb1", label: "Payment service", labelType: .text, type: .package,
                                                                      members: ["Clerk", "Authorize"], classes: ["system"], styles: []))
        for (declaration, label, type) in [("sb1[Payment service]", "Payment service", UseCaseLabelType.text),
                                           ("sb1[\"`**Payment** service`\"]", "**Payment** service", .markdown),
                                           ("sb1(\"Payment service\")", "Payment service", .text)] {
            let boundary = try UseCaseReading.lines("systemBoundary " + declaration, "A", "end").boundary("sb1")
            XCTAssertEqual(boundary?.label, label)
            XCTAssertEqual(boundary?.labelType, type)
        }
        let derived = try UseCaseReading.lines("systemBoundary \"Payment service\"@{ type: package }", "  A", "end", "Payment_service@{ type: rect }")
        XCTAssertEqual(derived.boundary("Payment_service")?.type, .rectangle)
    }

    func testDirectionsAreReadAndTopDownIsTopToBottom() throws {
        XCTAssertEqual(try UseCaseReading.lines("A").direction, .leftToRight)
        XCTAssertEqual(try UseCaseReading.lines("direction TB").direction, .topToBottom)
        XCTAssertEqual(try UseCaseReading.lines("direction TD").direction, .topToBottom)
        XCTAssertEqual(try UseCaseReading.lines("direction RL").direction, .rightToLeft)
        XCTAssertEqual(try UseCaseReading.lines("direction BT").direction, .bottomToTop)
    }

    func testMetadataGivesActorsTheirTypesIconsAndBusinessAndRelationshipsTheirAnimation() throws {
        let actors = try UseCaseReading.lines("actor A@{ type: awesome }", "actor B@{ icon: \"fa:user\" }", "actor C@{ type: hollow, business: true }",
                                              "Q(\"Quote\")@{ business: true }")
        XCTAssertEqual(actors.actors.map(\.type), [.awesome, .icon, .hollow])
        XCTAssertEqual(actors.actor("B")?.icon, "fa:user")
        XCTAssertEqual(actors.actor("C")?.isBusiness, true)
        XCTAssertEqual(actors.useCase("Q")?.isBusiness, true)
        let edges = try UseCaseReading.lines("A trueEdge@--> B", "trueEdge@{ animate: true }", "A fastEdge@--> B", "fastEdge@{ animation: fast }",
                                             "A slowEdge@--> B", "slowEdge@{ animation: slow }", "A offEdge@--> B", "offEdge@{ animate: false }")
        XCTAssertEqual(edges.relationships.map(\.isAnimated), [true, true, true, false])
        XCTAssertEqual(edges.relationships.map(\.animation), [nil, .fast, .slow, nil])
        XCTAssertEqual(try UseCaseReading.lines("actor A", "A@{ type: hollow }", "A@{ type: awesome }").actor("A")?.type, .awesome)
    }

    func testLabelsAreKeptAsWrittenAndMarkdownStringsMayBreakLines() throws {
        let diagram = try UseCaseReading.diagram(["usecase-beta", "classDef decorated fill:#fee", "actor User(\"`**User**", "role`\") <<Human>>:::decorated",
                                                  "Login(\"`Sign", "in`\") <<Primary>>:::decorated", "Escaped(\"Open #40;safe#41; #91;now#93;\")",
                                                  "Literal(\"First\\nSecond\")"].joined(separator: "\n"))
        XCTAssertEqual(diagram.actor("User")?.label, "**User**\nrole")
        XCTAssertEqual(diagram.actor("User")?.labelType, .markdown)
        XCTAssertEqual(diagram.actor("User")?.classes, ["decorated"])
        XCTAssertEqual(diagram.useCase("Login")?.label, "Sign\nin")
        XCTAssertEqual(diagram.useCase("Login")?.stereotype, "Primary")
        XCTAssertEqual(diagram.useCase("Escaped")?.label, "Open #40;safe#41; #91;now#93;")
        XCTAssertEqual(diagram.useCase("Literal")?.label, "First\\nSecond")
        let unquoted = try UseCaseReading.lines("actor Reviewer(*Reviewer*)", "Literal(**Literal markers**)", "Priced[Costs 19.95 EUR, incl. VAT!]",
                                                "Progress(Ärende — 50% klart)", "Reviewer -- opens **form** --> Literal", "Reviewer --> Priced",
                                                "note for Literal Read the guide; then sign off.")
        XCTAssertEqual(unquoted.actor("Reviewer")?.label, "*Reviewer*")
        XCTAssertEqual(unquoted.useCase("Priced")?.label, "Costs 19.95 EUR, incl. VAT!")
        XCTAssertEqual(unquoted.useCase("Progress")?.label, "Ärende — 50% klart")
        XCTAssertEqual(unquoted.relationships.first?.label, "opens **form**")
        XCTAssertEqual(unquoted.notes.first?.label, "Read the guide; then sign off.")
        let digits = try UseCaseReading.lines("1 --> 2", "1mg --> 3rd", "actor 4(\"x\")", "5[y]")
        XCTAssertEqual(digits.useCases.map(\.identifier), ["1", "2", "1mg", "3rd", "5"])
        XCTAssertEqual(digits.actors.map(\.identifier), ["4"])
    }

    func testClassesStylesNotesAndAccessibilityReachTheirTargets() throws {
        let diagram = try UseCaseReading.lines("accTitle: Shop", "accDescr {", "  A customer", "    signs in.", "}", "actor User", "User --> Login",
                                               "note for User \"first\"", "Login --> Logout", "note for Logout \"second\"",
                                               "classDef a,b fill:#fff,stroke-width:3px", "classDef a stroke:red", "class User,Login a,b",
                                               "style Login stroke-dasharray:5\\,5,fill:red", "style Login font-family:Arial Black")
        XCTAssertEqual(diagram.accessibilityTitle, "Shop")
        XCTAssertEqual(diagram.accessibilityDescription, "A customer\nsigns in.")
        XCTAssertEqual(diagram.notes.map(\.identifier), ["note-0", "note-1"])
        XCTAssertEqual(diagram.notes.map(\.target), ["User", "Logout"])
        XCTAssertEqual(diagram.relationships.map(\.identifier), ["edge-0", "edge-1"])
        XCTAssertEqual(diagram.classDefinitions.map(\.identifier), ["a", "b"])
        XCTAssertEqual(diagram.classDefinitions.first?.styles, ["stroke:red"])
        XCTAssertEqual(diagram.actor("User")?.classes, ["a", "b"])
        XCTAssertEqual(diagram.useCase("Login")?.styles, ["stroke-dasharray:5,5", "fill:red", "font-family:Arial Black"])
        let edge = try UseCaseReading.lines("A known@--> B", "class known c", "style known stroke:#f00")
        XCTAssertEqual(edge.relationships.first?.classes, ["c"])
        XCTAssertEqual(edge.relationships.first?.styles, ["stroke:#f00"])
    }

    func testJSONTablesKeepTheirKeysInTheOrderWritten() throws {
        let diagram = try UseCaseReading.lines("json Payload@{", "  \"2\": \"second\",", "  \"1\": \"first\",", "  \"duplicate\": \"old\",",
                                               "  \"duplicate\": \"new\"", "}:::data", "style Payload stroke-width:4px")
        let node = try XCTUnwrap(diagram.jsonNodes.first)
        XCTAssertEqual(node.identifier, "Payload")
        XCTAssertEqual(node.classes, ["data"])
        XCTAssertEqual(node.styles, ["stroke-width:4px"])
        XCTAssertEqual(node.value.root.keys, ["2", "1", "duplicate"])
        XCTAssertEqual(node.value.root.children.map { child in node.value.entries[child].kind }, [.string("second"), .string("first"), .string("new")])
    }

    func testTheSpacingOptionsAreReadFromTheFrontMatter() throws {
        let diagram = try UseCaseReading.diagram("---\nconfig:\n  usecase:\n    nodeSpacing: 60\n    rankSpacing: 9000\n---\nusecase-beta\nA --> B")
        XCTAssertEqual(diagram.nodeSpacing, 60)
        XCTAssertEqual(diagram.rankSpacing, 2_000)
        XCTAssertNil(try UseCaseReading.lines("A").nodeSpacing)
    }

    func testTheCountsArePastTheLimitsBeforeAnythingOfThemIsMade() {
        var limits = MermaidDiagramLimits.standard
        limits.maximumNodeCount = 10
        limits.maximumEdgeCount = 10
        let actors = "usecase-beta\n" + (0..<11).map { index in "actor a\(index)\n" }.joined()
        XCTAssertEqual(UseCaseReading.readError(actors, limits: limits), .tooManyNodes(limit: 10))
        let edges = "usecase-beta\n" + (0..<11).map { _ in "A --> B\n" }.joined()
        XCTAssertEqual(UseCaseReading.readError(edges, limits: limits), .tooManyEdges(limit: 10))
        let ends = "usecase-beta\n" + (0..<6).map { index in "a\(index) --> b\(index)\n" }.joined()
        XCTAssertEqual(UseCaseReading.readError(ends, limits: limits), .tooManyNodes(limit: 10))
    }
}
