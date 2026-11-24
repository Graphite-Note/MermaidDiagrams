/**
 * File: FlowchartLayoutHostileInputTests.swift
 * --------------------------------------------
 * Layer: Tests
 * Description: Flowcharts built to make the compound layout's work grow, within the standard limits: deep groups that
 *              many links leave, wide levels of groups linked across, loops and collapsed groups in groups. Each is
 *              prepared with its narrow scene and its SVG, or refused with a typed error, quickly and without a crash.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class FlowchartLayoutHostileInputTests: XCTestCase {
    private static var typography: DiagramTypography { DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16)) }

    private static func repeated(_ count: Int, _ part: (Int) -> String) -> String {
        (0..<count).map(part).joined()
    }

    /// `depth` groups one inside the other, a node at the bottom, and `linkCount` links from it to nodes outside them
    /// all, each crossing every group's border.
    private static func deepGroupsLeft(depth: Int, linkCount: Int) -> String {
        "flowchart TD\n" + repeated(depth) { level in "subgraph g\(level)\n" } + "inner\n" + String(repeating: "end\n", count: depth)
            + repeated(linkCount) { link in "inner --> o\(link)\n" }
    }

    /// Prepares `source` with its narrow scene and SVG, or takes its typed error, and returns how long it took.
    private static func preparationSeconds(of source: String) -> Double {
        XCTAssertLessThanOrEqual(source.utf8.count, MermaidDiagramLimits.standard.maximumSourceBytes)
        let start = Date()
        if let prepared = try? MermaidDiagramPreparation.prepare(source: source, typography: typography) {
            _ = prepared.narrowScene
            _ = prepared.svgDocument
        }
        return Date().timeIntervalSince(start)
    }

    /// Links that leave many groups at once: each link's end has a port in every group it crosses, which the layout
    /// finds by walking a chain of the end's ports level by level. The work grows with the links times the groups, not
    /// faster: twice the depth takes well under four times as long.
    func testLinksLeavingDeepGroupsAreQuickAndGrowNoFasterThanTheirPorts() {
        let shallow = Self.preparationSeconds(of: Self.deepGroupsLeft(depth: 60, linkCount: 400))
        let deep = Self.preparationSeconds(of: Self.deepGroupsLeft(depth: 120, linkCount: 400))
        XCTAssertLessThan(deep, 20)
        XCTAssertLessThan(deep, 3.2 * max(shallow, 0.05), "\(shallow) s for 60 groups, \(deep) s for 120")
    }

    /// Hostile flowcharts with groups at the standard limits, each within a few seconds.
    func testHostileFlowchartsWithGroupsAreQuick() {
        let cases: [(String, String)] = [
            ("300 nested groups, 1,500 links out of them", Self.deepGroupsLeft(depth: 300, linkCount: 1_500)),
            ("400 groups side by side, each linked to the next", "flowchart LR\n"
                + Self.repeated(400) { group in "subgraph g\(group)\na\(group) --> b\(group)\nend\n" }
                + Self.repeated(399) { group in "b\(group) --> a\(group + 1)\ng\(group) --> g\((group * 7 + 3) % 400)\n" }),
            ("2,000 loops on a node inside groups", "flowchart TD\nsubgraph g\nsubgraph h\na\nend\nend\n" + String(repeating: "a --> a\n", count: 2_000)),
            ("2,000 links between groups", "flowchart TD\nsubgraph g\na\nend\nsubgraph h\nb\nend\n" + String(repeating: "g --> h\n", count: 2_000)),
            ("100 nested collapsed groups", "flowchart TD\n" + Self.repeated(100) { level in "subgraph g\(level)\nn\(level)\n" }
                + String(repeating: "end\n", count: 100) + Self.repeated(100) { level in "g\(level)@{ view: collapsed }\ng\(level) --> n\((level + 1) % 100)\n" }),
            ("groups nested both ways with links between their insides", "flowchart TD\n"
                + Self.repeated(40) { group in "subgraph g\(group)\ndirection LR\nsubgraph h\(group)\ndirection TB\na\(group) --> b\(group)\nend\nend\n" }
                + Self.repeated(1_000) { link in "a\(link % 40) --> b\((link * 13 + 5) % 40)\n" }),
        ]
        for (name, source) in cases {
            XCTAssertLessThan(Self.preparationSeconds(of: source), 10, name)
        }
    }
}
