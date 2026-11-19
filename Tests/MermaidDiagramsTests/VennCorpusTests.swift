/**
 * File: VennCorpusTests.swift
 * ---------------------------
 * Layer: Tests
 * Description: Mermaid's Venn documentation examples, all read and laid out with each region's text apart from the
 *              others' and on the page, Pele's worst cases within limits and time, and the benchmark's generated sets.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class VennCorpusTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))

    func testEveryDocumentationExampleIsDrawnWithItsRegionsTextApart() throws {
        let examples = try VennCorpus.documentationExamples()
        XCTAssertEqual(examples.count, 8)
        for (index, example) in examples.enumerated() {
            let layout = try VennLayoutEngine.layout(try VennReading.venn(example), typography: typography)
            PlaneMapPictures.write(DiagramScene(layout: layout), named: "venn-documentation-\(index)")
            let frames = layout.regions.map { region in region.lines.map(\.text.frame).reduce(CGRect.null) { union, frame in union.union(frame) } }
            let page = CGRect(origin: .zero, size: layout.size)
            for (first, frame) in frames.enumerated() where !frame.isNull {
                XCTAssertTrue(page.contains(frame), "example \(index), region \(first) at \(frame) on \(layout.size)")
                for second in frames.indices where second > first && !frames[second].isNull {
                    XCTAssertFalse(frame.insetBy(dx: 1, dy: 1).intersects(frames[second]), "example \(index): regions \(first) and \(second) overlap")
                }
            }
        }
    }

    func testTheGeneratedDiagramsAreLaidOutOnAFinitePage() throws {
        for setCount in [1, 2, 3, 6, 40, 200] {
            let diagram = try VennReading.venn(VennCorpus.generated(setCount: setCount))
            let layout = try VennLayoutEngine.layout(diagram, typography: typography)
            XCTAssertEqual(layout.sets.count, setCount)
            XCTAssertTrue(layout.size.width.isFinite && layout.size.height.isFinite && layout.size.width > 0, "\(setCount): \(layout.size)")
            if setCount == 6 { PlaneMapPictures.write(DiagramScene(layout: layout), named: "venn-generated-6") }
        }
    }

    /// Pele's worst cases (tests/venn/stress.test.ts) that fit the standard text limit: each is read and laid out, or
    /// refused with a typed error, its numbers finite, in under 10 seconds in a debug build (Pele allows 3 seconds to its
    /// compiled JavaScript; the benchmark times the release build).
    func testPelesWorstCasesAreDrawnOrRefusedQuickly() {
        let header = "venn-beta\n"
        func repeated(_ count: Int, _ line: (Int) -> String) -> String { (0..<count).map(line).joined() }
        let nonsense = "set A:0\nset B:-1000000000\nset C:\(String(repeating: "9", count: 400))\nset D:.\(String(repeating: "0", count: 300))1\n"
            + "union A,B:\(String(repeating: "9", count: 400))\nunion C,D:-5\nunion A,B,C,D[\"x\"]:0\n"
        var everyPair = header + repeated(60) { index in "set s\(index)\n" }
        for first in 0..<60 { for second in (first + 1)..<60 { everyPair += "union s\(first),s\(second)\n" } }
        let cases: [String] = [
            header + "set A[\"x" + String(repeating: "x", count: 6_000), header + String(repeating: "set \"a ", count: 6_000),
            header + "style A fill:" + String(repeating: "rgb(1,2,", count: 5_000), header + String(repeating: "a%%\n", count: 10_000),
            header + "set A\n" + String(repeating: " ", count: 40_000) + "text x", header + String(repeating: "title\n", count: 8_000),
            header + "title " + String(repeating: "word ", count: 9_000) + "\nset A", header + repeated(2_000) { index in "set s\(index)\n" },
            header + repeated(300) { index in "set s\(index)\n" } + repeated(299) { index in "union s\(index),s\(index + 1)\n" }, everyPair,
            header + repeated(300) { index in "set s\(index)\n" } + "union " + repeated(299) { index in "s\(index)," } + "s299[\"all\"]\n",
            header + repeated(60) { index in "set s\(index)\n" } + repeated(40) { _ in "union " + repeated(59) { index in "s\(index)," } + "s59\n" },
            header + String(repeating: "set A[\"x\"]:5\n", count: 3_000), header + "set A\n" + String(repeating: "  text t\n", count: 4_000),
            header + "set A\nset B\nset C\nunion A,B,C\n" + String(repeating: "  text \"t t\"[\"l\"]\n", count: 2_000),
            header + "set A\n" + String(repeating: "style A fill:red, color:blue\n", count: 1_500),
            header + "set A\nstyle A " + repeated(4_000) { index in "p\(index):1," } + "fill:red\n",
            header + "set A\nset B\nset C\nunion A,B,C[\"x\"]\n" + String(repeating: "style A,B,C fill:gold\n", count: 2_000),
            header + "set A[\"" + String(repeating: "word ", count: 9_000) + "\"]", header + "set A[" + String(repeating: "a", count: 45_000) + "]",
            header + "set A[\"" + String(repeating: "#35;&amp;<br>", count: 3_500) + "\"]", header + nonsense,
            header + "set A:" + String(repeating: "9", count: 40_000) + "\nset B\nunion A,B:" + String(repeating: "9", count: 400),
            header + "set A\n" + String(repeating: "union A,A,A,A[\"x\"]\n", count: 2_000),
        ]
        for source in cases {
            let started = ContinuousClock.now
            if let diagram = try? VennReading.venn(source), let layout = try? VennLayoutEngine.layout(diagram, typography: typography) {
                XCTAssertTrue(layout.size.width.isFinite && layout.size.height.isFinite, String(source.prefix(60)))
                for set in layout.sets { XCTAssertTrue(set.center.x.isFinite && set.center.y.isFinite && set.radius.isFinite, String(source.prefix(60))) }
            }
            XCTAssertLessThan(ContinuousClock.now - started, .seconds(10), String(source.prefix(60)))
        }
    }
}
