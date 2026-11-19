/**
 * File: WardleyMapLayoutEngineTests.swift
 * ---------------------------------------
 * Layer: Tests
 * Description: A Wardley map's layout as Pele's draw() makes it: the plot and its stages, coordinates in percent, links
 *              stopped at their nodes, a label's corner away from links, pipelines, evolutions, annotations and forces.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class WardleyMapLayoutEngineTests: XCTestCase {
    func testThePlotIsTheCanvasLessItsMarginsWithMermaidsFourStages() throws {
        let layout = try WardleyMapReading.uniformLayout("wardley-beta\ncomponent A [0.5, 0.5]")
        XCTAssertEqual(layout.plot.size, CGSize(width: 804, height: 504))
        XCTAssertEqual(layout.stageLabels.map { label in label.lines[0] }, ["Genesis", "Custom Built", "Product", "Commodity"])
        XCTAssertEqual(layout.stageLines.count, 3)
        XCTAssertEqual(layout.stageLines[0].start.x - layout.plot.minX, 201, accuracy: 1e-9)
        let small = try WardleyMapReading.uniformLayout("wardley-beta\nsize [100, 20000]\ncomponent A [0.5, 0.5]")
        XCTAssertEqual(small.plot.size, CGSize(width: 104, height: 9_904), "Each side kept from 200 to 10,000 before the margins")
        let custom = try WardleyMapReading.uniformLayout("wardley-beta\nevolution A@0.2 -> B@0.4 -> C@0.75 -> D@1.0\ncomponent X [0.5, 0.5]")
        XCTAssertEqual(custom.stageLines.map { line in line.start.x - custom.plot.minX }, [0.2 * 804, 0.4 * 804, 0.75 * 804].map { value in CGFloat(value) })
    }

    func testNodesSitAtTheirCoordinatesInPercent() throws {
        let layout = try WardleyMapReading.uniformLayout("wardley-beta\ncomponent A [0.25, 0.75]")
        let center = layout.nodes[0].center
        XCTAssertEqual(center.x - layout.plot.minX, 0.75 * 804, accuracy: 1e-9)
        XCTAssertEqual(center.y - layout.plot.minY, 504 - 0.25 * 504, accuracy: 1e-9)
        XCTAssertEqual(layout.nodes[0].shape, .circle)
        let label = try XCTUnwrap(layout.nodes[0].label.first)
        XCTAssertEqual(label.frame.minX, center.x + 8, accuracy: 1e-9, "Up and right, 8 points from the node")
        XCTAssertEqual(label.center.y + 13 * 0.35, center.y - 8, accuracy: 1e-9, "Its baseline 8 points up")
    }

    func testALinkStopsAtItsNodesAndPushesTheLabelToAFreeCorner() throws {
        let layout = try WardleyMapReading.uniformLayout("wardley-beta\ncomponent A [0.2, 0.2]\ncomponent B [0.6, 0.6]\nA +> B")
        let link = try XCTUnwrap(layout.links.first)
        let a = layout.nodes[0].center
        let b = layout.nodes[1].center
        XCTAssertEqual(hypot(link.line.start.x - a.x, link.line.start.y - a.y), 6, accuracy: 1e-9)
        XCTAssertEqual(link.arrows.count, 1)
        XCTAssertEqual(hypot(link.arrows[0].tip.x - b.x, link.arrows[0].tip.y - b.y), 6, accuracy: 1e-9)
        let aLabel = try XCTUnwrap(layout.nodes[0].label.first)
        XCTAssertGreaterThan(aLabel.center.y, a.y, "The link leaves A up and right: its label goes down and right")
    }

    func testAPipelineBoxesItsComponentsAndMovesItsParentOntoItsTop() throws {
        let layout = try WardleyMapReading.uniformLayout("wardley-beta\ncomponent DB [0.4, 0.6]\npipeline DB {\n  component Files [0.25]\n  component Cloud [0.85]\n}")
        let pipeline = try XCTUnwrap(layout.pipelines.first)
        let files = layout.nodes[1].center
        let cloud = layout.nodes[2].center
        XCTAssertEqual(pipeline.frame.minX, files.x - 15, accuracy: 1e-9)
        XCTAssertEqual(pipeline.frame.maxX, cloud.x + 15, accuracy: 1e-9)
        XCTAssertEqual(pipeline.frame.height, 24)
        XCTAssertNotNil(pipeline.line)
        XCTAssertEqual(layout.nodes[0].shape, .square)
        XCTAssertEqual(layout.nodes[0].center.x, (files.x + cloud.x) / 2, accuracy: 1e-9)
        XCTAssertEqual(layout.nodes[0].center.y, pipeline.frame.minY - 10.0 / 6, accuracy: 1e-9)
    }

    func testEvolutionsAnnotationsNotesAndForces() throws {
        let layout = try WardleyMapReading.uniformLayout("""
            wardley-beta
            component A [0.5, 0.2] (market) inertia
            evolve A 0.8
            annotation 2,[0.5, 0.5] "Second"
            annotation 1,[0.3, 0.3] "First"
            note "A note" [0.1, 0.1]
            accelerator "Faster" [0.5, 0.5]
            deaccelerator "Slower" [0.5, 0.5]
            """)
        let trend = try XCTUnwrap(layout.trends.first)
        XCTAssertNotNil(trend.arrow)
        XCTAssertEqual(trend.target.x - layout.plot.minX, 0.8 * 804, accuracy: 1e-9)
        XCTAssertEqual(layout.nodes[0].shape, .none, "A market is its ring and triangle")
        XCTAssertEqual(layout.nodes[0].inertia?.minX ?? 0, layout.nodes[0].center.x + 6 + 10 + 10, accuracy: 1e-9)
        XCTAssertEqual(layout.annotations.map { annotation in annotation.numbers[0].lines[0] }, ["2", "1"])
        XCTAssertEqual(layout.annotationList?.rows.map { row in row.lines[0] }, ["1. First", "2. Second"])
        XCTAssertGreaterThan(layout.annotationList?.frame.minY ?? 0, layout.plot.maxY, "Without a place, the list goes under the map")
        XCTAssertEqual(layout.notes.first?.first?.lines, ["A note"])
        XCTAssertEqual(layout.forces.map(\.isAccelerator), [true, false])
        XCTAssertEqual(layout.forces[0].outline.start.x, layout.forces[1].outline.start.x - 60, accuracy: 1e-9, "Their tails at opposite ends")
    }

    func testTheSceneHasPelesPartsInPelesOrder() throws {
        let scene = DiagramScene(layout: try WardleyMapReading.uniformLayout("wardley-beta\ntitle T\ncomponent A [0.2, 0.2]\ncomponent B [0.6, 0.6]\nA -> B"))
        let parts = scene.items.map { item -> DiagramScenePart in
            switch item {
            case .shape(let shape): shape.part
            case .text(let text): text.part
            }
        }
        XCTAssertEqual(Array(parts.prefix(3)), [.title, .wardleyStage, .wardleyAxis])
        XCTAssertTrue(parts.contains(.wardleyAxisLabel))
        XCTAssertLessThan(try XCTUnwrap(parts.firstIndex(of: .edge)), try XCTUnwrap(parts.firstIndex(of: .node)))
        XCTAssertTrue(scene.texts.contains { text in text.rotation != nil && text.part == .wardleyAxisLabel })
    }
}
