/**
 * File: CynefinCorpusTests.swift
 * ------------------------------
 * Layer: Tests
 * Description: Mermaid's Cynefin documentation examples, all read and laid out with their blocks apart and on the page,
 *              Pele's worst cases within limits and time, and the benchmark's generated frameworks.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class CynefinCorpusTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))

    func testEveryDocumentationExampleIsDrawnWithItsBlocksApartAndOnThePage() throws {
        let examples = try CynefinCorpus.documentationExamples()
        XCTAssertEqual(examples.count, 3)
        for (index, example) in examples.enumerated() {
            let layout = CynefinLayoutEngine.layout(try CynefinReading.cynefin(example), typography: typography)
            PlaneMapPictures.write(DiagramScene(layout: layout), named: "cynefin-documentation-\(index)")
            let page = CGRect(origin: .zero, size: layout.size)
            for (first, block) in layout.blocks.enumerated() {
                XCTAssertTrue(page.contains(block.frame), "example \(index): \(block.domain)")
                for second in layout.blocks.indices where second > first {
                    XCTAssertFalse(block.frame.intersects(layout.blocks[second].frame), "example \(index): \(block.domain) and \(layout.blocks[second].domain)")
                }
            }
            for transition in layout.transitions {
                if let label = transition.label { XCTAssertTrue(page.contains(label.frame), "example \(index): \(transition.from) to \(transition.to)") }
            }
        }
        let strategy = CynefinLayoutEngine.layout(try CynefinReading.cynefin(examples[1]), typography: typography)
        XCTAssertEqual(strategy.transitions.count, 4)
    }

    func testTheGeneratedFrameworksAreLaidOut() throws {
        for itemCount in [0, 12, 200] {
            let layout = CynefinLayoutEngine.layout(try CynefinReading.cynefin(CynefinCorpus.generated(itemCount: itemCount)), typography: typography)
            let diagram = try CynefinReading.cynefin(CynefinCorpus.generated(itemCount: itemCount))
            let shown = CynefinDomain.allCases.map { domain in min(diagram.items[domain]?.count ?? 0, domain == .confusion ? 3 : .max) }.reduce(0, +)
            XCTAssertEqual(layout.blocks.flatMap(\.badges).filter { badge in !badge.isOverflow }.count, shown, "\(itemCount)")
            XCTAssertEqual(diagram.items.values.map(\.count).reduce(0, +), itemCount)
            XCTAssertTrue(layout.size.width.isFinite && layout.size.height.isFinite)
            if itemCount == 12 { PlaneMapPictures.write(DiagramScene(layout: layout), named: "cynefin-generated-12") }
        }
    }

    /// Pele's worst cases (tests/cynefin/stress.test.ts) that fit the standard text limit: each is read and laid out, or
    /// refused with a typed error, in under 10 seconds in a debug build.
    func testPelesWorstCasesAreDrawnOrRefusedQuickly() {
        let header = "cynefin-beta\n"
        let domains = ["complex", "clear", "chaotic", "confusion", "complicated"]
        let items = (0..<4_000).map { item in "\"i\(item)\"\n" }.joined()
        let labelled = (0..<2_000).map { index in "complex --> clear : \"t\(index)\"\n" }.joined()
        let pairs = (0..<2_000).map { (index: Int) -> String in
            let from: String = domains[index % 5]
            let to: String = domains[(index + index % 3) % 5]
            return from + " --> " + to + "\n"
        }.joined()
        var bodies: [String] = ["complex\n" + items, "confusion\n" + String(repeating: "\"x\"\n", count: 4_000), String(repeating: "clear\n\"a\"\n", count: 4_000)]
        bodies += [labelled, pairs, "complex\n\"" + String(repeating: "word ", count: 9_000) + "\"", "complex\n\"" + String(repeating: "a", count: 45_000) + "\""]
        bodies += ["complex --> clear : \"" + String(repeating: "word ", count: 9_000) + "\"", "title " + String(repeating: "x", count: 45_000)]
        bodies += ["complex\n\"" + String(repeating: "a", count: 45_000), "complex\n\"" + String(repeating: "\\", count: 45_000)]
        bodies += ["complex\n\"" + String(repeating: "\\\"", count: 20_000) + "\"", "complex\n" + String(repeating: "\"a\n", count: 15_000)]
        bodies += ["accDescr {" + String(repeating: " a\n", count: 15_000), String(repeating: "%%{\n", count: 12_000), String(repeating: "complex\n---\n", count: 4_000)]
        bodies += [String(repeating: "\n", count: 45_000), "complex\n" + String(repeating: " ", count: 45_000) + "\"a\"", String(repeating: "%% c\n", count: 9_000)]
        bodies += ["complex\n\"" + String(repeating: "#35;&amp;<br>", count: 3_500) + "\"", String(repeating: "complex", count: 7_000)]
        let cases = bodies.map { body in header + body }
        for source in cases {
            let started = ContinuousClock.now
            if let diagram = try? CynefinReading.cynefin(source) {
                let layout = CynefinLayoutEngine.layout(diagram, typography: typography)
                XCTAssertTrue(layout.size.width.isFinite && layout.size.height.isFinite, String(source.prefix(60)))
            }
            XCTAssertLessThan(ContinuousClock.now - started, .seconds(10), String(source.prefix(60)))
        }
    }
}
