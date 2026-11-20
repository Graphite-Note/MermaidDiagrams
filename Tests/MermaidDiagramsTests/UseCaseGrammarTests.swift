/**
 * File: UseCaseGrammarTests.swift
 * -------------------------------
 * Layer: Tests
 * Description: The use case parser accepts and refuses what Mermaid's grammar does, as Pele's port of Mermaid's
 *              parser/usecase.parser.spec.ts checks it, and names the line and the token where the text breaks.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class UseCaseGrammarTests: XCTestCase {
    /// Whether the text passes the lexer and the grammar: a contradiction found afterwards means the grammar took it.
    private func isAccepted(_ source: String) -> Bool {
        switch UseCaseReading.readError(source) {
        case nil: true
        case .invalidSyntax(_, .useCase(.contradiction))?: true
        default: false
        }
    }

    func testTheHeaderLineBreaksBlankLinesAndCommentsAreAccepted() {
        for source in ["usecase-beta", "usecase-beta\nactor User", "usecase-beta\r\nactor User\r\n", "usecase-beta\ractor User\r",
                       "usecase-beta\n\n  %% retained\nLogin"] {
            XCTAssertTrue(isAccepted(source), source)
        }
    }

    func testCanonicalActorsUseCasesMetadataStereotypesAndClassesAreAccepted() {
        XCTAssertTrue(isAccepted("""
            usecase-beta
            actor Admin("Main Administrator")@{ type: hollow, business: true } <<Human>>:::external
            actor "System Administrator", "`**Automation**`"
            Login(Sign in)@{ business: false } <<Primary>>:::critical
            Report[Generate report]
            "Reset password"
            "`**Markdown** use case`"
            """))
        XCTAssertTrue(isAccepted("usecase-beta\nUser@{\n  business: true\n  type: normal,\n}"))
    }

    func testEveryCanonicalRelationIsAccepted() {
        let relations = ["A --> B", "A <-- B", "A -- B", "A --o B", "A o-- B", "A --x B", "A x-- B", "A -- \"starts session\" --> B",
                         "A <-- \"reverse label\" -- B", "A -- label -- B", "A -- label --o B", "A o-- label -- B", "A -- label --x B",
                         "A x-- label -- B", "A ..> : include B", "A ..> : INCLUDE B", "A ..> : ExTeNd B", "A --|> B", "A ---> B", "A <---- B",
                         "A ---- B", "A -- longer ----> B", "A login@--> B", "A dependency@..> : include B"]
        for relation in relations { XCTAssertTrue(isAccepted("usecase-beta\n" + relation), relation) }
    }

    func testBoundariesNotesJSONDirectionClassesStylesAndAccessibilityAreAccepted() {
        XCTAssertTrue(isAccepted("""
            usecase-beta
            systemBoundary "Authentication System":::system
              %% boundary comment
              actor User, Admin("Administrator")

              Login("Sign in"):::critical
              Report[Generate report]
            end
            User --> Login
            """))
        XCTAssertTrue(isAccepted("""
            usecase-beta
            systemBoundary sb1["Payment service"]@{ type: package }:::system
              Authorize("Authorize payment")
            end
            systemBoundary sb2(Billing)@{
              type: rect
            }:::billing
              Invoice[Create invoice]
            end
            systemBoundary sb3("`**Support**`")
              Refund[Issue refund]
            end
            """))
        XCTAssertTrue(isAccepted("""
            usecase-beta
            direction LR
            Auth@{ type: package }
            note for Login "`Requires an **active session**`"
            json Payload@{
              "fruit": "Apple",
              "nested": { "brace": "}", "items": [1, 2] }
            }:::data
            classDef external,critical fill:#fff,stroke-width:3px
            class Login,Payload external,critical
            style Login fill:#fee,stroke-dasharray:5\\,5
            """))
        XCTAssertTrue(isAccepted("usecase-beta\naccTitle: Authentication use cases\naccDescr: Actors and authentication flows"))
        XCTAssertTrue(isAccepted("usecase-beta\naccDescr {\n  Actors authenticate,\n  reset credentials, and sign out.\n}"))
    }

    func testWhatMermaidsGrammarRefusesIsRefused() {
        let refused = ["Usecase\nA", "usecase-beta\nactor A actor B", "usecase actor A", "usecase-beta\nactor A, B --> C", "usecase-beta\nunknown command",
                       "usecase-beta\n// not a comment", "usecase-beta\n# not a comment", "usecase-beta\nA; B", "usecase-beta\n:User:",
                       "usecase-beta\nactor User as U", "usecase-beta\nusecase \"Login\" as Login", "usecase-beta\nnewpage",
                       "usecase-beta\npackage \"Auth\" {", "usecase-beta\nrectangle \"Auth\" {", "usecase-beta\nskinparam actorStyle awesome",
                       "usecase-beta\nallowmixing", "usecase-beta\n== Section ==", "usecase-beta\nA \\n B", "usecase-beta\nA -left-> B",
                       "usecase-beta\nnote left of Login \"text\"", "usecase-beta\nnote for Login as N \"text\"",
                       "usecase-beta\nnote for Login,Report \"text\"", "usecase-beta\nsystemBoundary A\nsystemBoundary B\nend\nend",
                       "usecase-beta\nsystemBoundary A\nUser --> Login\nend", "usecase-beta\nsystemBoundary A\nnote for User \"text\"\nend",
                       "usecase-beta\nsystemBoundary A\njson Payload@{}\nend", "usecase-beta\nA ---o B", "usecase-beta\nA o--- B",
                       "usecase-beta\nA ---x B", "usecase-beta\nA ---|> B", "usecase-beta\nA ...> : include B", "usecase-beta\nA <<>>",
                       "usecase-beta\nA <<first\nsecond>>", "usecase-beta\nA <<primary", "usecase-beta\njson Payload@{\"nested\": {",
                       "usecase-beta\nA(\"`unfinished\")", "usecase-beta\nstyle A fill:red;stroke:blue",
                       "usecase-beta\nsystemBoundary A:::system@{ type: package }\nend", "usecase-beta\nsystemBoundary A <<S>>\nend",
                       "usecase-beta\nsystemBoundary [Payment service]\nend"]
        for source in refused { XCTAssertFalse(isAccepted(source), source) }
    }

    func testAnUnquotedLabelStillRefusesItsDelimitersAtTheirToken() {
        for (statement, token) in [("Literal(Literal (nested) markers)", "("), ("Literal[Literal [nested] markers]", "["),
                                   ("Literal(Literal {nested} markers)", "{"), ("Literal(Literal -- markers)", "--"),
                                   ("Literal(Literal ::: markers)", ":::"), ("Literal(Literal @{ markers)", "@{")] {
            guard case .unexpectedToken(let found, _)? = UseCaseReading.problem("usecase-beta\n" + statement)?.problem else {
                XCTFail(statement)
                continue
            }
            XCTAssertEqual(found, token, statement)
        }
        XCTAssertEqual(UseCaseReading.problem("usecase-beta\nLiteral(Literal \"markers)")?.problem, .unexpectedCharacter)
        XCTAssertEqual(UseCaseReading.problem("usecase-beta\nLiteral(Reviewer's markers)")?.problem, .unexpectedCharacter)
    }

    func testAnErrorNamesItsLineAndToken() {
        for (statement, token, line) in [("User --> Login", "-->", 3), ("note for User \"inside\"", "note", 3),
                                         ("json Payload@{}", "json Payload@", 3), ("systemBoundary Nested\nend", "systemBoundary", 3)] {
            let problem = UseCaseReading.problem("usecase-beta\nsystemBoundary Auth\n" + statement + "\nend")
            XCTAssertEqual(problem?.line, line, statement)
            guard case .unexpectedToken(let found, _)? = problem?.problem else {
                XCTFail(statement)
                continue
            }
            XCTAssertEqual(found, token, statement)
        }
        for body in ["systemBoundary Auth <<System>>\nLogin\nend", "Login\nnote for Login \"text\" <<Memo>>", "json Payload@{} <<Data>>",
                     "A link@--> B\nlink@{ animate: true } <<Link>>"] {
            guard case .unexpectedToken(let found, _)? = UseCaseReading.problem("usecase-beta\n" + body)?.problem else {
                XCTFail(body)
                continue
            }
            XCTAssertEqual(found, "<<", body)
        }
        // Pele's parser reads the text with a line break added at its end, and finds that line break here.
        XCTAssertEqual(UseCaseReading.problem("usecase-beta\nactor")?.problem, .unexpectedToken(found: "\n", expected: .name))
        XCTAssertEqual(UseCaseReading.problem("usecase-beta\nA -->")?.problem, .unexpectedToken(found: "\n", expected: .name))
        XCTAssertEqual(UseCaseReading.problem("usecase-beta\nsystemBoundary sb1:::system@{ type: package }\nA\nend")?.problem,
                       .unexpectedToken(found: "@{", expected: .lineEnd))
        XCTAssertEqual(UseCaseReading.problem("%% first\n\nusecase-beta\nactor A\nactor B C")?.line, 5)
    }

    /// Mermaid's preprocessing drops the semicolon after a style's color, so that the style reads.
    func testTheSemicolonAfterAStylesColorIsDropped() throws {
        let diagram = try UseCaseReading.lines("A", "style A fill:#f9f;", "classDef c stroke:#333;")
        XCTAssertEqual(diagram.useCase("A")?.styles, ["fill:#f9f"])
        XCTAssertEqual(diagram.classDefinitions.first?.styles, ["stroke:#333"])
    }
}
