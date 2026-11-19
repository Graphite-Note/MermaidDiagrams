/**
 * File: WardleyMapLayoutEngineTests.swift
 * ---------------------------------------
 * Layer: Tests
 * Description: A Wardley map's layout as Pele's draw() makes it: the plot and its stages, coordinates in percent, links
 *              stopped at their nodes, a label's corner away from links, pipelines, evolutions, annotations and forces.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
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

    /// The numbers worked out by hand from render.ts on the 804 by 504 plot: an evolution's arrow 8 points short of its
    /// circle and its line from the market's ring; the list under the stages' names and `Evolution` (568 down), 20 points
    /// wider and 14 taller than its lines, each row's baseline 7 points in, half a line and 0.35 of the size down; a note
    /// written from its point.
    func testEvolutionsAnnotationListAndNotesInPelesNumbers() throws {
        let layout = try WardleyMapReading.uniformLayout("""
            wardley-beta
            component A [0.5, 0.2] (market)
            evolve A 0.8
            annotation 2,[0.5, 0.5] "Second"
            annotation 1,[0.3, 0.3] "First"
            note "A note" [0.1, 0.1]
            """)
        let origin = layout.plot.origin
        let trend = try XCTUnwrap(layout.trends.first)
        XCTAssertEqual(try XCTUnwrap(trend.arrow).tip.x - origin.x, 0.8 * 804 - 8, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(trend.line).start.x - origin.x, 0.2 * 804 + 12, accuracy: 1e-9, "From the market's ring, two radii out")
        let list = try XCTUnwrap(layout.annotationList)
        XCTAssertEqual(list.frame.offsetBy(dx: -origin.x, dy: -origin.y), CGRect(x: 0, y: 568, width: 9 * 6.5 + 20, height: 2 * 20 + 14))
        XCTAssertEqual(list.rows[0].center.y + 13 * 0.35 - origin.y, 568 + 7 + 10 + 13 * 0.35, accuracy: 1e-9)
        XCTAssertEqual(list.rows[0].frame.minX - origin.x, 10, accuracy: 1e-9)
        let note = try XCTUnwrap(layout.notes.first?.first)
        XCTAssertEqual(note.frame.minX - origin.x, 0.1 * 804, accuracy: 1e-9)
        XCTAssertEqual(note.center.y + 13 * 0.35 - origin.y, 504 - 0.1 * 504, accuracy: 1e-9, "Its baseline at its point")
    }

    /// A link's label 5 points beside its middle on its upper side, past half its height for a level link; a line from
    /// an anchor stops on the ellipse around its name, 0.8 of the size tall.
    func testALinksLabelAndAnAnchorsReachInPelesNumbers() throws {
        let layout = try WardleyMapReading.uniformLayout("wardley-beta\nanchor X [0.5, 0.5]\ncomponent A [0.2, 0.2]\ncomponent B [0.2, 0.6]\nA -> B; go\nX -> Y\ncomponent Y [0.1, 0.5]")
        let origin = layout.plot.origin
        let label = try XCTUnwrap(layout.links[0].label)
        XCTAssertEqual(label.center.x - origin.x, (0.2 + 0.6) / 2 * 804, accuracy: 1e-9)
        XCTAssertEqual(label.center.y - origin.y, 504 - 0.2 * 504 - 5 - 9, accuracy: 1e-9)
        XCTAssertEqual(layout.links[1].line.start.y - origin.y, 504 - 0.5 * 504 + 13 * 0.8, accuracy: 1e-9)
    }

    /// Pele's fitWidth for a 280-point container: the map at 846 points is drawn tight, then its plot narrowed by what is
    /// still too wide (804 less 566: 238 points), its height 504 times three quarters, as it is narrower than that share;
    /// a stage's name wraps at 48 points, a component's label at 64 to 120.
    func testAMapTooWideForItsContainerIsDrawnTightAndNarrower() throws {
        let source = "wardley-beta\ncomponent A [0.5, 0.5]\ncomponent Long label words here [0.2, 0.2]"
        XCTAssertEqual(try WardleyMapReading.uniformLayout(source).size.width, 846)
        let fitted = try WardleyMapReading.uniformLayout(source, fittingWidth: 280)
        XCTAssertEqual(fitted.size.width, 280)
        XCTAssertEqual(fitted.plot.size, CGSize(width: 238, height: 378))
        XCTAssertEqual(fitted.stageLabels[1].lines, ["Custom", "Built"])
        XCTAssertEqual(fitted.nodes[1].label.map { line in line.lines[0] }, ["Long label words", "here"], "Wrapped at 119 points, half the plot")
        XCTAssertEqual(try WardleyMapReading.uniformLayout(source, fittingWidth: 900).size.width, 846, "It fits: drawn as it is")
        let floor = try WardleyMapReading.uniformLayout(source, fittingWidth: 50)
        XCTAssertEqual(floor.plot.width, 160, "Never narrower than 160 points")
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
