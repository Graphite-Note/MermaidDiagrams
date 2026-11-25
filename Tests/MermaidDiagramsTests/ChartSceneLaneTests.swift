/**
 * File: ChartSceneLaneTests.swift
 * -------------------------------
 * Layer: Tests
 * Description: The pie, radar, quadrant, XY chart, Sankey, treemap, packet, Venn and block scenes recorded into lanes are,
 *              item for item and element for element, the scenes 0.7.0 made from Core Graphics paths, on every corpus,
 *              their narrow layouts and thousands of texts mutated from the corpora's; and the lanes a chart's scene
 *              makes for a moment go back to the thread's pool.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class ChartSceneLaneTests: XCTestCase {
    private let typography = DiagramSceneSamples.typography
    /// The widths the output digest lays narrow scenes out at.
    private static let narrowWidths: [CGFloat] = [280, 390, 600]

    /// The corpora's sources of the types these scenes draw.
    private func chartSources() throws -> [String] {
        try OutputDigest.corpora().flatMap(\.sources).filter { source in
            (try? MermaidDiagramReader.read(source, limits: .standard)).map(Self.isChart) ?? false
        }
    }

    private static func isChart(_ diagram: MermaidDiagram) -> Bool {
        switch diagram {
        case .pieChart, .radar, .quadrantChart, .xyChart, .sankey, .treemap, .packet, .venn, .block: true
        default: false
        }
    }

    func testScenesOfEveryCorpusAreThoseMadeFromCoreGraphicsPaths() throws {
        var comparedCount = 0
        for source in try chartSources() where assertSameScenes(source) { comparedCount += 1 }
        XCTAssertGreaterThanOrEqual(comparedCount, 74, "the charts of the corpora compared")
    }

    /// Texts made from the corpora's charts by dropping, repeating, swapping and cutting lines, which reach the scenes'
    /// rarer branches: empty charts, lone slices, whole pies, series past the palette, unbalanced Sankey links.
    func testScenesOfMutatedChartsAreThoseMadeFromCoreGraphicsPaths() throws {
        var generator = ChartTextMutations(seed: 0x5CE_C4A7)
        var comparedCount = 0
        for source in try chartSources() {
            for _ in 0..<40 where assertSameScenes(generator.mutated(source)) { comparedCount += 1 }
        }
        XCTAssertGreaterThan(comparedCount, 1_800)
    }

    /// Lanes made for a moment while a chart's scene records go back to the pool, so that the pool holds about as many
    /// lanes for a chart of 400 slices, bands or boxes as for one of 4.
    func testLanesMadeForAMomentGoBackToThePool() throws {
        func pooledLaneCount(_ source: String) throws -> Int {
            let diagram = try MermaidDiagramReader.read(source, limits: .standard)
            var count = 0
            try DiagramSceneWorkspace.withRecording { workspace in
                var builder = DiagramSceneBuilder(workspace: workspace)
                switch diagram {
                case .pieChart(let chart): PieChartSceneRecording.add(PieChartLayoutEngine.layout(chart, typography: typography), to: &builder, workspace: workspace)
                case .sankey(let sankey):
                    SankeySceneRecording.add(try SankeyLayoutEngine.layout(sankey, typography: typography), to: &builder, workspace: workspace)
                case .treemap(let treemap):
                    TreemapSceneRecording.add(TreemapLayoutEngine.layout(treemap, typography: typography), to: &builder, workspace: workspace)
                default: XCTFail("not a pie, Sankey or treemap")
                }
                count = workspace.pooledLaneCount
            }
            return count
        }
        func pie(_ count: Int) -> String { "pie\n" + (0..<count).map { index in "  \"slice \(index)\" : \(index + 1)\n" }.joined() }
        func sankey(_ count: Int) -> String { "sankey-beta\n" + (0..<count).map { index in "a\(index % 7),b\(index % 5),\(index + 1)\n" }.joined() }
        func treemap(_ count: Int) -> String { "treemap\n\"all\"\n" + (0..<count).map { index in "  \"leaf \(index)\": \(index + 1)\n" }.joined() }
        XCTAssertLessThanOrEqual(try pooledLaneCount(pie(400)), try pooledLaneCount(pie(4)) + 2)
        XCTAssertLessThanOrEqual(try pooledLaneCount(sankey(400)), try pooledLaneCount(sankey(4)) + 2)
        XCTAssertLessThanOrEqual(try pooledLaneCount(treemap(400)), try pooledLaneCount(treemap(4)) + 2)
    }

    /// Compares the scenes of `source`'s regular layout and of its narrow layouts; false when it is not one of these
    /// charts or is not laid out.
    private func assertSameScenes(_ source: String, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        guard let diagram = try? MermaidDiagramReader.read(source, limits: .standard), Self.isChart(diagram) else { return false }
        var compared = false
        for width in [nil] + Self.narrowWidths.map(Optional.some) {
            guard let pair = laidOut(diagram, availableWidth: width) else { continue }
            let (scene, reference) = pair()
            XCTAssertEqual(transcript(of: scene), transcript(of: reference), "\(source.prefix(60)) at \(String(describing: width))", file: file, line: line)
            compared = true
        }
        return compared
    }

    /// The scene recorded into lanes and the one made from Core Graphics paths of `diagram`'s layout, at its own width or
    /// within `availableWidth`, as its preparation lays it out; nil when it is not laid out.
    private func laidOut(_ diagram: MermaidDiagram, availableWidth: CGFloat?) -> (() -> (DiagramScene, DiagramScene))? {
        func pair<Layout>(_ layout: Layout?, _ scene: @escaping (Layout) -> DiagramScene,
                          _ reference: @escaping (Layout) -> DiagramScene) -> (() -> (DiagramScene, DiagramScene))? {
            layout.map { layout in { (scene(layout), reference(layout)) } }
        }
        switch diagram {
        case .pieChart(let chart):
            return pair(PieChartLayoutEngine.layout(chart, typography: typography, availableWidth: availableWidth), DiagramScene.init(layout:),
                        ReferenceChartScene.scene(layout:))
        case .radar(let chart):
            return pair(RadarChartLayoutEngine.layout(chart, typography: typography, availableWidth: availableWidth), DiagramScene.init(layout:),
                        ReferenceChartScene.scene(layout:))
        case .quadrantChart(let chart):
            return pair(QuadrantChartLayoutEngine.layout(chart, typography: typography, availableWidth: availableWidth), DiagramScene.init(layout:),
                        ReferenceChartScene.scene(layout:))
        case .xyChart(let chart):
            return pair(try? XYChartLayoutEngine.layout(chart, typography: typography, availableWidth: availableWidth), DiagramScene.init(layout:),
                        ReferenceChartScene.scene(layout:))
        case .sankey(let sankey):
            return pair(try? SankeyLayoutEngine.layout(sankey, typography: typography, availableWidth: availableWidth), DiagramScene.init(layout:),
                        ReferenceChartScene.scene(layout:))
        case .treemap(let treemap):
            return pair(TreemapLayoutEngine.layout(treemap, typography: typography, availableWidth: availableWidth), DiagramScene.init(layout:),
                        ReferenceChartScene.scene(layout:))
        case .packet(let packet):
            return pair(PacketDiagramLayoutEngine.layout(packet, typography: typography, availableWidth: availableWidth), DiagramScene.init(layout:),
                        ReferenceChartScene.scene(layout:))
        case .venn(let venn):
            guard availableWidth == nil else { return nil }
            return pair(try? VennLayoutEngine.layout(venn, typography: typography, limits: .standard), DiagramScene.init(layout:),
                        ReferenceChartScene.scene(layout:))
        case .block(let block):
            let layout = availableWidth.map { width in try? BlockLayoutEngine.narrowLayout(block, typography: typography, width: width) }
                ?? (try? BlockLayoutEngine.layout(block, typography: typography))
            return pair(layout, DiagramScene.init(layout:), ReferenceChartScene.scene(layout:))
        default:
            return nil
        }
    }

    /// A scene's items as text: each shape's part, painting and every element's bits, each text's part, paint, place and
    /// look.
    private func transcript(of scene: DiagramScene) -> [String] {
        var lines = ["\(scene.size.width.bitPattern) \(scene.size.height.bitPattern) \(scene.itemCount) \(scene.seriesColors)"]
        scene.forEachItem { item in
            switch item {
            case .shape(let shape):
                var line = "shape \(shape.part.rawValue) \(shape.painting)"
                shape.forEachElement { verb, points in
                    line += " \(verb.rawValue)"
                    for index in 0..<verb.pointCount { line += ":\(points[index].x.bitPattern),\(points[index].y.bitPattern)" }
                }
                lines.append(line)
            case .text(let text):
                lines.append("text \(text.part.rawValue) \(text.paint) \(text.block.center) \(text.block.lineCount) \(text.isBold) \(text.isItalic) "
                    + "\(text.isMonospaced) \(String(describing: text.rotation)) \(String(describing: text.outline))")
            }
        }
        return lines
    }
}
