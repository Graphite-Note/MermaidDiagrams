/**
 * File: UseCaseContradictionTests.swift
 * -------------------------------------
 * Layer: Tests
 * Description: Use case statements that contradict each other or name what they cannot are refused with a typed case
 *              on the line of the statement at fault, as Pele's port of Mermaid's usecase.parser.spec.ts refuses them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class UseCaseContradictionTests: XCTestCase {
    private func contradiction(_ lines: String...) -> UseCaseContradiction? {
        UseCaseReading.contradiction((["usecase-beta"] + lines).joined(separator: "\n"))
    }

    private func line(_ lines: String...) -> Int? {
        UseCaseReading.problem((["usecase-beta"] + lines).joined(separator: "\n"))?.line
    }

    func testConflictingDeclarationsAreRefused() {
        XCTAssertEqual(contradiction("actor Shared", "Shared"), .declaredAsTwoKinds(identifier: "Shared", first: .actor, second: .useCase))
        XCTAssertEqual(contradiction("Login(Sign in)", "Login[Sign in]"), .conflictingShapes(useCase: "Login"))
        XCTAssertEqual(contradiction("Login(First label)", "Login(Second label)"), .conflictingLabels(identifier: "Login"))
        XCTAssertEqual(contradiction("Login <<Primary>>", "Login <<Secondary>>"), .conflictingStereotypes(identifier: "Login"))
        XCTAssertEqual(contradiction("systemBoundary First", "Login", "end", "systemBoundary Second", "Login", "end"),
                       .inMoreThanOneBoundary(identifier: "Login"))
        XCTAssertEqual(line("systemBoundary First", "Login", "end", "systemBoundary Second", "Login", "end"), 5)
        XCTAssertEqual(contradiction("systemBoundary A", "end", "systemBoundary A[\"Other\"]", "end"), .conflictingBoundaryTitles(boundary: "A"))
        XCTAssertEqual(contradiction("actor User@{ type: hollow }", "actor User@{ type: awesome }"),
                       .conflictingActorMetadata(actor: "User", key: "type"))
        XCTAssertEqual(contradiction("Q@{ business: true }", "Q@{ business: false }", "Q"), nil)
        XCTAssertEqual(contradiction("Q(Quote)@{ business: true }", "Q(Quote)@{ business: false }"), .conflictingBusinessMetadata(useCase: "Q"))
    }

    func testIdsMeanOneThingInTheWholeDiagram() {
        XCTAssertEqual(contradiction("\"A-B\"", "\"A B\""), .generatedIdentifierCollision(identifier: "A_B"))
        XCTAssertEqual(line("\"A-B\"", "\"A B\""), 3)
        XCTAssertEqual(contradiction("\"A B\"", "A_B(Explicit)"), .generatedIdentifierCollision(identifier: "A_B"))
        XCTAssertEqual(contradiction("actor \"A-B\"", "\"A B\""), .declaredAsTwoKinds(identifier: "A_B", first: .actor, second: .useCase))
        XCTAssertEqual(contradiction("systemBoundary \"A-B\"", "end", "systemBoundary \"A B\"", "end"), .generatedIdentifierCollision(identifier: "A_B"))
        XCTAssertEqual(contradiction("actor Shared", "json Shared@{}"), .declaredMoreThanOnce(identifier: "Shared", first: .actor, second: .json))
        XCTAssertEqual(contradiction("actor link", "A link@--> B"), .declaredMoreThanOnce(identifier: "link", first: .actor, second: .edge))
        XCTAssertEqual(contradiction("A link@--> B", "B link@--> C"), .declaredMoreThanOnce(identifier: "link", first: .edge, second: .edge))
        XCTAssertEqual(line("A link@--> B", "B link@--> C"), 3)
        XCTAssertNil(contradiction("\"Reset password\"", "Login(\"Reset password\")"))
    }

    func testTargetsNothingDeclaresAreRefused() {
        XCTAssertEqual(contradiction("note for Ghost \"Missing\""), .unresolvedNoteTarget(identifier: "Ghost"))
        XCTAssertEqual(contradiction("class Ghost important"), .unresolvedStyleTarget(identifier: "Ghost"))
        XCTAssertEqual(contradiction("style Ghost fill:red"), .unresolvedStyleTarget(identifier: "Ghost"))
        XCTAssertEqual(contradiction("Ghost@{ type: package }"), .unresolvedMetadataTarget(identifier: "Ghost", impliedKind: .boundary))
        XCTAssertEqual(contradiction("Ghost@{ icon: \"x\" }"), .unresolvedMetadataTarget(identifier: "Ghost", impliedKind: .actor))
        XCTAssertEqual(contradiction("Ghost@{ business: true }"), .unresolvedMetadataTarget(identifier: "Ghost", impliedKind: nil))
        XCTAssertEqual(contradiction("A known@--> B", "class missingEdge decorated"), .unresolvedStyleTarget(identifier: "missingEdge"))
        XCTAssertEqual(contradiction("direction TB", "classDef important fill:red", "actor User:::important", "Login[Sign in]", "User link@--> Login",
                                     "link@{ animation: fast }", "json Payload@{\"ok\": true}", "note for Missing \"late failure\""),
                       .unresolvedNoteTarget(identifier: "Missing"))
        XCTAssertEqual(contradiction("A:::c --> B"), .classedEndpointNotDeclared(identifier: "A"))
    }

    func testMetadataATargetDoesNotTakeIsRefused() {
        XCTAssertEqual(contradiction("actor User@{ type: giant }"), .invalidMetadataProperty(target: "User", key: "type", kind: .actor))
        XCTAssertEqual(contradiction("actor User@{ fillColor: red }"), .invalidMetadataProperty(target: "User", key: "fillColor", kind: .actor))
        XCTAssertEqual(contradiction("actor User@{ icon: \"fa:user\", type: awesome }"), .iconWithActorType(actor: "User", type: .awesome))
        XCTAssertEqual(contradiction("A link@--> B", "link@{ animation: medium }"), .invalidMetadataProperty(target: "link", key: "animation", kind: .edge))
        XCTAssertEqual(contradiction("A link@--> B", "link@{ animate: fast }"), .invalidMetadataProperty(target: "link", key: "animate", kind: .edge))
        XCTAssertEqual(contradiction("systemBoundary sb1[\"Payment service\"]@{ animate: true }", "A", "end"),
                       .invalidMetadataProperty(target: "sb1", key: "animate", kind: .boundary))
        XCTAssertEqual(contradiction("json P@{}", "P@{ type: rect }"), .invalidMetadataProperty(target: "P", key: "type", kind: .json))
        XCTAssertEqual(contradiction("actor Icon@{ icon: \"fa:user\", business: true }"), .businessActorGeometry(actor: "Icon"))
        XCTAssertEqual(contradiction("actor Awesome@{ type: awesome, business: true }"), .businessActorGeometry(actor: "Awesome"))
        XCTAssertEqual(contradiction("Report[Generate report]@{ business: true }"), .rectangularBusinessUseCase(identifier: "Report"))
    }

    func testRelationshipsBetweenKindsTheyDoNotJoinAreRefused() {
        XCTAssertEqual(contradiction("actor User", "Login", "User --|> Login"), .generalizationEndpoints)
        XCTAssertEqual(contradiction("actor User", "actor Admin", "User ..> : include Admin"), .relationshipNeedsUseCases(.include))
        XCTAssertEqual(contradiction("json Payload@{}", "Inspect", "Payload ..> : include Inspect"), .relationshipNeedsUseCases(.include))
        XCTAssertEqual(contradiction("json Payload@{}", "Inspect --o Payload"), .jsonRelationshipMarks(source: "Inspect", target: "Payload"))
        XCTAssertNil(contradiction("json Payload@{}", "Inspect <-- Payload"))
        XCTAssertEqual(contradiction("systemBoundary S", "A", "end", "S --> A"), .relationshipEndpointKind(identifier: "S", isSource: true, kind: .boundary))
        XCTAssertEqual(contradiction("A link@--> B", "C --> link"), .relationshipEndpointKind(identifier: "link", isSource: false, kind: .edge))
    }

    func testNotesAreForActorsAndUseCasesOnly() {
        XCTAssertEqual(contradiction("json Payload@{}", "note for Payload \"invalid\""), .noteTargetKind(identifier: "Payload", kind: .json))
        XCTAssertEqual(contradiction("systemBoundary Auth", "Login", "end", "note for Auth \"invalid\""), .noteTargetKind(identifier: "Auth", kind: .boundary))
        XCTAssertEqual(contradiction("A link@--> B", "note for link \"invalid\""), .noteTargetKind(identifier: "link", kind: .edge))
        XCTAssertEqual(line("A link@--> B", "note for link \"invalid\""), 3)
    }
}
