/**
 * File: LayeredDiagramSafetyTests.swift
 * -------------------------------------
 * Layer: Tests
 * Description: Pele's worst cases for requirement diagrams and swimlane diagrams, within the standard limits: each read
 *              and laid out, or refused with a typed error, quickly and without a crash.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class LayeredDiagramSafetyTests: XCTestCase {
    private static var typography: DiagramTypography { DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16)) }
    private static let size = 50_000

    private static func repeated(_ count: Int, _ part: (Int) -> String) -> String {
        (0..<count).map(part).joined()
    }

    /// Reads, lays out and makes the scene of `source`, regular and tight, or takes its typed error; true when it was laid out.
    @discardableResult
    private static func outcome(of source: String) -> Bool {
        let diagram: MermaidDiagram
        do { diagram = try MermaidDiagramReader.read(source, limits: .standard) } catch { return false }
        switch diagram {
        case .requirement(let requirement):
            guard let layout = try? RequirementLayoutEngine.layout(requirement, typography: typography, limits: .standard) else { return false }
            XCTAssertTrue(layout.size.width.isFinite && layout.size.height.isFinite)
            _ = DiagramScene(layout: layout)
        case .swimlane(let swimlane):
            let layout = SwimlaneLayoutEngine.layout(swimlane, typography: typography)
            XCTAssertTrue(layout.size.width.isFinite && layout.size.height.isFinite)
            _ = DiagramScene(layout: layout)
            _ = SwimlaneLayoutEngine.layout(swimlane.swimlaneTurnedToRunDown ?? swimlane, typography: typography, spacing: .compact, columnWidth: 280)
        default: XCTFail("not a requirement or swimlane diagram")
        }
        return true
    }

    /// Each case within `seconds`, and at least `laidOutCount` of them laid out rather than refused.
    private func assertQuick(_ cases: [(String, String)], seconds: Double, laidOutCount: Int) {
        var count = 0
        for (name, source) in cases {
            let start = Date()
            if Self.outcome(of: source) { count += 1 }
            XCTAssertLessThan(Date().timeIntervalSince(start), seconds, name)
        }
        XCTAssertGreaterThanOrEqual(count, laidOutCount)
    }

    /// Pele's requirement worst cases (`tests/requirement/stress.test.ts`), within 50,000 bytes.
    func testPelesRequirementWorstCasesAreQuick() {
        let head = "requirementDiagram\n"
        let size = Self.size
        assertQuick([
            ("one line that mentions direction without ending it", head + String(repeating: "a - contains -> b ", count: size / 18 - 2) + "direction XX"),
            ("one line of many tokens ending in a direction", head + String(repeating: ": ", count: size / 2 - 20) + "direction LR"),
            ("direction followed by blank lines", head + String(repeating: "direction" + String(repeating: "\n", count: 40), count: size / 50 - 1) + "TB"),
            ("many direction words on one line", head + String(repeating: "direction ", count: size / 10 - 3) + "TB"),
            ("many direction statements on one line", head + String(repeating: "direction TB ", count: size / 13 - 2)),
            ("accTitle with no colon before a wall of spaces", head + String(repeating: "accTitle" + String(repeating: " ", count: 100) + "\n", count: size / 110 - 1)),
            ("accDescr followed by whitespace only", head + "accDescr" + String(repeating: " \n", count: size / 2 - 20)),
            ("unclosed accDescr block", head + "accDescr {" + String(repeating: " a\n", count: size / 3 - 10)),
            ("title word on every line", head + String(repeating: "title\n", count: size / 6 - 4)),
            ("title followed by hashes", head + String(repeating: "title #", count: size / 7 - 3)),
            ("one unquoted string of spaces", head + "a" + String(repeating: " ", count: size - 30) + "b"),
            ("one unclosed quoted string", head + "element \"" + String(repeating: "x", count: size - 40)),
            ("quotes and nothing else", head + String(repeating: "\"", count: size - 30)),
            ("runs of whitespace between tokens", head + String(repeating: "a" + String(repeating: " \n\t", count: 30) + ":", count: size / 100 - 1)),
            ("spaces in a style statement", head + "style a" + String(repeating: " ", count: size - 40) + "fill:red\n"),
            ("a style statement of 9,000 parts", head + "style a " + String(repeating: "f:#-;", count: size / 5 - 10) + "\n"),
            ("a class list of 24,000 names", head + "requirement a {\n}\nclass a " + String(repeating: "c,", count: size / 2 - 40) + "c\n"),
            ("a class defined and applied 1,600 times", head + "requirement a {\n}\n" + String(repeating: "classDef c fill:red\nclass a c\n", count: 1_600)),
            ("a class of 6,000 declarations applied 1,000 times", head + "requirement a {\n}\nclassDef c " + String(repeating: "a:b,", count: 6_000) + "a:b\n"
                + String(repeating: "class a c\n", count: 1_000)),
            ("2,000 nodes and 500 class definitions", head + Self.repeated(2_000) { index in "element e\(index):::c {\n}\n" }.prefix(size - 10_000)
                + String(repeating: "classDef c a:b\n", count: 500)),
            ("a body of 6,000 repeated fields", head + "requirement a {\n" + String(repeating: "id: 1\n", count: 6_000) + "}\n"),
            ("a body that never closes", head + "requirement a {\n" + String(repeating: "text: x\n", count: 6_000)),
            ("blank lines", head + String(repeating: "\n \n", count: size / 3 - 30) + "requirement a {\n}\n"),
            ("comment characters on every line", head + String(repeating: "# c\n% d\n", count: size / 8 - 3)),
            ("1,000 requirements with full bodies", head + Self.repeated(1_000) { index in "requirement r\(index) {\nid: \(index)\nrisk: low\n}\n" }),
            ("chain of 1,000", head + Self.repeated(1_000) { index in "element e\(index) {\n}\n" } + Self.repeated(999) { index in "e\(index) - traces -> e\(index + 1)\n" }),
            ("star of 1,000", head + Self.repeated(1_000) { index in "element e\(index) {\n}\n" } + Self.repeated(999) { index in "e0 - contains -> e\(index + 1)\n" }),
            ("2,000 parallel relationships and 300 self relationships", head + "element a {\n}\nelement b {\n}\n" + String(repeating: "a - copies -> b\n", count: 2_000)
                + String(repeating: "a - contains -> a\n", count: 300)),
            ("2,500 relationships to names that do not exist", head + "element a {\n}\n" + Self.repeated(2_500) { index in "a - refines -> x\(index)\n" }),
            ("complete graph of 40", head + Self.repeated(40) { index in "element e\(index) {\n}\n" }
                + Self.repeated(40) { first in Self.repeated(39 - first) { offset in "e\(first) - derives -> e\(first + offset + 1)\n" } }),
            ("one 45,000 character text", head + "requirement a {\ntext: \"" + String(repeating: "word ", count: 9_000) + "\"\n}\n"),
            ("text of emphasis markers", head + "requirement a {\ntext: \"" + String(repeating: "*a _b **c ", count: 4_500) + "\"\n}\n"),
            ("a name of 45,000 characters without spaces", head + "requirement " + String(repeating: "x", count: 45_000) + " {\n}\n"),
            ("text of entities and line breaks", head + "requirement a {\ntext: \"" + String(repeating: "#35;&amp;<br>", count: 3_500) + "\"\n}\n"),
            ("blank lines and carriage returns before a comment", head + String(repeating: "\n \r", count: size / 3 - 30) + "%% c\nrequirement a {\n}\n"),
            ("comment lines", head + String(repeating: "%% c\n", count: size / 5 - 10) + "requirement a {\n}\n"),
            ("style lines with a color and no semicolon", head + String(repeating: "style a fill:#b\n", count: size / 16 - 5)),
            ("style lines with a color and a semicolon far back", head + "a;\n" + String(repeating: "style a:#b\n", count: size / 11 - 5)),
        ], seconds: 3, laidOutCount: 18)
    }

    /// Pele's swimlane worst cases (`tests/swimlane/stress.test.ts`), within the standard limits.
    func testPelesSwimlaneWorstCasesAreQuick() {
        func lanes(_ count: Int, _ body: (Int) -> String) -> String {
            Self.repeated(count) { lane in "  subgraph L\(lane)\n\(body(lane))\n  end\n" }
        }
        var seed = 7
        func next(_ bound: Int) -> Int {
            seed = (seed &* 1_103_515_245 &+ 12_345) & 0x7fff_ffff
            return seed % bound
        }
        let randomEdges = Self.repeated(2_000) { _ in "  n\(next(10))_\(next(80)) --> n\(next(10))_\(next(80))\n" }
        assertQuick([
            ("800 nodes in 10 lanes with 2,000 edges", "swimlane-beta TD\n" + lanes(10) { lane in Self.repeated(80) { index in "    n\(lane)_\(index)\n" } } + randomEdges),
            ("one long chain that changes lane at every step", "swimlane-beta LR\n" + lanes(8) { lane in Self.repeated(150) { index in "    n\(index * 8 + lane)\n" } }
                + Self.repeated(1_199) { index in "  n\(index) --> n\(index + 1)\n" }),
            ("500 lanes", "swimlane-beta TD\n" + lanes(500) { lane in "    a\(lane) --> b\(lane)" }),
            ("edges that span 1,500 ranks", "swimlane-beta TD\n  subgraph A\n" + Self.repeated(1_500) { index in "    a\(index) --> a\(index + 1)\n" }
                + "  end\n  subgraph B\n    b\n  end\n" + Self.repeated(40) { index in "  a0 --> a\(1_500 - index)\n  b --> a\(1_400 - index)\n" }),
            ("2,500 labelled edges between two nodes", "swimlane-beta TD\n  subgraph A\n    a\n  end\n  subgraph B\n    b\n  end\n"
                + String(repeating: "  a -- label --> b\n", count: 2_500)),
            ("3,000 self-loops", "swimlane-beta TD\n  subgraph A\n    a\n  end\n" + String(repeating: "  a --> a\n", count: 3_000)),
            ("1,000 edges between lanes themselves", "swimlane-beta TD\n" + lanes(20) { lane in "    a\(lane)" }
                + Self.repeated(1_000) { index in "  L\(index % 20) --> L\((index * 7 + 3) % 20)\n" }),
            ("a cycle through every node", "swimlane-beta RL\n" + lanes(10) { lane in Self.repeated(60) { index in "    n\(lane * 60 + index)\n" } }
                + Self.repeated(600) { index in "  n\(index) --> n\((index * 37 + 11) % 600)\n  n\((index * 37 + 11) % 600) --> n\(index)\n" }),
        ], seconds: 10, laidOutCount: 8)
    }
}
