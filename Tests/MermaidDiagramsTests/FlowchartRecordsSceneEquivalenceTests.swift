/**
 * File: FlowchartRecordsSceneEquivalenceTests.swift
 * -------------------------------------------------
 * Layer: Tests
 * Description: The flowchart scene and the public drawing parts, which read the layout's flat records, paint what
 *              main ba176e5's code painted from the layout's nodes and edges as values (ReferenceFlowchartValueScene), to
 *              the bit, on every corpus, Pele's documentation examples, random and changed flowcharts, narrow layouts
 *              and swimlanes' flowcharts: the layout tests compare only those values, and the reference scene the lane
 *              tests use reads the records itself.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics
import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class FlowchartRecordsSceneEquivalenceTests: XCTestCase {
    private let typography = DiagramSceneSamples.typography

    /// Whether `source` is a flowchart or a swimlane, after comparing the scene and the drawing parts' scene of each of
    /// its layouts with the scene painted from the layout's values.
    private func assertSameScenes(_ source: String, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        var layouts: [FlowchartLayout] = []
        switch try? MermaidDiagramReader.read(source, limits: .standard) {
        case .flowchart(let flowchart)?:
            if let layout = try? FlowchartLayoutEngine.layout(flowchart, typography: typography, limits: .standard) { layouts.append(layout) }
            if let narrow = try? FlowchartLayoutEngine.layout(flowchart, typography: typography, limits: .standard, availableWidth: 280) {
                layouts.append(narrow)
            }
        case .swimlane(let flowchart)?:
            layouts.append(SwimlaneLayoutEngine.layout(flowchart, typography: typography).flowchart)
        default:
            return false
        }
        for layout in layouts {
            let expected = DiagramSceneTranscript.lines(of: ReferenceFlowchartValueScene.scene(layout: layout))
            XCTAssertEqual(DiagramSceneTranscript.lines(of: DiagramScene(layout: layout)), expected, "scene: " + String(source.prefix(80)), file: file, line: line)
            XCTAssertEqual(DiagramSceneTranscript.lines(of: ReferenceFlowchartScene.scene(layout: layout)), expected,
                           "drawing parts: " + String(source.prefix(80)), file: file, line: line)
        }
        return !layouts.isEmpty
    }

    func testCorpusScenesAreThosePaintedFromTheLayoutsValues() throws {
        var comparedCount = 0
        var sources = try OutputDigest.corpora().flatMap(\.sources)
        sources += try FlowchartCorpus.documentationExamples()
        for source in sources where assertSameScenes(source) { comparedCount += 1 }
        XCTAssertGreaterThan(comparedCount, 300)
    }

    func testRandomFlowchartScenesAreThosePaintedFromTheLayoutsValues() {
        var texts = FlowchartRandomTexts(seed: 0x7EC0_2D5)
        var comparedCount = 0
        for index in 0..<2_000 where assertSameScenes(texts.text(statementCount: 2 + index % 40)) { comparedCount += 1 }
        XCTAssertGreaterThan(comparedCount, 800)
    }

    /// Corpus flowcharts with styles, links styled, invisible links, icons and pictures put in, and changed at random.
    func testChangedFlowchartScenesAreThosePaintedFromTheLayoutsValues() throws {
        let flowcharts = try OutputDigest.corpora().flatMap(\.sources).filter { source in
            if case .flowchart? = try? MermaidDiagramReader.read(source, limits: .standard) { return true }
            return false
        }
        let pieces = GraphTextMutations.commonPieces + ["\nlinkStyle 0 stroke:#f00,stroke-width:3px\n", "\nlinkStyle default stroke:#0f0\n", " ~~~ ",
                                                        "\nstyle A fill:#f9f,color:#00f\n", ":::k", "\nclassDef k stroke:#000\n", " ==> ", " -.-> ",
                                                        "@{ icon: \"fa:x\", label: \"L\" }", "@{ img: \"https://x/y.png\", w: 20, h: 20 }",
                                                        "@{ icon: \"fa:y\", form: circle }", "@{ icon: \"fa:z\", form: square, label: \"\" }",
                                                        "@{ icon: \"fa:w\", form: rounded, label: \"\" }", " --o ", " --x ", "-->|t|"]
        var mutations = GraphTextMutations(seed: 0xF10C)
        var comparedCount = 0
        for round in 0..<1_500 {
            let source = mutations.mutated(flowcharts[round % flowcharts.count], pieces: pieces)
            if assertSameScenes(source) { comparedCount += 1 }
        }
        XCTAssertGreaterThan(comparedCount, 300)
    }

    /// Icons and pictures with text, without text, styled or not, in every form and direction: their frames are placed
    /// by whether the node has text, which the records keep as the text's line count.
    func testIconAndPictureNodesAreThosePaintedFromTheLayoutsValues() {
        let nodes = ["A@{ icon: \"fa:user\", form: square, label: \"\" }", "B@{ icon: \"fa:car\", form: circle, label: \"\" }",
                     "C@{ icon: \"fa:x\", form: rounded, label: \"Text\" }", "D@{ img: \"https://x/y.png\", label: \"\", w: 30, h: 30 }",
                     "E@{ img: \"https://x/z.png\", label: \"Picture\", pos: b, w: 40, h: 20 }", "F@{ icon: \"fa:y\", label: \"Below\", pos: b }",
                     "G@{ icon: \"fa:w\", form: square }"]
        var comparedCount = 0
        for direction in ["TD", "LR", "BT", "RL"] {
            for styled in [false, true] {
                var source = "flowchart \(direction)\n"
                for (index, node) in nodes.enumerated() { source += "  \(node) --> N\(index)\n" }
                if styled { source += "  style A fill:#f00\n  style D stroke:#0f0\n  classDef k fill:#00f\n  class B,E k\n" }
                if assertSameScenes(source) { comparedCount += 1 }
            }
        }
        XCTAssertEqual(comparedCount, 8)
    }
}
