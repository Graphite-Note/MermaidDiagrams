/**
 * File: RequirementParserTests.swift
 * ----------------------------------
 * Layer: Tests
 * Description: The inputs of Mermaid 12.1.0's requirement diagram specs, as Pele ports them (`tests/compat/requirement`),
 *              read by the requirement diagram reader, with what Mermaid's database holds for them.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class RequirementParserTests: XCTestCase {
    static func read(_ source: String, limits: MermaidDiagramLimits = .standard) throws -> RequirementDiagram {
        guard case .requirement(let diagram) = try MermaidDiagramReader.read(source, limits: limits) else { throw MermaidDiagramReadError.noDiagram }
        return diagram
    }

    private static func requirementText(kind: String, risk: String = "High", method: String = "Analysis") -> String {
        ["requirementDiagram", "", "\(kind) test_req {", "id: test_id", "text: the test text.", "risk: \(risk)", "verifymethod: \(method)", "}"]
            .joined(separator: "\n")
    }

    func testAFullRequirementDefinition() throws {
        let diagram = try Self.read(Self.requirementText(kind: "requirement"))
        XCTAssertEqual(diagram.requirements.count, 1)
        let requirement = try XCTUnwrap(diagram.requirements.first)
        XCTAssertEqual(requirement.name, "test_req")
        XCTAssertEqual(requirement.identifier, "test_id")
        XCTAssertEqual(requirement.text, "the test text.")
        XCTAssertEqual(requirement.risk, .high)
        XCTAssertEqual(requirement.verificationMethod, .analysis)
        XCTAssertTrue(diagram.elements.isEmpty)
        XCTAssertTrue(diagram.relations.isEmpty)
    }

    func testAFullElementDefinition() throws {
        let diagram = try Self.read(["requirementDiagram", "", "element test_el {", "type: test_type", "docref: test_ref", "}"].joined(separator: "\n"))
        XCTAssertTrue(diagram.requirements.isEmpty)
        let element = try XCTUnwrap(diagram.elements.first)
        XCTAssertEqual(diagram.elements.count, 1)
        XCTAssertEqual(element.name, "test_el")
        XCTAssertEqual(element.type, "test_type")
        XCTAssertEqual(element.documentReference, "test_ref")
        XCTAssertTrue(diagram.relations.isEmpty)
    }

    func testAccessibilityTitleAndDescription() throws {
        let diagram = try Self.read("""
            requirementDiagram
                  accTitle: test title
                  accDescr: my chart description
                  element test_name {
                  type: test_type
                  docref: test_ref
                  }
            """)
        XCTAssertEqual(diagram.accessibilityTitle, "test title")
        XCTAssertEqual(diagram.accessibilityDescription, "my chart description")
    }

    func testAccessibilityTitleAndDescriptionOfSeveralLines() throws {
        let diagram = try Self.read("""
            requirementDiagram
                  accTitle: test title
                  accDescr {
                    my chart description
            line 2
                  }
                  element test_name {
                  type: test_type
                  docref: test_ref
                  }
            """)
        XCTAssertEqual(diagram.accessibilityTitle, "test title")
        XCTAssertEqual(diagram.accessibilityDescription, "my chart description\nline 2")
    }

    func testAFullRelationshipDefinition() throws {
        let diagram = try Self.read("requirementDiagram\n\na - contains -> b")
        XCTAssertTrue(diagram.requirements.isEmpty)
        XCTAssertTrue(diagram.elements.isEmpty)
        XCTAssertEqual(diagram.relations, [RequirementDiagramRelation(kind: .contains, source: "a", target: "b")])
    }

    func testEveryKindOfRequirement() throws {
        let kinds: [(String, RequirementKind)] = [("requirement", .requirement), ("functionalRequirement", .functionalRequirement),
                                                   ("interfaceRequirement", .interfaceRequirement), ("performanceRequirement", .performanceRequirement),
                                                   ("physicalRequirement", .physicalRequirement), ("designConstraint", .designConstraint)]
        for (keyword, kind) in kinds {
            XCTAssertEqual(try Self.read(Self.requirementText(kind: keyword)).requirements.first?.kind, kind, keyword)
        }
        XCTAssertEqual(RequirementKind.functionalRequirement.rawValue, "Functional Requirement")
    }

    func testEveryRiskAndVerificationMethod() throws {
        for risk in RequirementRisk.allCases {
            XCTAssertEqual(try Self.read(Self.requirementText(kind: "designConstraint", risk: risk.rawValue)).requirements.first?.risk, risk)
        }
        for method in RequirementVerificationMethod.allCases {
            XCTAssertEqual(try Self.read(Self.requirementText(kind: "designConstraint", method: method.rawValue)).requirements.first?.verificationMethod, method)
        }
    }

    func testEveryRelationshipBothWays() throws {
        for kind in RequirementRelationKind.allCases {
            let forward = try Self.read("requirementDiagram\n\na - \(kind.rawValue) -> b")
            XCTAssertEqual(forward.relations, [RequirementDiagramRelation(kind: kind, source: "a", target: "b")])
            let backward = try Self.read("requirementDiagram\n\na <- \(kind.rawValue) - b\n")
            XCTAssertEqual(backward.relations, [RequirementDiagramRelation(kind: kind, source: "b", target: "a")])
        }
    }

    func testStylingARequirementAnElementAndBothAtOnce() throws {
        let requirement = try Self.read("requirementDiagram\n\nrequirement test_requirement {\n}\nstyle test_requirement fill:#f9f,stroke:#333,stroke-width:4px\n")
        XCTAssertEqual(requirement.requirements.first?.styleDeclarations, ["fill:#f9f", "stroke:#333", "stroke-width:4px"])
        let element = try Self.read("requirementDiagram\n\nelement test_element {\n}\nstyle test_element fill:#f9f,stroke:#333,stroke-width:4px\n")
        XCTAssertEqual(element.elements.first?.styleDeclarations, ["fill:#f9f", "stroke:#333", "stroke-width:4px"])
        let both = try Self.read("""
            requirementDiagram

            requirement test_requirement {
            }
            element test_element {
            }
            style test_requirement,test_element fill:#f9f,stroke:#333,stroke-width:4px

            """)
        XCTAssertEqual(both.requirements.first?.styleDeclarations, ["fill:#f9f", "stroke:#333", "stroke-width:4px"])
        XCTAssertEqual(both.elements.first?.styleDeclarations, ["fill:#f9f", "stroke:#333", "stroke-width:4px"])
    }

    func testDefiningOneClassAndSeveralAtOnce() throws {
        let one = try Self.read("requirementDiagram\n\nclassDef myClass fill:#f9f,stroke:#333,stroke-width:4px\n")
        XCTAssertEqual(one.styleClasses, [RequirementDiagramStyleClass(name: "myClass", styleDeclarations: ["fill:#f9f", "stroke:#333", "stroke-width:4px"],
                                                                       textStyleDeclarations: [])])
        let several = try Self.read("requirementDiagram\n\nclassDef firstClass,secondClass fill:#f9f,stroke:#333,stroke-width:4px\n")
        XCTAssertEqual(several.styleClasses.map(\.name), ["firstClass", "secondClass"])
        XCTAssertEqual(several.styleClasses.map(\.styleDeclarations), Array(repeating: ["fill:#f9f", "stroke:#333", "stroke-width:4px"], count: 2))
    }

    func testAssigningClassesByStatementAndShorthand() throws {
        let statement = try Self.read("requirementDiagram\n\nrequirement myReq {\n}\nclassDef myClass fill:#f9f,stroke:#333,stroke-width:4px\nclass myReq myClass\n")
        XCTAssertEqual(statement.requirements.first?.classNames, ["default", "myClass"])
        let several = try Self.read("""
            requirementDiagram

            requirement req {
            }
            element elem {
            }
            classDef class1,class2 fill:#f9f,stroke:#333,stroke-width:4px
            class req,elem class1,class2

            """)
        XCTAssertEqual(several.requirements.first?.classNames, ["default", "class1", "class2"])
        XCTAssertEqual(several.elements.first?.classNames, ["default", "class1", "class2"])
        let shorthand = try Self.read("requirementDiagram\n\nrequirement myReq {\n}\nclassDef class1 fill:#f9f\nclassDef class2 color:blue\nmyReq:::class1,class2\n")
        XCTAssertEqual(shorthand.requirements.first?.classNames, ["default", "class1", "class2"])
        XCTAssertEqual(shorthand.styleClasses.last?.textStyleDeclarations, ["color:blue"])
    }

    func testAssigningClassesWhereARequirementOrElementIsDefined() throws {
        let diagram = try Self.read("""
            requirementDiagram

            requirement myReq:::class1 {
            }
            element myElem:::class1,class2 {
            }

            classDef class1 fill:#f9f,stroke:#333,stroke-width:4px
            classDef class2 color:blue

            """)
        XCTAssertEqual(diagram.requirements.first?.classNames, ["default", "class1"])
        XCTAssertEqual(diagram.elements.first?.classNames, ["default", "class1", "class2"])
        // A class defined after it is given copies its declarations onto the nodes that have it.
        XCTAssertEqual(diagram.elements.first?.styleDeclarations, ["fill:#f9f", "stroke:#333", "stroke-width:4px", "color:blue"])
    }

    /// Mermaid's spec: `__proto__` and `constructor` are names like any other.
    func testThePrototypesNamesAreNamesOfRequirementsAndElements() throws {
        for name in ["__proto__", "constructor"] {
            let requirement = try Self.read("requirementDiagram\n      requirement \(name) {\n        id: 1\n        text: the test text.\n        risk: high\n        verifymethod: test\n      }")
            XCTAssertEqual(requirement.requirements.map(\.name), [name])
            XCTAssertEqual(try Self.read("requirementDiagram\n      element \(name) {\n        type: simulation\n      }").elements.map(\.name), [name])
        }
    }

    func testEveryDirection() throws {
        let directions: [(String, FlowchartDirection)] = [("TB", .topToBottom), ("BT", .bottomToTop), ("LR", .leftToRight), ("RL", .rightToLeft)]
        for (written, direction) in directions {
            XCTAssertEqual(try Self.read("requirementDiagram\n\ndirection \(written)\n").direction, direction, written)
        }
    }
}
