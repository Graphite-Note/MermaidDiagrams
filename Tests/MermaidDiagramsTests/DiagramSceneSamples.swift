/**
 * File: DiagramSceneSamples.swift
 * -------------------------------
 * Layer: Tests
 * Description: The diagram texts every scene, SVG and preparation test runs over: every documentation example of the
 *              benchmark's corpora, a generated diagram heavy in series colors per type, and diagrams with styles.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

import Foundation
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

/// A diagram text of the samples, with what it is for in a failure message.
struct DiagramSceneSample {
    let name: String
    let source: String
}

/// The texts the scene tests run over, of all fourteen types: each documentation example the benchmark collects, a
/// generated diagram per type that uses many series colors or is large, and texts that set colors of their own.
enum DiagramSceneSamples {
    static var typography: DiagramTypography { DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16)) }

    /// The energy flows of Mermaid's specification, after `sankey-beta`, a blank line and a space, as the specification
    /// writes them.
    static func sankeyEnergy() throws -> String {
        "sankey-beta\n\n " + (try SankeyCorpus.energyRows())
    }

    static func all() throws -> [DiagramSceneSample] {
        let documentation: [(String, [String])] = [
            ("flowchart", try FlowchartCorpus.documentationExamples()), ("state", try StateDiagramCorpus.documentationExamples()),
            ("class", try ClassDiagramCorpus.documentationExamples()), ("sequence", try SequenceCorpus.documentationExamples()),
            ("er", try EntityRelationshipCorpus.documentationExamples()), ("mindmap", try MindmapCorpus.documentationExamples()),
            ("timeline", try TimelineCorpus.documentationExamples()), ("pie", try PieChartCorpus.documentationExamples()),
            ("gantt", try GanttChartCorpus.documentationExamples()), ("gitGraph", try GitGraphCorpus.documentationExamples()),
            ("journey", try UserJourneyCorpus.documentationExamples()), ("quadrantChart", try QuadrantChartCorpus.documentationExamples()),
            ("xychart", try XYChartCorpus.documentationExamples()), ("sankey", try SankeyCorpus.documentationExamples()),
        ]
        var samples = documentation.flatMap { type, sources in
            sources.enumerated().map { index, source in DiagramSceneSample(name: "\(type) documentation example \(index)", source: source) }
        }
        samples += try generated().map { name, source in DiagramSceneSample(name: name, source: source) }
        samples += styled.map { name, source in DiagramSceneSample(name: name, source: source) }
        samples += DiagramSceneOptionSamples.all.map { name, source in DiagramSceneSample(name: name, source: source) }
        return samples
    }

    /// One large or series-heavy diagram per type.
    private static func generated() throws -> [(String, String)] {
        [
            ("flowchart groups", FlowchartCorpus.groups(pairCount: 3, nodesPerGroup: 4)),
            ("flowchart mesh", FlowchartCorpus.mesh(nodeCount: 40, extraEdgeCount: 15)),
            ("state machine", StateDiagramCorpus.machine(stateCount: 20, extraTransitionCount: 10)),
            ("class hierarchy", ClassDiagramCorpus.hierarchy(classCount: 15)),
            ("sequence conversation", SequenceCorpus.conversation(participantCount: 6, messageCount: 30)),
            ("er schema", EntityRelationshipCorpus.schema(entityCount: 8)), ("mindmap tree", MindmapCorpus.tree(nodeCount: 40)),
            ("timeline of 30 periods", TimelineCorpus.generated(periodCount: 30)),
            ("timeline down", TimelineCorpus.generated(periodCount: 12, isDown: true)), ("pie of 20 slices", PieChartCorpus.pie(sliceCount: 20)),
            ("gantt of 30 tasks", GanttChartCorpus.chart(taskCount: 30)), ("git graph of 12 branches", GitGraphCorpus.generated(branchCount: 12)),
            ("journey of 20 tasks", UserJourneyCorpus.generated(taskCount: 20)), ("quadrant of 30 points", QuadrantChartCorpus.generated(pointCount: 30)),
            ("xy chart of 10 series", XYChartCorpus.generated(categoryCount: 8, seriesCount: 10)), ("sankey energy", try sankeyEnergy()),
            ("sankey layers", SankeyCorpus.generated(layerCount: 4, nodesPerLayer: 5)),
        ]
    }

    /// Texts that set colors, strokes, dashes and highlights of their own, with text that needs escaping.
    static let styled: [(String, String)] = [
        ("flowchart styled", """
            flowchart LR
                A["Tom & Jerry <b>"]:::hot --> B{"Is it #quot;quoted#quot;?"}
                B -->|yes| C([Done])
                B -.->|no| D[(Store)]
                C ==> E((End))
                classDef hot fill:#f96,stroke:#333,stroke-width:3px,color:#fff
                style D fill:#bbf,stroke:#f66,stroke-width:2px,stroke-dasharray: 5 5
                linkStyle 0 stroke:#ff3,stroke-width:4px
                linkStyle 2 stroke:red,stroke-dasharray: 2 2
            """),
        ("sequence highlighted", """
            sequenceDiagram
                autonumber
                actor Alice
                participant Bob
                rect rgb(191, 223, 255)
                Alice->>Bob: Hello <Bob> & co
                rect rgba(0, 0, 255, .1)
                Bob-->>Alice: Fine
                end
                end
                Note over Alice,Bob: A "note"
                loop Every minute
                    Alice-)Bob: Ping
                end
            """),
        ("quadrant colored points", """
            quadrantChart
                title Reach & engagement
                x-axis Low Reach --> High Reach
                y-axis Low Engagement --> High Engagement
                quadrant-1 We should expand
                quadrant-2 Need to promote
                Campaign A: [0.3, 0.6] radius: 12, color: #ff3300, stroke-color: #10f0f0, stroke-width: 5px
                Campaign B: [0.45, 0.23] color: #00ff33
                Campaign C: [0.57, 0.69]
            """),
        ("state with notes", """
            stateDiagram-v2
                [*] --> Still
                Still --> Moving : push <hard>
                Moving --> Crash
                note right of Moving : a "note" & more
                Crash --> [*]
            """),
        ("class members and note", """
            classDiagram
                class Shape {
                    <<interface>>
                    +String name$
                    +area()* double
                    +count()$ int
                    -List~Point~ points
                }
                class Circle {
                    +radius
                    +draw()*
                }
                Shape <|-- Circle : is a
                note for Circle "Drawn & <filled>"
            """),
    ]

    /// The diagram a sample's text describes, read with the standard limits.
    static func read(_ sample: DiagramSceneSample) throws -> MermaidDiagram {
        try MermaidDiagramReader.read(sample.source, limits: .standard)
    }
}
