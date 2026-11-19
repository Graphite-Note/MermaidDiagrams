/**
 * File: ClassDiagramNamespaceTests.swift
 * --------------------------------------
 * Layer: Tests
 * Description: Class diagram namespaces as Pele nests and draws them: dotted names, titles, the flat option, the boxes.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class ClassDiagramNamespaceTests: XCTestCase {
    private let accuracy: CGFloat = 0.01
    private let measurers = ClassDiagramTextMeasurers(names: UniformWidthTextMeasurer(),
                                                      members: UniformWidthTextMeasurer(characterWidth: 7, fontSize: 14, lineHeight: 21),
                                                      marks: UniformWidthTextMeasurer(characterWidth: 6, fontSize: 13, lineHeight: 20))

    private func tree(_ source: String) throws -> ClassDiagramNamespaceTree {
        ClassDiagramNamespaceTree(diagram: try ClassDiagramReading.classDiagram(source))
    }

    private func layout(_ source: String) throws -> ClassDiagramLayout {
        try ClassDiagramLayoutEngine.layout(try ClassDiagramReading.classDiagram(source), measurers: measurers, font: UniformWidthLayout.font,
                                            limits: .standard)
    }

    /// Mermaid's documentation example of dotted namespace names, as the benchmark's corpus holds it.
    private let dottedNames = "classDiagram\n    namespace Company.Engineering.Backend {\n        class Developer {\n            +writeCode()\n        }\n    }\n"
        + "    namespace Company.Engineering.Frontend {\n        class Designer {\n            +createMockup()\n        }\n    }\n"
        + "    namespace Company.Engineering {\n        class TechLead {\n            +planSprint()\n        }\n    }\n"
        + "    TechLead --> Developer : leads\n    TechLead --> Designer : leads\n"

    func testADottedNameIsANamespaceInsideItsPrefixesAndOneNameIsOneNamespace() throws {
        let namespaces = try tree(dottedNames)
        XCTAssertEqual(namespaces.namespaces.map(\.identifier),
                       ["Company", "Company.Engineering", "Company.Engineering.Backend", "Company.Engineering.Frontend"])
        XCTAssertEqual(namespaces.namespaces.map(\.title), ["Company", "Engineering", "Backend", "Frontend"].map(DiagramLabel.init))
        XCTAssertEqual(namespaces.namespaces.map(\.parent), [nil, 0, 1, 1])
        XCTAssertEqual(namespaces.namespaces.map(\.isDeclared), [false, true, true, true])
        // Developer, Designer, TechLead.
        XCTAssertEqual(namespaces.classNamespaces, [2, 3, 1])
    }

    func testAWrittenTitleIsKeptAndNestedStatementsNest() throws {
        XCTAssertEqual(try tree("classDiagram\nnamespace Auth[\"Authentication Service\"] {\nclass UserService\n}").namespaces.map(\.title),
                       [DiagramLabel("Authentication Service")])
        let nested = try tree("classDiagram\nnamespace Platform {\nnamespace Auth {\nclass UserService\n}\nclass Gateway\n}")
        XCTAssertEqual(nested.namespaces.map(\.identifier), ["Platform", "Platform.Auth"])
        XCTAssertEqual(nested.namespaces.map(\.title), [DiagramLabel("Platform"), DiagramLabel("Auth")])
        XCTAssertEqual(nested.classNamespaces, [1, 0])
    }

    func testWithoutHierarchicalNamespacesOnlyTheDeclaredOnesAreBoxesTitledInFull() throws {
        let source = "---\nconfig:\n  class:\n    hierarchicalNamespaces: false\n---\n" + dottedNames
        let diagram = try ClassDiagramReading.classDiagram(source)
        XCTAssertFalse(diagram.hierarchicalNamespaces)
        let namespaces = ClassDiagramNamespaceTree(diagram: diagram)
        XCTAssertEqual(namespaces.namespaces.map(\.title).map { title in title.lines }, [["Company.Engineering"], ["Company.Engineering.Backend"],
                                                                                         ["Company.Engineering.Frontend"]])
        XCTAssertEqual(namespaces.namespaces.map(\.parent), [nil, nil, nil])
        XCTAssertEqual(namespaces.classNamespaces, [1, 2, 0])
    }

    func testEachClassIsInsideItsNamespacesBoxAndNestedBoxesNest() throws {
        let laidOut = try layout(dottedNames)
        XCTAssertEqual(laidOut.namespaces.count, 4)
        XCTAssertEqual(laidOut.namespaces.map(\.depth), [0, 1, 2, 2])
        let boxes = laidOut.namespaces.map(\.frame)
        XCTAssertTrue(boxes[0].contains(boxes[1]))
        XCTAssertTrue(boxes[1].contains(boxes[2]))
        XCTAssertTrue(boxes[1].contains(boxes[3]))
        XCTAssertFalse(boxes[2].intersects(boxes[3]))
        XCTAssertTrue(boxes[2].contains(laidOut.classes[0].frame))
        XCTAssertTrue(boxes[3].contains(laidOut.classes[1].frame))
        XCTAssertTrue(boxes[1].contains(laidOut.classes[2].frame))
        XCTAssertFalse(boxes[2].intersects(laidOut.classes[2].frame))
        XCTAssertEqual(laidOut.relations.count, 2)
        XCTAssertTrue(CGRect(origin: .zero, size: laidOut.size).contains(boxes[0]))
    }

    func testABoxHasPelesPaddingAndItsTitleAlongItsTop() throws {
        // "Shapes" is 48 points wide and 24 high: 20 points of room on the sides and below, the title and 16 above.
        let laidOut = try layout("classDiagram\nnamespace Shapes {\nclass Triangle\n}")
        let box = try XCTUnwrap(laidOut.namespaces.first).frame
        let triangle = laidOut.classes[0].frame
        XCTAssertEqual(triangle.minX - box.minX, 20, accuracy: accuracy)
        XCTAssertEqual(box.maxY - triangle.maxY, 20, accuracy: accuracy)
        XCTAssertEqual(triangle.minY - box.minY, 24 + 16, accuracy: accuracy)
        let title = try XCTUnwrap(laidOut.namespaces.first?.title)
        XCTAssertEqual(title.center.y, box.minY + 8 + 12, accuracy: accuracy)
    }

    func testARelationIntoANamespaceWidensItForItsTitle() throws {
        // A relation crosses into "Shapes", which grows by its title and 24 points: 48 + 40 - 12 + 72.
        let laidOut = try layout("classDiagram\nnamespace Shapes {\nclass A\n}\nB --> A")
        XCTAssertEqual(try XCTUnwrap(laidOut.namespaces.first).frame.width, 148, accuracy: accuracy)
    }

    func testAnEmptyNamespaceIsABoxAroundItsTitle() throws {
        let laidOut = try layout("classDiagram\nnamespace Empty {\n}\nclass A")
        let box = try XCTUnwrap(laidOut.namespaces.first).frame
        XCTAssertEqual(box.width, 80, accuracy: accuracy)
        XCTAssertEqual(box.height, 24 + 40, accuracy: accuracy)
    }

    func testTheSceneDrawsTheBoxesBehindTheRelations() throws {
        let scene = DiagramScene(layout: try layout(dottedNames))
        let firstCluster = try XCTUnwrap(scene.items.firstIndex { item in
            if case .shape(let shape) = item { return shape.part == .cluster }
            return false
        })
        let firstEdge = try XCTUnwrap(scene.items.firstIndex { item in
            if case .shape(let shape) = item { return shape.part == .edge }
            return false
        })
        XCTAssertLessThan(firstCluster, firstEdge)
        XCTAssertEqual(scene.texts.filter { text in text.part == .clusterLabel }.count, 4)
    }
}
