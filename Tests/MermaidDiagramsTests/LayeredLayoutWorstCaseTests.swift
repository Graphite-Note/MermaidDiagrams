/**
 * File: LayeredLayoutWorstCaseTests.swift
 * ---------------------------------------
 * Layer: Tests
 * Description: Pele's worst cases for its layered and compound layouts (tests/stress.test.ts), each laid out or refused
 *              quickly by the port.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class LayeredLayoutWorstCaseTests: XCTestCase {
    private static var typography: DiagramTypography { DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16)) }
    /// Pele's `big` options lift its limits for these cases; here the source and counts are lifted, and the layout's
    /// points and the drawing's side keep the standard limits.
    private static let limits = MermaidDiagramLimits(maximumSourceBytes: 2_000_000, maximumNodeCount: 20_000, maximumEdgeCount: 20_000,
                                                     maximumLayoutPointCount: MermaidDiagramLimits.standard.maximumLayoutPointCount)

    private static func repeated(_ count: Int, _ part: (Int) -> String) -> String {
        (0..<count).map(part).joined()
    }

    /// Pele's flowchart cases that reach the layout.
    private static var cases: [(String, String)] {
        var complete = "graph TD\n"
        for first in 0..<60 { for second in (first + 1)..<60 { complete += "n\(first)-->n\(second)\n" } }
        return [
            ("edges that each cross 1,000 nested subgraph borders", "flowchart TD\n" + repeated(1000) { index in "subgraph g\(index)\n" } + "inner\n"
                + String(repeating: "end\n", count: 1000) + repeated(2000) { index in "out\(index % 50) --> inner\n" }),
            ("3,000 nested subgraphs, rendered", "graph TD\n" + repeated(3000) { index in "subgraph s\(index)\n" } + "A-->B\n" + String(repeating: "end\n", count: 3000)),
            ("5,000 sibling subgraphs", "graph TD\n" + repeated(5000) { index in "subgraph s\(index)\nn\(index)\nend\n" }),
            ("chain of 5,000", "graph TD\n" + repeated(5000) { index in "n\(index)-->n\(index + 1)\n" }),
            ("star of 5,000", "graph TD\n" + repeated(5000) { index in "c-->n\(index)\n" }),
            ("3,000 long edges over a chain of 3,000", "graph TD\n" + repeated(3000) { index in "n\(index)-->n\(index + 1)\nn0-->n\(index + 2)\n" }),
            ("complete graph of 60", complete),
            ("2,000 parallel edges and 2,000 self loops", "graph TD\n" + String(repeating: "A-->B\n", count: 2000) + String(repeating: "A-->A\n", count: 2000)),
            ("1,000 edges of length ten", "graph TD\n" + repeated(1000) { index in "n\(index) ------------> n\(index + 1)\n" }),
        ]
    }

    func testPelesWorstCasesAreLaidOutOrRefusedQuickly() {
        for (name, source) in Self.cases {
            let start = Date()
            if let diagram = try? FlowchartReading.flowchart(source, limits: Self.limits),
               let layout = try? FlowchartLayoutEngine.layout(diagram, typography: Self.typography, limits: Self.limits) {
                XCTAssertTrue(layout.size.width.isFinite && layout.size.height.isFinite, name)
            }
            XCTAssertLessThan(Date().timeIntervalSince(start), 3, name)
        }
    }
}
