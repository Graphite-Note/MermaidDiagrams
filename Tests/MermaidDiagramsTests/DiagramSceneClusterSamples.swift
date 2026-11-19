/**
 * File: DiagramSceneClusterSamples.swift
 * --------------------------------------
 * Layer: Tests
 * Description: Samples of the boxes and shapes Pele draws beyond the documentation examples: stray edges, cross-flow
 *              exits, composite surroundings, nested namespaces and groups, every flowchart shape.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

@testable import MermaidDiagrams

/// Texts that exercise what the documentation examples leave out of the boxes and shapes: the scene, SVG and preparation
/// tests run over them with the other samples, and the safety tests cut and change them.
enum DiagramSceneClusterSamples {
    static let all: [(String, String)] = [
        ("flowchart every shape", "flowchart LR\n" + FlowchartNodeShape.documentedNames.enumerated().map { index, entry in
            "N\(index)@{ shape: \(entry.1[0]), label: \"\(entry.1[0])\" }"
        }.joined(separator: " --> ") + "\nE(-ellipse-)\nstyle N44 fill:#fde,stroke:#c06\nstyle N26 fill:#dfe"),
        ("flowchart edges into a group", "flowchart TD\nsubgraph one [Group]\nA --> B\nend\nA --> one\none --> one\nC --> A\nsubgraph two\nD\nend\ntwo --> D"),
        ("flowchart exits across a group", "flowchart TB\nX --> A\nX --> B\nX --> C\nsubgraph S [Across]\ndirection LR\nA --> D\nB --> D\nC --> D\nend\nD --> Y"),
        ("flowchart nested collapsed groups",
         "flowchart TD\nsubgraph outer\nsubgraph inner [Folded]\nA --> B\nend\nC --> inner\nend\ninner --> D\nB --> E\ninner@{ view: collapsed }"),
        ("state composite surroundings", """
            stateDiagram-v2
            [*] --> Moving
            state Moving {
              slow --> fast
              fast --> slow
            }
            Moving --> slow : enter
            fast --> Moving : leave
            Moving --> Moving : again
            note left of Moving : busy all day
            note right of Moving : also here
            Moving --> [*]
            """),
        ("class nested namespaces", """
            classDiagram
            namespace A.B {
              class One
            }
            namespace A {
              class Two
              namespace C {
                class Three
              }
            }
            namespace Empty {
            }
            One --> Two : uses
            Three --> One
            Two "1" --> "*" Four
            """),
        ("er nested groups", """
            erDiagram
            direction LR
            subgraph outer [Outer group]
              direction TB
              A ||--o{ B : has
              subgraph inner
                C
              end
            end
            inner ||--|| D : links
            outer }o--|| E : holds
            C ||--|| outer : inside
            """),
    ]
}
