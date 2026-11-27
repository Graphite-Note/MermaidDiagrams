/**
 * File: RequirementStyleCopiesTests.swift
 * ---------------------------------------
 * Layer: Tests
 * Description: Requirement diagrams whose classes and styles copy declarations onto their boxes few times, and so many
 *              times that the layout keeps each declaration it reads: laid out alike to the bit by the layout and the 0.7.0
 *              engine kept as the reference, with the same count of declarations not applied.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

@testable import MermaidDiagrams
import XCTest

final class RequirementStyleCopiesTests: XCTestCase {
    /// `boxCount` requirements and elements given classes and styles, the default class among them, so that about
    /// `boxCount` times the declarations' count of copies are made.
    private static func diagram(boxCount: Int, declarations: String) -> String {
        var source = "requirementDiagram\n"
        for index in 0..<boxCount {
            source += index.isMultiple(of: 3) ? "element e\(index) {\n  type: t\n}\n" : "requirement r\(index) {\n  id: \(index)\n  risk: low\n}\n"
        }
        source += "classDef default \(declarations)\n"
        source += "classDef hot fill:#f00,font-weight:bold\n"
        for index in stride(from: 0, to: boxCount, by: 2) { source += "class \(index.isMultiple(of: 3) ? "e" : "r")\(index) hot\n" }
        source += "style \(boxCount > 1 ? "r1" : "e0") stroke:#00f,stroke-width:3px,color:#123\n"
        return source
    }

    func testFewAndManyCopiesAreLaidOutAsTheReferenceLaysThemOut() throws {
        var compared = 0
        for boxCount in [1, 4, 20, 90, 200] {
            for declarations in ["fill:#eee", "fill:#eee,stroke:#333,stroke-dasharray: 5 5,font-size:12px", "color:red,unknown:1,fill:#0f0"] {
                let source = Self.diagram(boxCount: boxCount, declarations: declarations)
                guard case .requirement(let diagram) = try MermaidDiagramReader.read(source, limits: .standard) else { return XCTFail("not read") }
                let copyCount = diagram.model.numbers.count
                XCTAssertNil(RequirementLayoutEquivalenceTests.firstDifference(diagram, limits: .standard), "\(boxCount) boxes, \(copyCount) copies")
                let layout = try RequirementLayoutEngine.layout(diagram, typography: DiagramSceneSamples.typography, limits: .standard)
                XCTAssertEqual(layout.unappliedStatementCount, diagram.unappliedStatementCount)
                compared += 1
            }
        }
        XCTAssertEqual(compared, 15)
        // Both ways of reading were taken: a diagram of few copies and one of more than the layout reads without keeping.
        let few = try MermaidDiagramReader.read(Self.diagram(boxCount: 4, declarations: "fill:#eee"), limits: .standard)
        let many = try MermaidDiagramReader.read(Self.diagram(boxCount: 200, declarations: "fill:#eee,stroke:#333"), limits: .standard)
        guard case .requirement(let fewDiagram) = few, case .requirement(let manyDiagram) = many else { return XCTFail("not read") }
        XCTAssertLessThanOrEqual(fewDiagram.model.numbers.count, RequirementStyleResolution.largestUncachedCopyCount)
        XCTAssertGreaterThan(manyDiagram.model.numbers.count, RequirementStyleResolution.largestUncachedCopyCount)
    }
}
