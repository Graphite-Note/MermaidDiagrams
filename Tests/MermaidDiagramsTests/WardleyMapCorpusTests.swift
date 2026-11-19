/**
 * File: WardleyMapCorpusTests.swift
 * ---------------------------------
 * Layer: Tests
 * Description: Mermaid's Wardley map documentation examples, all read and laid out with everything on the page, Pele's
 *              worst cases within limits and time, and the benchmark's generated maps.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class WardleyMapCorpusTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))

    func testEveryDocumentationExampleIsDrawnOnThePage() throws {
        let examples = try WardleyMapCorpus.documentationExamples()
        XCTAssertEqual(examples.count, 19)
        for (index, example) in examples.enumerated() {
            let layout = WardleyMapLayoutEngine.layout(try WardleyMapReading.map(example), typography: typography)
            PlaneMapPictures.write(DiagramScene(layout: layout), named: "wardley-documentation-\(index)")
            let page = CGRect(origin: .zero, size: layout.size).insetBy(dx: -0.5, dy: -0.5)
            XCTAssertTrue(page.contains(layout.plot), "example \(index)")
            let texts = layout.stageLabels + layout.nodes.flatMap(\.label) + layout.notes.flatMap { note in note } + layout.links.compactMap(\.label)
            for text in texts { XCTAssertTrue(page.contains(text.frame), "example \(index): \(text.lines) at \(text.frame) on \(layout.size)") }
        }
    }

    func testTheGeneratedMapsAreLaidOut() throws {
        for componentCount in [0, 12, 200] {
            let layout = WardleyMapLayoutEngine.layout(try WardleyMapReading.map(WardleyMapCorpus.generated(componentCount: componentCount)), typography: typography)
            XCTAssertEqual(layout.nodes.count, componentCount + 1)
            XCTAssertTrue(layout.size.width.isFinite && layout.size.height.isFinite)
            if componentCount == 12 { PlaneMapPictures.write(DiagramScene(layout: layout), named: "wardley-generated-12") }
        }
    }

    /// Pele's worst cases (tests/wardley/stress.test.ts) that fit the standard text limit: each is read and laid out, or
    /// refused with a typed error, in under 10 seconds in a debug build.
    func testPelesWorstCasesAreDrawnOrRefusedQuickly() {
        let header = "wardley-beta\n"
        var bodies: [String] = [(0..<3_000).map { index in "component c\(index) [0.5, 0.5]\n" }.joined()]
        bodies.append("component a [0.5, 0.5]\ncomponent b [0.6, 0.6]\n" + String(repeating: "a -> b\n", count: 5_000))
        bodies.append("component a [0.5, 0.5]\npipeline a {\n" + (0..<2_000).map { index in "component p\(index) [0.5]\n" }.joined() + "}\n")
        bodies.append("component " + String(repeating: "word ", count: 9_000) + "[0.5, 0.5]")
        bodies.append("note \"" + String(repeating: "word ", count: 9_000) + "\" [0.5, 0.5]")
        bodies.append(String(repeating: "1", count: 45_000) + ".")
        bodies.append(String(repeating: "a-", count: 20_000) + ">")
        bodies.append("accDescr {" + String(repeating: " a\n", count: 15_000))
        bodies.append(String(repeating: "accDescr {\n", count: 4_000))
        bodies.append(String(repeating: "%%{\n", count: 12_000))
        bodies.append(String(repeating: "component a [0.5, 0.5]\n---\n", count: 1_500))
        bodies.append("size [" + String(repeating: "9", count: 400) + ", " + String(repeating: "9", count: 400) + "]")
        bodies.append("component a [0.5, 0.5]\n" + String(repeating: "evolve a 0.9\n", count: 3_000))
        bodies.append("annotations [0.1, 0.9]\n" + (0..<2_000).map { index in "annotation \(index),[0.5, 0.5] \"a\"\n" }.joined())
        bodies.append("component a [0.5, 0.5] label [" + String(repeating: "9", count: 400) + ", -" + String(repeating: "9", count: 400) + "]")
        for body in bodies {
            let source = header + body
            let started = ContinuousClock.now
            if let map = try? WardleyMapReading.map(source) {
                let layout = WardleyMapLayoutEngine.layout(map, typography: typography)
                XCTAssertTrue(layout.size.width.isFinite && layout.size.height.isFinite, String(source.prefix(60)))
            }
            XCTAssertLessThan(ContinuousClock.now - started, .seconds(10), String(source.prefix(60)))
        }
    }
}
