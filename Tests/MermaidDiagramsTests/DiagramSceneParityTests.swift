/**
 * File: DiagramSceneParityTests.swift
 * -----------------------------------
 * Layer: Tests
 * Description: Every sample of every diagram type paints the same pixels from its scene as from its type's own renderer,
 *              in a light palette at one pixel per point and a dark one at two.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class DiagramSceneParityTests: XCTestCase {
    /// A diagram laid out: its scene, and its drawing by its type's renderer.
    private struct LaidOutDiagram {
        let scene: DiagramScene
        let drawnByRenderer: (CGContext, DiagramPalette) -> Void
    }

    func testEverySampleIsPaintedFromItsSceneAsItsRendererPaintsIt() throws {
        var comparedTypes: Set<String> = []
        var comparedCount = 0
        var comparedNames: Set<String> = []
        for sample in try DiagramSceneSamples.all() {
            guard let diagram = try? DiagramSceneSamples.read(sample), let laidOut = try? Self.laidOut(diagram) else { continue }
            comparedTypes.insert(String(describing: diagram).prefix { character in character != "(" }.description)
            for (palette, scale) in [(DiagramScenePaletteSamples.light, CGFloat(1)), (DiagramScenePaletteSamples.dark, CGFloat(2))] {
                let size = laidOut.scene.size
                let byRenderer = try XCTUnwrap(DiagramScenePixels(size: size, scale: scale) { context in laidOut.drawnByRenderer(context, palette) })
                let byScene = try XCTUnwrap(DiagramScenePixels(size: size, scale: scale) { context in
                    DiagramSceneRenderer.draw(laidOut.scene, in: context, palette: palette)
                })
                XCTAssertEqual(byScene.differingPixelCount(from: byRenderer), 0, "\(sample.name) at \(scale)x")
                XCTAssertEqual(byScene.hasPaintedPixel, !laidOut.scene.items.isEmpty, sample.name)
            }
            comparedCount += 1
            comparedNames.insert(sample.name)
        }
        for (name, _) in DiagramSceneSamples.styled { XCTAssertTrue(comparedNames.contains(name), name) }
        XCTAssertEqual(comparedTypes.count, 14, "\(comparedTypes.sorted())")
        // The samples' texts the layouts refuse (a collapsed group, options not drawn) are left out: 320 are drawn.
        XCTAssertGreaterThanOrEqual(comparedCount, 320)
    }

    /// A theme change paints the same scene again: nothing in it holds a color.
    func testOneSceneIsPaintedInEitherPaletteAsTheRendererPaintsEach() throws {
        let layout = PieChartLayoutEngine.layout(try PieChartReading.pieChart(PieChartCorpus.pie(sliceCount: 12)), typography: DiagramSceneSamples.typography)
        let scene = DiagramScene(layout: layout)
        for palette in [DiagramScenePaletteSamples.dark, DiagramScenePaletteSamples.light] {
            let byScene = try XCTUnwrap(DiagramScenePixels(size: scene.size, scale: 1) { context in DiagramSceneRenderer.draw(scene, in: context, palette: palette) })
            let byRenderer = try XCTUnwrap(DiagramScenePixels(size: scene.size, scale: 1) { context in
                PieChartRenderer.draw(layout, in: context, palette: palette)
            })
            XCTAssertEqual(byScene.differingPixelCount(from: byRenderer), 0)
        }
    }

    private static func laidOut(_ diagram: MermaidDiagram) throws -> LaidOutDiagram {
        let typography = DiagramSceneSamples.typography
        switch diagram {
        case .flowchart(let flowchart):
            let layout = try FlowchartLayoutEngine.layout(flowchart, typography: typography, limits: .standard)
            return LaidOutDiagram(scene: DiagramScene(layout: layout)) { context, palette in FlowchartRenderer.draw(layout, in: context, palette: palette) }
        case .stateDiagram(let state):
            let layout = try StateDiagramLayoutEngine.layout(state, typography: typography, limits: .standard)
            return LaidOutDiagram(scene: DiagramScene(layout: layout)) { context, palette in StateDiagramRenderer.draw(layout, in: context, palette: palette) }
        case .classDiagram(let classes):
            let layout = try ClassDiagramLayoutEngine.layout(classes, typography: typography, limits: .standard)
            return LaidOutDiagram(scene: DiagramScene(layout: layout)) { context, palette in
                ClassDiagramRenderer.draw(layout, in: context, palette: ClassDiagramPalette(diagram: palette, muted: palette.muted,
                                                                                            noteSurface: palette.alternateSurface))
            }
        case .sequence(let sequence):
            let layout = try SequenceLayoutEngine.layout(sequence, typography: typography)
            return LaidOutDiagram(scene: DiagramScene(layout: layout)) { context, palette in SequenceRenderer.draw(layout, in: context, palette: palette) }
        case .entityRelationship(let entityRelationship):
            let layout = try EntityRelationshipLayoutEngine.layout(entityRelationship, typography: typography, limits: .standard)
            return LaidOutDiagram(scene: DiagramScene(layout: layout)) { context, palette in
                EntityRelationshipRenderer.draw(layout, in: context, palette: palette)
            }
        case .mindmap(let mindmap):
            let layout = MindmapLayoutEngine.layout(mindmap, typography: typography)
            return LaidOutDiagram(scene: DiagramScene(layout: layout)) { context, palette in MindmapRenderer.draw(layout, in: context, palette: palette) }
        case .timeline(let timeline):
            let layout = TimelineLayoutEngine.layout(timeline, typography: typography)
            return LaidOutDiagram(scene: DiagramScene(layout: layout)) { context, palette in TimelineRenderer.draw(layout, in: context, palette: palette) }
        default:
            return try laidOutChart(diagram, typography: typography)
        }
    }

    private static func laidOutChart(_ diagram: MermaidDiagram, typography: DiagramTypography) throws -> LaidOutDiagram {
        switch diagram {
        case .pieChart(let chart):
            let layout = PieChartLayoutEngine.layout(chart, typography: typography)
            return LaidOutDiagram(scene: DiagramScene(layout: layout)) { context, palette in PieChartRenderer.draw(layout, in: context, palette: palette) }
        case .ganttChart(let chart):
            let layout = try GanttLayoutEngine.layout(chart, typography: typography, now: GanttChartCorpus.now, timeZone: GanttChartCorpus.timeZone,
                                                      limits: .standard)
            return LaidOutDiagram(scene: DiagramScene(layout: layout)) { context, palette in GanttRenderer.draw(layout, in: context, palette: palette) }
        case .gitGraph(let gitGraph):
            let layout = try GitGraphLayoutEngine.layout(gitGraph, typography: typography)
            return LaidOutDiagram(scene: DiagramScene(layout: layout)) { context, palette in GitGraphRenderer.draw(layout, in: context, palette: palette) }
        case .userJourney(let journey):
            let layout = UserJourneyLayoutEngine.layout(journey, typography: typography)
            return LaidOutDiagram(scene: DiagramScene(layout: layout)) { context, palette in UserJourneyRenderer.draw(layout, in: context, palette: palette) }
        case .quadrantChart(let chart):
            let layout = QuadrantChartLayoutEngine.layout(chart, typography: typography)
            return LaidOutDiagram(scene: DiagramScene(layout: layout)) { context, palette in QuadrantChartRenderer.draw(layout, in: context, palette: palette) }
        case .xyChart(let chart):
            let layout = try XYChartLayoutEngine.layout(chart, typography: typography)
            return LaidOutDiagram(scene: DiagramScene(layout: layout)) { context, palette in XYChartRenderer.draw(layout, in: context, palette: palette) }
        case .sankey(let sankey):
            let layout = try SankeyLayoutEngine.layout(sankey, typography: typography)
            return LaidOutDiagram(scene: DiagramScene(layout: layout)) { context, palette in SankeyRenderer.draw(layout, in: context, palette: palette) }
        case .flowchart, .stateDiagram, .classDiagram, .sequence, .entityRelationship, .mindmap, .timeline:
            throw NotAChart()
        }
    }

    private struct NotAChart: Error {}
}
