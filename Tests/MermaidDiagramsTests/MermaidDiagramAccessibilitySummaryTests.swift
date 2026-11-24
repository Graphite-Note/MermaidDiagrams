/**
 * File: MermaidDiagramAccessibilitySummaryTests.swift
 * ---------------------------------------------------
 * Layer: Tests
 * Description: Checks that preparing a diagram of any type, and writing its SVG, leaves its spoken summary to the
 *              first reader, that the summary then made is the one the diagram's parts give, made once however many
 *              threads read it at the same time, and that accessibility values compare by what they say.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import Foundation
@testable import MermaidDiagrams
import XCTest

final class MermaidDiagramAccessibilitySummaryTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))

    /// One small diagram of each type whose summary reads its model or its layout.
    private static let sources = [
        "flowchart LR\n  A[Start] --> B{Ready?}\n  subgraph Group\n  C\n  end",
        "stateDiagram-v2\n  [*] --> Still\n  Still --> Moving",
        "classDiagram\n  class Animal",
        "sequenceDiagram\n  Alice->>Bob: Hello",
        "erDiagram\n  CUSTOMER ||--o{ ORDER : places",
        "mindmap\n  root\n    child",
        "timeline\n  2004 : Facebook : Google",
        "pie\n  \"Dogs\" : 79\n  \"Cats\" : 21",
        "journey\n  title Day\n  section Work\n    Do work: 1: Me, Cat",
        "quadrantChart\n  Campaign A: [0.3, 0.6]",
        "xychart-beta\n  x-axis [jan, feb]\n  bar [5000, 6000]",
        "sankey-beta\n\nCoal,Solid,75.57",
        "kanban\n  Todo\n    Write the docs",
        "gitGraph\n  commit id: \"init\"",
        "C4Context\n  Person(customer, \"Banking Customer\")",
        "requirementDiagram\n  requirement test_req {\n  id: 1\n  }",
    ]

    func testPreparingAndWritingTheSVGLeaveTheSummaryToItsFirstReader() throws {
        for source in Self.sources {
            let prepared = try MermaidDiagramPreparation.prepare(source: source, typography: typography, narrowestColumnWidth: nil)
            _ = prepared.svgDocument()
            XCTAssertFalse(prepared.accessibility.summaryParts.isMade, source)
            XCTAssertFalse(prepared.accessibility.summary.isEmpty, source)
            XCTAssertTrue(prepared.accessibility.summaryParts.isMade, source)
        }
    }

    func testTheSummaryMadeLaterIsTheOneItsPartsGive() throws {
        let flowchart = try MermaidDiagramPreparation.prepare(source: Self.sources[0], typography: typography, narrowestColumnWidth: nil)
        XCTAssertEqual(flowchart.accessibility.summary, ["Start", "Ready?", "C", "Group"])
        XCTAssertEqual(flowchart.accessibility.value, "Start, Ready?, C, Group")
        XCTAssertEqual(flowchart.accessibility.label, "Flowchart")
        let sequence = try MermaidDiagramPreparation.prepare(source: Self.sources[3], typography: typography, narrowestColumnWidth: nil)
        XCTAssertEqual(sequence.accessibility.value, "Alice, Bob. Alice to Bob: Hello")
        let pie = try MermaidDiagramPreparation.prepare(source: Self.sources[7], typography: typography, narrowestColumnWidth: nil)
        XCTAssertEqual(pie.accessibility.summary, ["Dogs 79%", "Cats 21%"])
    }

    func testThreadsReadingAtOnceAllGetTheSummaryMadeOnce() throws {
        let counter = MadeCounter()
        let accessibility = MermaidDiagramAccessibility(kind: .flowchart, title: nil, description: nil) {
            counter.add()
            return ["one", "two"]
        }
        let results = ResultStore(count: 64)
        DispatchQueue.concurrentPerform(iterations: 64) { index in
            results.set(index, accessibility.value)
        }
        XCTAssertEqual(counter.count, 1)
        XCTAssertEqual(Set(results.values), ["one, two"])
    }

    func testAccessibilityValuesCompareByWhatTheySay() {
        let made = MermaidDiagramAccessibility(kind: .pieChart, title: "Pets", description: nil, summary: ["Dogs 79%"])
        let later = MermaidDiagramAccessibility(kind: .pieChart, title: "Pets", description: nil) { ["Dogs 79%"] }
        let other = MermaidDiagramAccessibility(kind: .pieChart, title: "Pets", description: nil) { ["Cats 21%"] }
        XCTAssertEqual(made, later)
        XCTAssertNotEqual(made, other)
        XCTAssertNotEqual(made, MermaidDiagramAccessibility(kind: .pieChart, title: "Pets", description: nil, summary: ["Dogs 79%"],
                                                            summarySeparator: "; "))
    }
}

/// How many times a summary was made, counted from several threads.
private final class MadeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var made = 0

    func add() {
        lock.lock()
        made += 1
        lock.unlock()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return made
    }
}

/// The values threads read, one place each.
private final class ResultStore: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String]

    init(count: Int) {
        stored = Array(repeating: "", count: count)
    }

    func set(_ index: Int, _ value: String) {
        lock.lock()
        stored[index] = value
        lock.unlock()
    }

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}
