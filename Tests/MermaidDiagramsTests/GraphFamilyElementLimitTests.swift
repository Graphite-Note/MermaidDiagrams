/**
 * File: GraphFamilyElementLimitTests.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: A state, class, entity relationship or requirement diagram's scene records its paths under the limits
 *              its preparation is given: a path past their element limit makes the scene say so, and the preparation
 *              refuses it as too many path elements instead of drawing it with the path missing.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import CoreGraphics
import XCTest
@testable import MermaidDiagrams

final class GraphFamilyElementLimitTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))
    /// Limits whose element limit is the least a lane has, 2¹⁶ verbs.
    private let smallLimits = MermaidDiagramLimits(maximumSourceBytes: 50_000, maximumNodeCount: 1, maximumEdgeCount: 1, maximumLayoutPointCount: 1)

    /// A path of more line segments than the small limits let a lane hold, far fewer than the standard limits do.
    private var longPath: DiagramPath {
        let segmentCount = DiagramSceneWorkspace.elementLimit(for: smallLimits) + 10
        return DiagramPath(start: .zero, segments: (0..<segmentCount).map { index in .line(to: CGPoint(x: index % 50, y: index / 50)) })
    }

    private func read(_ source: String) throws -> MermaidDiagram {
        try MermaidDiagramReader.read(source, limits: .standard)
    }

    /// The scene made under the small limits says it went past their element limit and its preparation refuses it; the
    /// same scene made under the standard limits is whole.
    private func assertRefusedUnderSmallLimits(_ scene: (MermaidDiagramLimits) -> DiagramScene, file: StaticString = #filePath, line: UInt = #line) {
        let limit = DiagramSceneWorkspace.elementLimit(for: smallLimits)
        let refused = scene(smallLimits)
        XCTAssertEqual(refused.exceededPathElementLimit, limit, file: file, line: line)
        XCTAssertThrowsError(try MermaidDiagramPreparation.refuseIncomplete(refused, limits: .standard), file: file, line: line) { error in
            XCTAssertEqual(error as? MermaidDiagramPreparationFailure, .tooManyPathElements(limit: limit), file: file, line: line)
        }
        let whole = scene(.standard)
        XCTAssertNil(whole.exceededPathElementLimit, file: file, line: line)
        XCTAssertNoThrow(try MermaidDiagramPreparation.refuseIncomplete(whole, limits: .standard), file: file, line: line)
    }

    /// A scene within the small limits is drawn as under the standard ones.
    private func assertSameDrawing(_ scene: DiagramScene, _ standard: DiagramScene, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNil(scene.exceededPathElementLimit, file: file, line: line)
        let writer = DiagramSVGWriter()
        XCTAssertEqual(writer.document(of: scene, diagramType: "test"), writer.document(of: standard, diagramType: "test"), file: file, line: line)
    }

    func testAStateDiagramsScenePastItsElementLimitIsRefused() throws {
        guard case .stateDiagram(let diagram) = try read("stateDiagram-v2\n  [*] --> A\n  A --> B : go\n  B --> [*]") else { return XCTFail("not a state diagram") }
        let layout = try StateDiagramLayoutEngine.layout(diagram, typography: typography, limits: .standard)
        let lengthened = StateDiagramLayout(size: layout.size, font: layout.font, states: layout.states, transitions: layout.transitions,
                                            notes: layout.notes, title: layout.title, composites: layout.composites, regionDividers: [longPath])
        assertRefusedUnderSmallLimits { limits in DiagramScene(layout: lengthened, limits: limits) }
        assertSameDrawing(DiagramScene(layout: layout, limits: smallLimits), DiagramScene(layout: layout))
    }

    func testAClassDiagramsScenePastItsElementLimitIsRefused() throws {
        guard case .classDiagram(let diagram) = try read("classDiagram\n  Animal <|-- Duck\n  Animal : +int age") else { return XCTFail("not a class diagram") }
        let layout = try ClassDiagramLayoutEngine.layout(diagram, typography: typography, limits: .standard)
        var relations = layout.relations
        relations[0].path = longPath
        let lengthened = ClassDiagramLayout(size: layout.size, font: layout.font, classes: layout.classes, notes: layout.notes, interfaces: layout.interfaces,
                                            relations: relations, noteLinks: layout.noteLinks, title: layout.title, namespaces: layout.namespaces)
        assertRefusedUnderSmallLimits { limits in DiagramScene(layout: lengthened, limits: limits) }
        assertSameDrawing(DiagramScene(layout: layout, limits: smallLimits), DiagramScene(layout: layout))
    }

    func testAnEntityRelationshipDiagramsScenePastItsElementLimitIsRefused() throws {
        guard case .entityRelationship(let diagram) = try read("erDiagram\n  CUSTOMER ||--o{ ORDER : places\n  ORDER { string id }") else {
            return XCTFail("not an entity relationship diagram")
        }
        let layout = try EntityRelationshipLayoutEngine.layout(diagram, typography: typography, limits: .standard)
        var relationships = layout.relationships
        relationships[0].path = longPath
        let lengthened = EntityRelationshipLayout(size: layout.size, font: layout.font, entities: layout.entities, relationships: relationships,
                                                  title: layout.title, subgraphs: layout.subgraphs)
        assertRefusedUnderSmallLimits { limits in DiagramScene(layout: lengthened, limits: limits) }
        assertSameDrawing(DiagramScene(layout: layout, limits: smallLimits), DiagramScene(layout: layout))
    }

    func testARequirementDiagramsScenePastItsElementLimitIsRefused() throws {
        let source = "requirementDiagram\n  requirement checkout_req {\n    id: 1\n    text: pay\n  }\n  element shop {\n    type: service\n  }\n  shop - satisfies -> checkout_req"
        guard case .requirement(let diagram) = try read(source) else { return XCTFail("not a requirement diagram") }
        let layout = try RequirementLayoutEngine.layout(diagram, typography: typography, limits: .standard)
        var relations = layout.relations
        relations[0].path = longPath
        let lengthened = RequirementLayout(size: layout.size, font: layout.font, boxes: layout.boxes, relations: relations, title: layout.title)
        assertRefusedUnderSmallLimits { limits in DiagramScene(layout: lengthened, limits: limits) }
        assertSameDrawing(DiagramScene(layout: layout, limits: smallLimits), DiagramScene(layout: layout))
    }
}
