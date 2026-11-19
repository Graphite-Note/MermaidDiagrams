/**
 * File: DiagramSceneParityTests.swift
 * -----------------------------------
 * Layer: Tests
 * Description: Every sample of every diagram type paints the same pixels from its scene as its type's renderer painted it
 *              before the scene, in a light palette at one pixel per point and a dark one at two; a class diagram's palette
 *              names its scene's roles.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class DiagramSceneParityTests: XCTestCase {
    /// A diagram laid out: its scene, and its drawing by its type's renderer as it was before the scene
    /// (`ReferenceRenderers`): each type's own renderer now paints its scene.
    private struct LaidOutDiagram {
        let scene: DiagramScene
        let drawnByRenderer: (CGContext, DiagramPalette) -> Void
    }

    func testEverySampleIsPaintedFromItsSceneAsItsRendererPaintsIt() throws {
        var comparedTypes: Set<String> = []
        var comparedCount = 0
        var comparedNames: Set<String> = []
        var italicTextCount = 0
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
            italicTextCount += laidOut.scene.texts.filter(\.isItalic).count
        }
        for (name, _) in DiagramSceneSamples.styled { XCTAssertTrue(comparedNames.contains(name), name) }
        XCTAssertEqual(comparedTypes.count, 14, "\(comparedTypes.sorted())")
        XCTAssertGreaterThan(italicTextCount, 0, "Abstract class members, in italics, are compared (static ones underlined beside them)")
        // The samples' texts the layouts refuse (a collapsed group, options not drawn) are left out: 321 are drawn.
        XCTAssertGreaterThanOrEqual(comparedCount, 321)
    }

    /// A theme change paints the same scene again: nothing in it holds a color.
    func testOneSceneIsPaintedInEitherPaletteAsTheRendererPaintsEach() throws {
        let layout = PieChartLayoutEngine.layout(try PieChartReading.pieChart(PieChartCorpus.pie(sliceCount: 12)), typography: DiagramSceneSamples.typography)
        let scene = DiagramScene(layout: layout)
        for palette in [DiagramScenePaletteSamples.dark, DiagramScenePaletteSamples.light] {
            let byScene = try XCTUnwrap(DiagramScenePixels(size: scene.size, scale: 1) { context in
                DiagramSceneRenderer.draw(scene, in: context, palette: palette)
            })
            let byRenderer = try XCTUnwrap(DiagramScenePixels(size: scene.size, scale: 1) { context in
                ReferencePieChartRenderer.draw(layout, in: context, palette: palette)
            })
            XCTAssertEqual(byScene.differingPixelCount(from: byRenderer), 0)
        }
    }

    /// A class diagram's own muted color and note surface reach its scene's muted and alternate surface roles.
    func testAClassDiagramsRendererPaintsItsSceneInItsPalettesColors() throws {
        let source = "classDiagram\n  class Shape {\n    <<interface>>\n    +area() double*\n  }\n  note for Shape \"Every shape has an area\"\n  Shape <|-- Square"
        guard case .classDiagram(let diagram) = try MermaidDiagramReader.read(source, limits: .standard) else { return XCTFail("A class diagram") }
        let layout = try ClassDiagramLayoutEngine.layout(diagram, typography: DiagramSceneSamples.typography, limits: .standard)
        let palette = ClassDiagramPalette(diagram: DiagramScenePaletteSamples.dark, muted: CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1),
                                          noteSurface: CGColor(srgbRed: 0, green: 0.5, blue: 0, alpha: 1))
        let byRenderer = try XCTUnwrap(DiagramScenePixels(size: layout.size, scale: 1) { context in
            ClassDiagramRenderer.draw(layout, in: context, palette: palette)
        })
        let byReference = try XCTUnwrap(DiagramScenePixels(size: layout.size, scale: 1) { context in
            ReferenceClassDiagramRenderer.draw(layout, in: context, palette: palette)
        })
        XCTAssertEqual(byRenderer.differingPixelCount(from: byReference), 0)
    }

    private static func laidOut(_ diagram: MermaidDiagram) throws -> LaidOutDiagram {
        let typography = DiagramSceneSamples.typography
        switch diagram {
        case .flowchart(let flowchart):
            let layout = try FlowchartLayoutEngine.layout(flowchart, typography: typography, limits: .standard)
            return LaidOutDiagram(scene: DiagramScene(layout: layout)) { context, palette in
                ReferenceFlowchartRenderer.draw(layout, in: context, palette: palette)
            }
        case .stateDiagram(let state):
            let layout = try StateDiagramLayoutEngine.layout(state, typography: typography, limits: .standard)
            return LaidOutDiagram(scene: DiagramScene(layout: layout)) { context, palette in
                ReferenceStateDiagramRenderer.draw(layout, in: context, palette: palette)
            }
        case .classDiagram(let classes):
            let layout = try ClassDiagramLayoutEngine.layout(classes, typography: typography, limits: .standard)
            return LaidOutDiagram(scene: DiagramScene(layout: layout)) { context, palette in
                ReferenceClassDiagramRenderer.draw(layout, in: context, palette: ClassDiagramPalette(diagram: palette, muted: palette.muted,
                                                                                            noteSurface: palette.alternateSurface))
            }
        case .sequence(let sequence):
            let layout = try SequenceLayoutEngine.layout(sequence, typography: typography)
            return LaidOutDiagram(scene: DiagramScene(layout: layout)) { context, palette in
                ReferenceSequenceRenderer.draw(layout, in: context, palette: palette)
            }
        case .entityRelationship(let entityRelationship):
            let layout = try EntityRelationshipLayoutEngine.layout(entityRelationship, typography: typography, limits: .standard)
            return LaidOutDiagram(scene: DiagramScene(layout: layout)) { context, palette in
                ReferenceEntityRelationshipRenderer.draw(layout, in: context, palette: palette)
            }
        case .mindmap(let mindmap):
            let layout = MindmapLayoutEngine.layout(mindmap, typography: typography)
            return LaidOutDiagram(scene: DiagramScene(layout: layout)) { context, palette in
                ReferenceMindmapRenderer.draw(layout, in: context, palette: palette)
            }
        case .timeline(let timeline):
            let layout = TimelineLayoutEngine.layout(timeline, typography: typography)
            return LaidOutDiagram(scene: DiagramScene(layout: layout)) { context, palette in
                ReferenceTimelineRenderer.draw(layout, in: context, palette: palette)
            }
        default:
            return try laidOutChart(diagram, typography: typography)
        }
    }

    private static func laidOutChart(_ diagram: MermaidDiagram, typography: DiagramTypography) throws -> LaidOutDiagram {
        switch diagram {
        case .pieChart(let chart):
            let layout = PieChartLayoutEngine.layout(chart, typography: typography)
            return LaidOutDiagram(scene: DiagramScene(layout: layout)) { context, palette in
                ReferencePieChartRenderer.draw(layout, in: context, palette: palette)
            }
        case .ganttChart(let chart):
            let layout = try GanttLayoutEngine.layout(chart, typography: typography, now: GanttChartCorpus.now, timeZone: GanttChartCorpus.timeZone,
                                                      limits: .standard)
            return LaidOutDiagram(scene: DiagramScene(layout: layout)) { context, palette in
                ReferenceGanttRenderer.draw(layout, in: context, palette: palette)
            }
        case .gitGraph(let gitGraph):
            let layout = try GitGraphLayoutEngine.layout(gitGraph, typography: typography)
            return LaidOutDiagram(scene: DiagramScene(layout: layout)) { context, palette in
                ReferenceGitGraphRenderer.draw(layout, in: context, palette: palette)
            }
        case .userJourney(let journey):
            let layout = UserJourneyLayoutEngine.layout(journey, typography: typography)
            return LaidOutDiagram(scene: DiagramScene(layout: layout)) { context, palette in
                ReferenceUserJourneyRenderer.draw(layout, in: context, palette: palette)
            }
        case .quadrantChart(let chart):
            let layout = QuadrantChartLayoutEngine.layout(chart, typography: typography)
            return LaidOutDiagram(scene: DiagramScene(layout: layout)) { context, palette in
                ReferenceQuadrantChartRenderer.draw(layout, in: context, palette: palette)
            }
        case .xyChart(let chart):
            let layout = try XYChartLayoutEngine.layout(chart, typography: typography)
            return LaidOutDiagram(scene: DiagramScene(layout: layout)) { context, palette in
                ReferenceXYChartRenderer.draw(layout, in: context, palette: palette)
            }
        case .sankey(let sankey):
            let layout = try SankeyLayoutEngine.layout(sankey, typography: typography)
            return LaidOutDiagram(scene: DiagramScene(layout: layout)) { context, palette in
                ReferenceSankeyRenderer.draw(layout, in: context, palette: palette)
            }
        case .flowchart, .stateDiagram, .classDiagram, .sequence, .entityRelationship, .mindmap, .timeline:
            throw NotAChart()
        case .venn, .cynefin, .wardleyMap:
            throw NoReferenceRenderer()
        }
    }

    private struct NotAChart: Error {}
    /// A type drawn from its scene since it was added, with no renderer from before the scene to compare with.
    private struct NoReferenceRenderer: Error {}
}
