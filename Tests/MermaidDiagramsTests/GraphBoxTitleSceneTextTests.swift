/**
 * File: GraphBoxTitleSceneTextTests.swift
 * ---------------------------------------
 * Layer: Tests
 * Description: State and class diagrams measure their texts themselves and hand their scenes measured texts: the only
 *              blocks their scenes are given are the titles of their composite states' and namespaces' boxes, which the
 *              flowchart's group drawing paints.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class GraphBoxTitleSceneTextTests: XCTestCase {
    func testStateAndClassScenesAreGivenNoBlockButTheirBoxesTitles() throws {
        let typography = DiagramSceneSamples.typography
        var sources = try OutputDigest.corpora().flatMap(\.sources)
        var stateTexts = StateRandomTexts(seed: 43)
        var classTexts = ClassRandomTexts(seed: 47)
        sources += (0..<200).map { _ in stateTexts.text(statementCount: 20) } + (0..<200).map { _ in classTexts.text(statementCount: 20) }
        var counts = (state: 0, class: 0, titles: 0)
        for source in sources {
            guard let diagram = try? MermaidDiagramReader.read(source, limits: .standard) else { continue }
            for width in [nil] + OutputDigest.narrowColumnWidths.map(Optional.some) {
                let given: Int
                let titles: [DiagramTextBlock?]
                switch diagram {
                case .stateDiagram(let stateDiagram):
                    guard let layout = try? StateDiagramLayoutEngine.layout(stateDiagram, typography: typography, limits: .standard, availableWidth: width)
                    else { continue }
                    given = Self.blocksGiven { _ = DiagramScene(layout: layout) }
                    titles = layout.composites.map(\.title)
                    counts.state += 1
                case .classDiagram(let classDiagram):
                    guard let layout = try? ClassDiagramLayoutEngine.layout(classDiagram, typography: typography, limits: .standard, availableWidth: width)
                    else { continue }
                    given = Self.blocksGiven { _ = DiagramScene(layout: layout) }
                    titles = layout.namespaces.map(\.title)
                    counts.class += 1
                default: continue
                }
                let titleCount = titles.filter { title in (title?.lineCount ?? 0) > 0 }.count
                counts.titles += titleCount
                XCTAssertEqual(given, titleCount, "\(width.map { "\($0) points wide" } ?? "regular"):\n\(source.prefix(300))")
            }
        }
        XCTAssertGreaterThan(counts.state, 500)
        XCTAssertGreaterThan(counts.class, 500)
        XCTAssertGreaterThan(counts.titles, 100)
    }

    /// How many blocks the scene builder is given while `body` runs.
    private static func blocksGiven(_ body: () -> Void) -> Int {
        var count = 0
        DiagramSceneTextSubstitution.measuredText = { _ in
            count += 1
            return nil
        }
        defer { DiagramSceneTextSubstitution.measuredText = nil }
        body()
        return count
    }
}
