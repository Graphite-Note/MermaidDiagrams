/**
 * File: GraphTypeLayoutSafetyTests.swift
 * --------------------------------------
 * Layer: Tests
 * Description: Hostile state, class, entity relationship, requirement and use case diagrams (deep nesting, many items,
 *              long lines) are laid out or refused within the limits, quickly and never quadratically, and exactly as
 *              the 0.7.0 engines kept as references lay them out.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import Foundation
import XCTest
@testable import MermaidDiagrams

final class GraphTypeLayoutSafetyTests: XCTestCase {
    private static var readingLimits: MermaidDiagramLimits {
        var limits = MermaidDiagramLimits.standard
        limits.maximumSourceBytes = 2_000_000
        return limits
    }

    /// Reads `source`, checks its layout against the reference, and returns how long the layout took.
    private func assertHostile(_ source: String, bound: TimeInterval, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let result = Result { try MermaidDiagramReader.read(source, limits: Self.readingLimits) }
        guard case .success(let diagram) = result else { return XCTFail("\(message) is not read: \(result)", file: file, line: line) }
        let read: MermaidDiagram? = diagram
        let started = Date()
        let difference: String?
        switch read {
        case .stateDiagram(let diagram)?: difference = StateDiagramLayoutEquivalenceTests.firstDifference(diagram, limits: .standard)
        case .classDiagram(let diagram)?: difference = ClassDiagramLayoutEquivalenceTests.firstDifference(diagram, limits: .standard)
        case .entityRelationship(let diagram)?: difference = EntityRelationshipLayoutEquivalenceTests.firstDifference(diagram, limits: .standard)
        case .requirement(let diagram)?: difference = RequirementLayoutEquivalenceTests.firstDifference(diagram, limits: .standard)
        case .useCase(let diagram)?: difference = UseCaseLayoutEquivalenceTests.firstDifference(diagram, limits: .standard)
        default: return XCTFail("\(message) is not one of the five types", file: file, line: line)
        }
        XCTAssertNil(difference, message, file: file, line: line)
        XCTAssertLessThan(Date().timeIntervalSince(started), bound, message, file: file, line: line)
    }

    func testDeeplyNestedCompositeStatesAndNamespacesAndGroups() {
        let depth = 60
        var state = "stateDiagram-v2\n"
        for level in 0..<depth { state += String(repeating: " ", count: level) + "state S\(level) {\n" }
        state += "  a --> b\n" + String(repeating: "}\n", count: depth)
        assertHostile(state, bound: 60, "nested composite states")
        var classes = "classDiagram\n"
        for level in 0..<depth { classes += "namespace N\(level) {\n" }
        classes += "class A\nclass B\n" + String(repeating: "}\n", count: depth) + "A --> B\n"
        assertHostile(classes, bound: 60, "nested namespaces")
        var groups = "erDiagram\n"
        for level in 0..<depth { groups += "subgraph g\(level)\n" }
        groups += "A ||--o{ B : has\n" + String(repeating: "end\n", count: depth)
        assertHostile(groups, bound: 60, "nested ER groups")
    }

    func testManyItems() {
        var state = "stateDiagram-v2\n[*] --> s0\n"
        for index in 1..<1_500 { state += "s\(index - 1) --> s\(index) : e\(index)\n" }
        assertHostile(state, bound: 120, "a long chain of states")
        var classes = "classDiagram\nclass Wide {\n"
        for index in 0..<1_500 { classes += "  +int member\(index)\n" }
        classes += "}\nWide --> Other\n"
        assertHostile(classes, bound: 60, "a class of many members")
        var entities = "erDiagram\nWIDE {\n"
        for index in 0..<1_500 { entities += "  string column\(index) PK \"comment \(index)\"\n" }
        entities += "}\nWIDE ||--o{ OTHER : has\n"
        assertHostile(entities, bound: 60, "an entity of many attributes")
        var requirements = "requirementDiagram\n"
        for index in 0..<300 { requirements += "requirement r\(index) {\nid: \(index)\ntext: t\(index)\n}\n" }
        for index in 1..<300 { requirements += "r0 - contains -> r\(index)\n" }
        assertHostile(requirements, bound: 120, "a requirement containing many")
        var useCases = "usecase-beta\nactor User\n"
        for index in 0..<300 { useCases += "User --> Case\(index)\n" }
        assertHostile(useCases, bound: 120, "an actor with many use cases")
    }

    func testLongLines() {
        let long = String(repeating: "word ", count: 4_000)
        assertHostile("stateDiagram-v2\nA --> B : \(long)\nnote right of A : \(long)\n", bound: 60, "long state texts")
        assertHostile("classDiagram\nclass A {\n  +\(long)\n}\nA --> B : \(long)\n", bound: 60, "long class texts")
        assertHostile("erDiagram\nA ||--o{ B : \"\(long)\"\nA {\n  string x \"\(long)\"\n}\n", bound: 60, "long ER texts")
        assertHostile("requirementDiagram\nrequirement r {\ntext: \"\(long)\"\n}\nelement e {\ntype: x\n}\ne - satisfies -> r\n", bound: 60, "long requirement texts")
        assertHostile("usecase-beta\nactor U\nU -- \"\(long)\" --> C\n", bound: 60, "long use case texts")
    }
}
