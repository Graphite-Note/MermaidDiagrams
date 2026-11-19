/**
 * File: WardleyMapParserTests.swift
 * ---------------------------------
 * Layer: Tests
 * Description: The inputs of Mermaid 12.1.0's Wardley specs (wardleyParser.spec.ts and wardleyBuilder.spec.ts, as Pele
 *              ports them in tests/compat/wardley), the lexer's quirks, the builder's merging, and the errors.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class WardleyMapParserTests: XCTestCase {
    private func map(_ source: String) throws -> WardleyMap {
        try WardleyMapReading.map(source)
    }

    private func node(_ map: WardleyMap, _ label: String) -> WardleyMapNode? {
        map.nodes.first { node in node.label == label }
    }

    // MARK: Mermaid's parser spec

    func testComponentsAndLinks() throws {
        let parsed = try map("wardley-beta\ntitle Example\ncomponent Alpha [0.2, 0.1]\ncomponent Beta [0.4, 0.3]\nAlpha -> Beta")
        XCTAssertEqual(parsed.nodes.count, 2)
        XCTAssertEqual(parsed.links.count, 1)
        XCTAssertEqual(parsed.title, "Example")
    }

    func testEvolutionStagesPlainWithSecondNamesAndWithBoundaries() throws {
        XCTAssertEqual(try map("wardley-beta\ntitle Test\nevolution Genesis -> Custom -> Product -> Commodity\ncomponent A [0.5, 0.5]").stages,
                       ["Genesis", "Custom", "Product", "Commodity"])
        XCTAssertEqual(try map("wardley-beta\nevolution Genesis / Concept -> Custom / Emerging -> Product / Converging -> Commodity / Accepted").stages,
                       ["Genesis / Concept", "Custom / Emerging", "Product / Converging", "Commodity / Accepted"])
        let widths = try map("wardley-beta\nevolution Genesis@0.3 -> Custom@0.6 -> Product@0.85 -> Commodity@1.0\ncomponent A [0.5, 0.5]")
        XCTAssertEqual(widths.stages, ["Genesis", "Custom", "Product", "Commodity"])
        XCTAssertEqual(widths.stageBoundaries, [0.3, 0.6, 0.85, 1.0])
    }

    func testPipelineComponentsTakeTheirParentsVisibility() throws {
        let parsed = try map("""
            wardley-beta
            title Test Pipeline
            component Kettle [0.45, 0.57]
            pipeline Kettle {
              component Campfire Kettle [0.35] label [-60, 35]
              component Electric Kettle [0.53]
            }
            """)
        let kettle = try XCTUnwrap(node(parsed, "Kettle"))
        let campfire = try XCTUnwrap(node(parsed, "Campfire Kettle"))
        let electric = try XCTUnwrap(node(parsed, "Electric Kettle"))
        XCTAssertEqual(campfire.point.y, kettle.point.y)
        XCTAssertEqual(electric.point.y, kettle.point.y)
        XCTAssertEqual(campfire.point.x, 35, accuracy: 1e-9)
        XCTAssertEqual(electric.point.x, 53, accuracy: 1e-9)
        XCTAssertEqual(campfire.identifier, "Kettle_Campfire Kettle")
        XCTAssertEqual([campfire.labelOffsetX, campfire.labelOffsetY], [-60, 35])
        XCTAssertTrue(kettle.isPipelineParent)
        XCTAssertTrue(campfire.isInPipeline)
        XCTAssertEqual(parsed.pipelines, [WardleyMapPipeline(nodeIdentifier: "Kettle", componentIdentifiers: ["Kettle_Campfire Kettle", "Kettle_Electric Kettle"])])
    }

    func testNotesAnnotationsAnchorsAndEvolutions() throws {
        XCTAssertEqual(try map("wardley-beta\ncomponent API [0.6, 0.7]\nnote \"Critical decision point\" [0.65, 0.55]").notes.map(\.text), ["Critical decision point"])
        let annotated = try map("wardley-beta\nannotations [0.1, 0.9]\nannotation 1,[0.6, 0.65] \"Critical component\"\nannotation 2,[0.5, 0.5] \"Performance layer\"")
        XCTAssertEqual(annotated.annotations.map(\.text), ["Critical component", "Performance layer"])
        let anchors = try map("wardley-beta\nanchor Business [0.95, 0.63]\nanchor Public [0.95, 0.78]\ncomponent Tea [0.63, 0.81]").nodes.filter { node in node.kind == .anchor }
        XCTAssertEqual(anchors.map(\.label), ["Business", "Public"])
        let evolved = try map("wardley-beta\ncomponent Kettle [0.35, 0.43]\nevolve Kettle 0.62")
        XCTAssertEqual(evolved.trends.count, 1)
        XCTAssertEqual(evolved.trends[0].target.x, 62, accuracy: 1e-9)
    }

    func testSourcingAndSize() throws {
        let decorated = try map("wardley-beta\ncomponent API [0.6, 0.7] (build)\ncomponent Database [0.4, 0.5] (buy)\ncomponent Cache [0.5, 0.6] (outsource)")
        XCTAssertEqual(decorated.nodes.map(\.sourcing), [.build, .buy, .outsource])
        XCTAssertEqual(try map("wardley-beta\nsize [1200, 900]\ncomponent A [0.5, 0.5]").size, WardleyMapSize(width: 1200, height: 900))
    }

    func testQuotedNamesPortsLabelsAndCoordinatesInPercent() throws {
        let parsed = try map("""
            wardley-beta
            title Coordinate Handling
            component "Mobile App" [0.2, 0.4] (build) (inertia)
            component API [0.3, 0.5]
            "Mobile App" +<> API; constraint
            note "Check dependencies" [0.25, 0.45]
            annotations [0.10, 0.90]
            annotation 1,[0.60, 0.65] "Critical component"
            accelerator "Cloud Native" [0.20, 0.85]
            deaccelerator "Legacy Data" [0.40, 0.35]
            """)
        let mobile = try XCTUnwrap(node(parsed, "Mobile App"))
        XCTAssertEqual(mobile.point.x, 40, accuracy: 1e-9)
        XCTAssertEqual(mobile.point.y, 20, accuracy: 1e-9)
        XCTAssertEqual(mobile.sourcing, .build)
        XCTAssertTrue(mobile.hasInertia)
        XCTAssertEqual(parsed.links.first?.flow, .bidirectional)
        XCTAssertEqual(parsed.links.first?.label, "constraint")
        XCTAssertEqual(parsed.notes[0].point.x, 45, accuracy: 1e-9)
        XCTAssertEqual(parsed.notes[0].point.y, 25, accuracy: 1e-9)
        XCTAssertEqual(parsed.annotationsBox, WardleyMapPoint(x: 90, y: 10))
        XCTAssertEqual(parsed.annotations[0].point, WardleyMapPoint(x: 65, y: 60))
        XCTAssertEqual(parsed.accelerators[0], WardleyMapForce(name: "Cloud Native", point: WardleyMapPoint(x: 85, y: 20)))
        XCTAssertEqual(parsed.deaccelerators[0], WardleyMapForce(name: "Legacy Data", point: WardleyMapPoint(x: 35, y: 40)))
    }

    func testHyphensInNamesAndArrowsWithoutSpaces() throws {
        let hyphenated = try map("wardley-beta\ncomponent real-time processing [0.5, 0.5]\ncomponent end-user [0.8, 0.9]\nreal-time processing -> end-user")
        XCTAssertEqual(hyphenated.links.map(\.source), ["real-time processing"])
        XCTAssertEqual(hyphenated.links.map(\.target), ["end-user"])
        XCTAssertEqual(try XCTUnwrap(node(hyphenated, "end-user")).point, WardleyMapPoint(x: 90, y: 80))
        let anchor = try XCTUnwrap(node(try map("wardley-beta\nanchor on-call engineer [0.9, 0.95]"), "on-call engineer"))
        XCTAssertEqual(anchor.kind, .anchor)
        XCTAssertEqual(anchor.point.x, 95, accuracy: 1e-9)
        XCTAssertEqual(try map("wardley-beta\ncomponent A [0.1, 0.1]\ncomponent B [0.2, 0.2]\nA->B").links.map(\.target), ["B"])
        XCTAssertEqual(try map("wardley-beta\ncomponent foo-bar [0.3, 0.3]\ncomponent baz [0.6, 0.6]\nfoo-bar->baz").links.map(\.source), ["foo-bar"])
        let pipeline = try map("wardley-beta\ncomponent Data Store [0.5, 0.5]\npipeline Data Store {\n  component real-time queue [0.3] label [-40, 20]\n  component batch-loader [0.7]\n}")
        XCTAssertEqual(try XCTUnwrap(node(pipeline, "real-time queue")).kind, .pipelineComponent)
        XCTAssertEqual(try XCTUnwrap(node(pipeline, "real-time queue")).labelOffsetX, -40)
        XCTAssertEqual(try XCTUnwrap(node(pipeline, "batch-loader")).point.x, 70, accuracy: 1e-9)
        XCTAssertNotNil(node(try map("wardley-beta\ncomponent foo--bar [0.3, 0.4]"), "foo--bar"))
        XCTAssertNotNil(node(try map("wardley-beta\ncomponent foo- [0.2, 0.3]"), "foo-"))
    }

    // MARK: Mermaid's builder spec

    func testLinksResolveByIdentifierThenByLabel() throws {
        let parsed = try map("wardley-beta\ncomponent Kettle [0.45, 0.57]\npipeline Kettle {\n  component Campfire Kettle [0.35]\n}\n"
                             + "component API [0.6, 0.7]\nAPI -> Campfire Kettle\nAPI -> Unknown")
        XCTAssertEqual(parsed.links.map(\.target), ["Kettle_Campfire Kettle", "Unknown"])
    }

    // MARK: Links, merging and errors

    func testLinkArrowsSetFlowDashesAndLabels() throws {
        let parsed = try map("wardley-beta\ncomponent User [0.9, 0.95]\ncomponent App [0.75, 0.75]\ncomponent API [0.6, 0.6]\ncomponent Cache [0.65, 0.45]\n"
                             + "User -> App\nApp +> API\nAPI +<> Cache\nCache +'backup'> API\nApp -.-> Cache\nAPI +< User")
        XCTAssertEqual(parsed.links.map(\.flow), [nil, .forward, .bidirectional, .forward, nil, .backward])
        XCTAssertEqual(parsed.links.map(\.label), [nil, nil, nil, "backup", nil, nil])
        XCTAssertEqual(parsed.links.map(\.isDashed), [false, false, false, false, true, false])
    }

    func testAComponentStatedAgainKeepsItsLabelOffsetUnlessItGivesOne() throws {
        let parsed = try map("wardley-beta\ncomponent A [0.1, 0.1] label [5, 6] (buy)\ncomponent A [0.2, 0.3]\nanchor A [0.4, 0.5]")
        XCTAssertEqual(parsed.nodes.count, 1)
        XCTAssertEqual(parsed.nodes[0].labelOffsetX, 5)
        XCTAssertNil(parsed.nodes[0].sourcing, "A component stated again sets its sourcing again")
        XCTAssertEqual(parsed.nodes[0].kind, .component, "Anchors are added before components, whatever the order written")
        XCTAssertEqual(parsed.nodes[0].point, WardleyMapPoint(x: 30, y: 20))
    }

    func testTheLexersQuirksAreMermaids() throws {
        XCTAssertEqual(WardleyMapReading.readError("wardley-beta\ncomponent A-->B [0.1, 0.2]\n"), .invalidSyntax(line: 2, problem: .wardleyMap(.expectedToken("'['"))),
                       "`A-`, then `->`: a name keeps a hyphen that is not before `>`")
        XCTAssertEqual(try map("wardley-beta\ncomponent Cup of Tea [0.79, 0.61]\ncomponent Tea [0.6, 0.8]\nCup of Tea -> Tea").links.first?.source, "Cup of Tea")
        XCTAssertEqual(WardleyMapReading.readError("wardley-beta\ntitled map\n"), .invalidSyntax(line: 2, problem: .wardleyMap(.expectedName)),
                       "A name that starts with `title` but not `title ` is a link's first end")
    }

    func testErrorsSayWhatBrokeOnWhichLine() {
        XCTAssertEqual(WardleyMapReading.readError("wardley-beta\ncomponent A [1, 0.5]"), .invalidSyntax(line: 2, problem: .wardleyMap(.expectedToken("WARDLEY_NUMBER"))))
        XCTAssertEqual(WardleyMapReading.readError("wardley-beta\ncomponent A [0.5, 0.5"), .invalidSyntax(line: 2, problem: .wardleyMap(.expectedToken("']'"))))
        XCTAssertEqual(WardleyMapReading.readError("wardley-beta\ncomponent A [0.5, 150.5]"), .invalidSyntax(line: 2, problem: .wardleyMap(.coordinateOutOfRange(150.5))))
        XCTAssertEqual(WardleyMapReading.readError("wardley-beta\npipeline Nothing {\n  component A [0.5]\n}"),
                       .invalidSyntax(line: 2, problem: .wardleyMap(.pipelineWithoutComponent("Nothing"))))
        XCTAssertEqual(WardleyMapReading.readError("wardley-beta\ncomponent A [0.5, 0.5] extra"), .invalidSyntax(line: 2, problem: .wardleyMap(.expectedLineEnd)))
        XCTAssertEqual(WardleyMapReading.readError("wardley-beta\n[0.5]"), .invalidSyntax(line: 2, problem: .wardleyMap(.expectedStatement)))
        XCTAssertEqual(WardleyMapReading.readError("wardley-beta\nA ->"), .invalidSyntax(line: 2, problem: .wardleyMap(.expectedName)))
        XCTAssertEqual(WardleyMapReading.readError("wardley-beta\ncomponent é [0.5, 0.5]"), .invalidSyntax(line: 2, problem: .unexpectedText("é [0.5, 0.5]")))
    }

    func testOptionsComeFromTheFrontMatter() throws {
        let options = try map("---\nconfig:\n  wardley-beta:\n    width: 700\n    showGrid: true\n---\nwardley-beta\ncomponent A [0.5, 0.5]").options
        XCTAssertEqual(options.width, 700)
        XCTAssertTrue(options.showsGrid)
    }

    func testCountsAreBoundedByTheLimits() {
        var limits = MermaidDiagramLimits.standard
        limits.maximumNodeCount = 2
        limits.maximumEdgeCount = 1
        XCTAssertEqual(WardleyMapReading.readError("wardley-beta\ncomponent A [0.1, 0.1]\ncomponent B [0.1, 0.1]\nnote \"n\" [0.1, 0.1]", limits: limits),
                       .tooManyNodes(limit: 2))
        XCTAssertEqual(WardleyMapReading.readError("wardley-beta\nA -> B\nB -> A", limits: limits), .tooManyEdges(limit: 1))
    }
}
