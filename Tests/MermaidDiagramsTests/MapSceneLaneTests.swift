/**
 * File: MapSceneLaneTests.swift
 * -----------------------------
 * Layer: Tests
 * Description: The Git graph, mindmap, architecture, tree view, Wardley map, Cynefin and Ishikawa scenes recorded into
 *              lanes are, item for item and element for element, the scenes 0.7.0 made from Core Graphics paths, on
 *              every corpus input of those types, each input with one of its lines left out, and their narrow layouts.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class MapSceneLaneTests: XCTestCase {
    private let typography = DiagramSceneSamples.typography
    /// The width the narrow layouts are made for, Graphite's narrowest column.
    private let narrowWidth: CGFloat = 280

    func testScenesOfEveryCorpusInputAreThoseMadeFromCoreGraphicsPaths() throws {
        var comparedCount = 0
        for source in try mapSources() where assertSameScenes(source) { comparedCount += 1 }
        XCTAssertGreaterThan(comparedCount, 80, "Git graphs, mindmaps, architecture diagrams, tree views, Wardley maps, Cynefin and Ishikawa diagrams")
    }

    /// Each input with one of its lines left out: a statement missing, a block cut short, an outline's depth changed.
    func testScenesOfInputsWithALineLeftOutAreThoseMadeFromCoreGraphicsPaths() throws {
        var comparedCount = 0
        for source in try mapSources() {
            let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
            for leftOut in 1..<max(lines.count, 1) {
                var kept = lines
                kept.remove(at: leftOut)
                if assertSameScenes(kept.joined(separator: "\n")) { comparedCount += 1 }
            }
        }
        XCTAssertGreaterThan(comparedCount, 800)
    }

    /// The corpus inputs of the types whose scenes record into lanes.
    private func mapSources() throws -> [String] {
        try OutputDigest.corpora().flatMap(\.sources).filter { source in
            guard let diagram = try? MermaidDiagramReader.read(source, limits: .standard) else { return false }
            switch diagram {
            case .gitGraph, .mindmap, .architecture, .treeView, .wardleyMap, .cynefin, .ishikawa: return true
            default: return false
            }
        }
    }

    /// Compares the scenes of `source`'s layout, and of its narrow layout where the type has one, with the references;
    /// false when `source` is not one of the types or is not laid out.
    private func assertSameScenes(_ source: String, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        guard let diagram = try? MermaidDiagramReader.read(source, limits: .standard) else { return false }
        let pairs: [(DiagramScene, DiagramScene)]
        switch diagram {
        case .gitGraph(let gitGraph):
            guard let layout = try? GitGraphLayoutEngine.layout(gitGraph, typography: typography) else { return false }
            pairs = [(DiagramScene(layout: layout), ReferenceGitGraphScene.scene(layout: layout))]
        case .mindmap(let mindmap):
            pairs = [MindmapLayoutEngine.layout(mindmap, typography: typography), MindmapLayoutEngine.layout(mindmap, typography: typography, availableWidth: narrowWidth)]
                .map { layout in (DiagramScene(layout: layout), ReferenceMindmapScene.scene(layout: layout)) }
        case .architecture(let architecture):
            pairs = [ArchitectureLayoutEngine.layout(architecture, typography: typography),
                     ArchitectureLayoutEngine.layout(architecture, typography: typography, availableWidth: narrowWidth, isTight: true)]
                .map { layout in (DiagramScene(layout: layout), ReferenceArchitectureScene.scene(layout: layout)) }
        case .treeView(let tree):
            pairs = [TreeViewLayoutEngine.layout(tree, typography: typography), TreeViewLayoutEngine.layout(tree, typography: typography, maximumWidth: narrowWidth)]
                .map { layout in (DiagramScene(layout: layout), ReferenceTreeViewScene.scene(layout: layout)) }
        case .wardleyMap(let map):
            pairs = [WardleyMapLayoutEngine.layout(map, typography: typography), WardleyMapLayoutEngine.layout(map, typography: typography, fittingWidth: narrowWidth)]
                .map { layout in (DiagramScene(layout: layout), ReferenceWardleyMapScene.scene(layout: layout)) }
        case .cynefin(let cynefin):
            let layout = CynefinLayoutEngine.layout(cynefin, typography: typography)
            pairs = [(DiagramScene(layout: layout), ReferenceCynefinScene.scene(layout: layout))]
        case .ishikawa(let ishikawa):
            pairs = [IshikawaLayoutEngine.layout(ishikawa, typography: typography), IshikawaLayoutEngine.layout(ishikawa, typography: typography, maximumWidth: narrowWidth)]
                .map { layout in (DiagramScene(layout: layout), ReferenceIshikawaScene.scene(layout: layout)) }
        default:
            return false
        }
        for (recorded, reference) in pairs {
            XCTAssertEqual(DiagramSceneTranscript.lines(of: recorded), DiagramSceneTranscript.lines(of: reference), file: file, line: line)
        }
        return true
    }
}

/// A scene's items as text: each shape's part, painting and every element's bits, each text's part, paint, place,
/// lines and turn, so that two scenes are the same scene exactly when their transcripts are equal.
enum DiagramSceneTranscript {
    static func lines(of scene: DiagramScene) -> [String] {
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
                lines.append("text \(text.part.rawValue) \(text.paint) \(text.block) \(text.isBold) \(text.isItalic) \(text.isMonospaced) "
                    + "\(String(describing: text.rotation)) \(String(describing: text.outline))")
            }
        }
        return lines
    }
}
