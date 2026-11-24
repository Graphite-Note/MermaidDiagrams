/**
 * File: FlowchartReadingSpeedTests.swift
 * --------------------------------------
 * Layer: Tests
 * Description: Guards what the faster flowchart reading must keep: identifiers that Swift's strings count as equal name
 *              one node, a node named before its shape keeps the text it is given, styles and attributes read as before;
 *              and writes every model the reader makes of the spec texts and corpora, to compare two builds.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class FlowchartReadingSpeedTests: XCTestCase {
    private func flowchart(_ source: String) throws -> FlowchartDiagram {
        guard case .flowchart(let diagram) = try MermaidDiagramReader.read(source, limits: .standard) else {
            throw XCTSkip("not a flowchart")
        }
        return diagram
    }

    /// Identifiers are looked up by their bytes first; a spelling whose bytes differ but which Swift's strings count as the
    /// same text (a Hangul syllable against its letters, the Ohm sign against omega, the Kelvin sign against `K`) names the same node, as
    /// the dictionary of strings made it.
    func testCanonicallyEquivalentIdentifiersNameOneNode() throws {
        let diagram = try flowchart("flowchart LR\n  \u{AC00}[first] --> \u{1100}\u{1161}\n  \u{212A} --> K[kelvin]\n  K --> \u{212A}\n  \u{2126} --> \u{3A9}\n")
        XCTAssertEqual(diagram.nodes.map { node in Array(node.identifier.unicodeScalars) }, [["\u{AC00}"], ["\u{212A}"], ["\u{2126}"]])
        XCTAssertEqual(diagram.nodes.map(\.label), [DiagramLabel("first"), DiagramLabel("kelvin"), DiagramLabel("\u{2126}")])
        XCTAssertEqual(diagram.edges.map { edge in [edge.sourceIndex, edge.targetIndex] }, [[0, 0], [1, 1], [1, 1], [2, 2]])
    }

    /// A node named for the first time with a shape and text shows that text, and one named without shows its identifier,
    /// read as a label (`a\nb` breaks); a node given an icon without a label of its own shows none.
    func testNewNodesTakeTheirTextOrTheirIdentifier() throws {
        let diagram = try flowchart("flowchart TD\n  A[Alpha] --> B\n  B --> C(Gamma)\n  D@{ icon: \"fa:user\" } --> E@{ label: \"Epsilon\" }\n")
        XCTAssertEqual(diagram.nodes.map(\.label), [DiagramLabel("Alpha"), DiagramLabel("B"), DiagramLabel("Gamma"), DiagramLabel(lines: [""]),
                                                    DiagramLabel("Epsilon")])
        XCTAssertEqual(diagram.edges.count, 3)
    }

    /// A node written again with the same brackets and text keeps them; attributes or other brackets written between
    /// change it, and the same brackets written after that set them again.
    func testShapesWrittenAgainSetTheNodeAsWritten() throws {
        let diagram = try flowchart("flowchart TD\n  A[x] --> B\n  A[x] --> C\n  A@{ label: y } --> D\n  A[x] --> E\n  F(f) --> F(f)\n  F((f))\n  G[g] --> G@{ shape: diam }\n  G[g]\n")
        let nodes = Dictionary(uniqueKeysWithValues: diagram.nodes.map { node in (node.identifier, node) })
        XCTAssertEqual(nodes["A"]?.label, DiagramLabel("x"))
        XCTAssertEqual(nodes["A"]?.shape, .rectangle)
        XCTAssertEqual(nodes["F"]?.shape, .circle)
        XCTAssertEqual(nodes["G"]?.shape, .rectangle)
        let relabelled = try flowchart("flowchart TD\n  A[x] --> B\n  A@{ label: y }\n")
        XCTAssertEqual(relabelled.nodes.first?.label, DiagramLabel("y"))
    }

    /// Statements that style nodes and edges still style them, and a diagram without any leaves every style nil.
    func testStylesAreAppliedAndAbsentStylesStayNil() throws {
        let styled = try flowchart("flowchart LR\n  A --> B --> C\n  classDef hot fill:#f00\n  class A hot\n  style B stroke:#00f\n  linkStyle 1 stroke:#0f0\n")
        XCTAssertNotNil(styled.nodes[0].style)
        XCTAssertNotNil(styled.nodes[1].style)
        XCTAssertNil(styled.nodes[2].style)
        XCTAssertNil(styled.edges[0].style)
        XCTAssertNotNil(styled.edges[1].style)
        let plain = try flowchart("flowchart LR\n  A --> B --> C\n  classDef unused fill:#f00\n")
        XCTAssertTrue(plain.nodes.allSatisfy { node in node.style == nil })
        XCTAssertTrue(plain.edges.allSatisfy { edge in edge.style == nil })
    }

    /// With `MERMAID_DIAGRAMS_FLOWCHART_MODEL_DUMP` set to a file, writes the reading of every text of Pele's compatibility
    /// specs of every type, the flowchart spec texts, the documentation examples and Pele's generated flowcharts: the model
    /// in full or the error, one per line, so that two builds can be compared with `diff` (with `SWIFT_DETERMINISTIC_HASHING=1`
    /// set too, so that the models' dictionaries list their keys in the same order in both).
    func testWriteEveryModelWhenAsked() throws {
        guard let path = ProcessInfo.processInfo.environment["MERMAID_DIAGRAMS_FLOWCHART_MODEL_DUMP"] else {
            throw XCTSkip("MERMAID_DIAGRAMS_FLOWCHART_MODEL_DUMP is not set")
        }
        var sources = try PeleResults.flowchartSpecTexts().map(\.source)
        sources += try PeleResults.compatInputs().sorted { first, second in first.key < second.key }.flatMap(\.value)
        sources += try FlowchartCorpus.documentationExamples()
        sources += [FlowchartCorpus.tree(nodeCount: 50), FlowchartCorpus.tree(nodeCount: 500),
                    FlowchartCorpus.mesh(nodeCount: 50, extraEdgeCount: 20), FlowchartCorpus.mesh(nodeCount: 500, extraEdgeCount: 200)]
        sources += Self.edgeCases
        var lines: [String] = []
        for (index, source) in sources.enumerated() {
            let reading: String
            do {
                reading = String(reflecting: try MermaidDiagramReader.read(source, limits: .standard))
            } catch {
                reading = "error \(String(reflecting: error))"
            }
            lines.append("\(index) \(reading)")
        }
        try (lines.joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// Texts for the dump that reach the reader's less usual paths: identifiers beyond ASCII and equal as strings, link
    /// identifiers, direction statements, attributes over lines, styles, groups, refusals and long lines.
    private static let edgeCases: [String] = [
        "flowchart LR\n  \u{AC00} --> \u{1100}\u{1161} --> \u{212A} --> K\n  subgraph \u{212A}\n  K\n  \u{1100}\u{1161}\n  end\n  subgraph \u{AC00}x\n  \u{1100}\u{1161}x\n  end\n  style \u{2126} fill:#f00\n  \u{3A9} --> \u{2126}\n",
        "flowchart LR\n  e1@--> B\n  A e1@--> B\n  e1@{ animate: true }\n  A --- B\n",
        "flowchart TB\n  subgraph one\n  direction LR\n  a1 --> a2\n  end\n  subgraph two [Two words]\n  direction BT\n  b1 --> b2\n  end\n  one --> two\n",
        "flowchart TD\n  A@{ shape: diam, label: \"a\n  b\" }\n  B@{\n    shape: rounded\n    label: Bee\n  }\n  A --> B\n",
        "flowchart TD\n  A@{ shape: nothing }\n",
        "flowchart TD\n  A@{ shape: diam\n",
        "flowchart TD\n  A@{ shape: [diam }\n",
        "flowchart TD\n  A[a (b) c]\n",
        "flowchart TD\n  A[] --> B\n",
        "flowchart TD\n  A --> \n",
        "flowchart TD\n  A & B --> C & D\n  A &B\n",
        "flowchart TD\n  A:::hot --> B:::cold:::warm\n  classDef hot fill:#f00\n  classDef default stroke:#333\n  style C fill:#0f0\n  linkStyle default stroke:#00f\n  linkStyle 0,7 stroke:#f00\n",
        "flowchart TD\n  A -- text --> B -. dotted .-> C == thick ==> D ~~~ E\n  A -->|bar| B\n  A <--> B\n  A x--o B\n  A ---->|long| B\n",
        "flowchart TD\n  A[\"`**bold** text`\"] --> B[\"quoted\"] --> C[/lean/] --> D[\\lean\\] --> E[/trap\\] --> F[\\inv/]\n  G(-ellipse-) --> H>flag] --> I{{hex}} --> J[(db)] --> K((c)) --> L(((dc))) --> M([st]) --> N[[sub]]\n",
        "flowchart TD\n  A[|borders:lt|text] --> B\n  click A callback\n  accTitle: The title\n  accDescr { A long\n  description }\n",
        "flowchart TD\n  subgraph\n  end\n  end\n",
        "flowchart TD\n  subgraph A\n  B\n",
        "flowchart TD\n  subgraph myTitle   \n  x\n  end\n  subgraph \"quoted title\"\n  y\n  end\n",
        "flowchart TD\n  " + String(repeating: "a:", count: 4000) + "\n",
        "flowchart TD\n  " + String(repeating: "&", count: 4000) + "\n",
        "flowchart TD\n  " + (0..<300).map { index in "n\(index)" }.joined(separator: " --> ") + "\n",
        "flowchart TD\n  classes --> B\n  end1 --> subgraph1\n  style1 --> default.node\n  #node --> :node\n  odd- --> v\n",
        "graph LR;A-->B;B-->C;%% comment\nC-->D\n",
        "flowchart\n  direction RL\n  A --> B\n",
        "flowchart XY\n  A\n",
        "flowchart TD\n  \u{4E2D}\u{6587} --> \u{0645}\u{0631}\u{062D}\u{0628}\u{0627} --> \u{1F600}\n",
    ]
}
