/**
 * File: MermaidDiagramGraphPreparation.swift
 * ------------------------------------------
 * Layer: Core
 * Description: Prepares the graph-shaped diagrams: flowcharts, state, class, sequence and entity relationship diagrams
 *              and Git graphs, with their narrow-column layouts.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

extension MermaidDiagramPreparationContext {
    /// A flowchart, and for a narrow column the flowchart turned to run down with Pele's tighter gaps.
    func prepared(_ flowchart: FlowchartDiagram) throws(MermaidDiagramPreparationFailure) -> PreparedMermaidDiagram {
        let layout: FlowchartLayout
        do { layout = try FlowchartLayoutEngine.layout(flowchart, typography: typography, limits: limits) } catch { throw .flowchartLayout(error) }
        let narrow = narrowScene(of: flowchart.turnedToRunDown ?? flowchart, regularSize: layout.size, laidOut: { turned in
            try FlowchartLayoutEngine.layout(turned, typography: typography, limits: limits, spacing: .compact)
        }, scene: DiagramScene.init(layout:))
        return PreparedMermaidDiagram(kind: .flowchart, scene: DiagramScene(layout: layout), narrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(flowchart: flowchart),
                                      unappliedStatementCount: flowchart.unappliedStatementCount)
    }

    func prepared(_ stateDiagram: StateDiagram) throws(MermaidDiagramPreparationFailure) -> PreparedMermaidDiagram {
        let layout: StateDiagramLayout
        do { layout = try StateDiagramLayoutEngine.layout(stateDiagram, typography: typography, limits: limits) } catch { throw .stateDiagramLayout(error) }
        let narrow = narrowScene(of: stateDiagram.turnedToRunDown, regularSize: layout.size, laidOut: { turned in
            try StateDiagramLayoutEngine.layout(turned, typography: typography, limits: limits)
        }, scene: DiagramScene.init(layout:))
        return PreparedMermaidDiagram(kind: .stateDiagram, scene: DiagramScene(layout: layout), narrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(stateDiagram: stateDiagram, layout: layout),
                                      unappliedStatementCount: stateDiagram.unappliedStatementCount)
    }

    func prepared(_ classDiagram: ClassDiagram) throws(MermaidDiagramPreparationFailure) -> PreparedMermaidDiagram {
        let layout: ClassDiagramLayout
        do { layout = try ClassDiagramLayoutEngine.layout(classDiagram, typography: typography, limits: limits) } catch { throw .classDiagramLayout(error) }
        let narrow = narrowScene(of: classDiagram.turnedToRunDown, regularSize: layout.size, laidOut: { turned in
            try ClassDiagramLayoutEngine.layout(turned, typography: typography, limits: limits)
        }, scene: DiagramScene.init(layout:))
        return PreparedMermaidDiagram(kind: .classDiagram, scene: DiagramScene(layout: layout), narrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(classDiagram: classDiagram),
                                      unappliedStatementCount: classDiagram.unappliedStatementCount)
    }

    func prepared(_ sequence: SequenceDiagram) throws(MermaidDiagramPreparationFailure) -> PreparedMermaidDiagram {
        let layout: SequenceLayout
        do { layout = try SequenceLayoutEngine.layout(sequence, typography: typography) } catch { throw .sequenceLayout(error) }
        return PreparedMermaidDiagram(kind: .sequence, scene: DiagramScene(layout: layout), accessibility: MermaidDiagramAccessibility(sequence: sequence))
    }

    func prepared(_ diagram: EntityRelationshipDiagram) throws(MermaidDiagramPreparationFailure) -> PreparedMermaidDiagram {
        let layout: EntityRelationshipLayout
        do {
            layout = try EntityRelationshipLayoutEngine.layout(diagram, typography: typography, limits: limits)
        } catch {
            throw .entityRelationshipLayout(error)
        }
        let narrow = narrowScene(of: diagram.turnedToRunDown, regularSize: layout.size, laidOut: { turned in
            try EntityRelationshipLayoutEngine.layout(turned, typography: typography, limits: limits)
        }, scene: DiagramScene.init(layout:))
        return PreparedMermaidDiagram(kind: .entityRelationship, scene: DiagramScene(layout: layout), narrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(entityRelationship: diagram),
                                      unappliedStatementCount: diagram.unappliedStatementCount)
    }

    /// A Git graph, and for a narrow column the graph with its commits from the top down.
    func prepared(_ gitGraph: GitGraphDiagram) throws(MermaidDiagramPreparationFailure) -> PreparedMermaidDiagram {
        let layout: GitGraphLayout
        do { layout = try GitGraphLayoutEngine.layout(gitGraph, typography: typography) } catch { throw .gitGraphLayout(error) }
        let narrow = narrowScene(of: gitGraph.turnedToRunDown, regularSize: layout.size, laidOut: { turned in
            try GitGraphLayoutEngine.layout(turned, typography: typography)
        }, scene: DiagramScene.init(layout:))
        return PreparedMermaidDiagram(kind: .gitGraph, scene: DiagramScene(layout: layout), narrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(gitGraph: gitGraph))
    }
}
