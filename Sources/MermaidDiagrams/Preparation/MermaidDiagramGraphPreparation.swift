/**
 * File: MermaidDiagramGraphPreparation.swift
 * ------------------------------------------
 * Layer: Core
 * Description: Prepares the graph-shaped diagrams: flowcharts, state, class, sequence and entity relationship diagrams
 *              and Git graphs, with their narrow-column layouts.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 23/11/2026
 */

extension MermaidDiagramPreparationContext {
    /// A flowchart, and for a narrow column the flowchart as Pele fits it: turned to run down, with Pele's tighter gaps.
    func prepared(_ flowchart: FlowchartDiagram) throws(MermaidDiagramPreparationFailure) -> PreparedMermaidDiagram {
        let layout: FlowchartLayout
        do { layout = try FlowchartLayoutEngine.layout(flowchart, typography: typography, limits: limits) } catch { throw .flowchartLayout(error) }
        let narrow = narrowSceneIsWanted(forRegularSize: layout.size)
            ? narrowScene(of: narrowestColumnWidth.map { width in (flowchart, width) }, regularSize: layout.size, laidOut: { flowchart, width in
                try FlowchartLayoutEngine.layout(flowchart, typography: typography, limits: limits, availableWidth: width)
            }, scene: DiagramScene.init(layout:)) : nil
        return PreparedMermaidDiagram(kind: .flowchart, scene: DiagramScene(layout: layout), preparedNarrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(flowchart: flowchart),
                                      unappliedStatementCount: flowchart.unappliedStatementCount)
    }

    func prepared(_ stateDiagram: StateDiagram) throws(MermaidDiagramPreparationFailure) -> PreparedMermaidDiagram {
        let layout: StateDiagramLayout
        do { layout = try StateDiagramLayoutEngine.layout(stateDiagram, typography: typography, limits: limits) } catch { throw .stateDiagramLayout(error) }
        let narrow = narrowSceneIsWanted(forRegularSize: layout.size)
            ? narrowScene(of: narrowestColumnWidth.map { width in (stateDiagram, width) }, regularSize: layout.size, laidOut: { stateDiagram, width in
                try StateDiagramLayoutEngine.layout(stateDiagram, typography: typography, limits: limits, availableWidth: width)
            }, scene: DiagramScene.init(layout:)) : nil
        return PreparedMermaidDiagram(kind: .stateDiagram, scene: DiagramScene(layout: layout), preparedNarrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(stateDiagram: stateDiagram, layout: layout),
                                      unappliedStatementCount: stateDiagram.unappliedStatementCount)
    }

    func prepared(_ classDiagram: ClassDiagram) throws(MermaidDiagramPreparationFailure) -> PreparedMermaidDiagram {
        let layout: ClassDiagramLayout
        do { layout = try ClassDiagramLayoutEngine.layout(classDiagram, typography: typography, limits: limits) } catch { throw .classDiagramLayout(error) }
        let narrow = narrowSceneIsWanted(forRegularSize: layout.size)
            ? narrowScene(of: narrowestColumnWidth.map { width in (classDiagram, width) }, regularSize: layout.size, laidOut: { classDiagram, width in
                try ClassDiagramLayoutEngine.layout(classDiagram, typography: typography, limits: limits, availableWidth: width)
            }, scene: DiagramScene.init(layout:)) : nil
        return PreparedMermaidDiagram(kind: .classDiagram, scene: DiagramScene(layout: layout), preparedNarrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(classDiagram: classDiagram),
                                      unappliedStatementCount: classDiagram.unappliedStatementCount)
    }

    func prepared(_ sequence: SequenceDiagram) throws(MermaidDiagramPreparationFailure) -> PreparedMermaidDiagram {
        let layout: SequenceLayout
        do { layout = try SequenceLayoutEngine.layout(sequence, typography: typography) } catch { throw .sequenceLayout(error) }
        let narrow = narrowSceneIsWanted(forRegularSize: layout.size)
            ? narrowScene(of: narrowestColumnWidth.map { width in (sequence, width) }, regularSize: layout.size, laidOut: { sequence, width in
                try SequenceLayoutEngine.layout(sequence, typography: typography, availableWidth: width)
            }, scene: DiagramScene.init(layout:)) : nil
        return PreparedMermaidDiagram(kind: .sequence, scene: DiagramScene(layout: layout), preparedNarrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(sequence: sequence))
    }

    func prepared(_ diagram: EntityRelationshipDiagram) throws(MermaidDiagramPreparationFailure) -> PreparedMermaidDiagram {
        let layout: EntityRelationshipLayout
        do {
            layout = try EntityRelationshipLayoutEngine.layout(diagram, typography: typography, limits: limits)
        } catch {
            throw .entityRelationshipLayout(error)
        }
        let narrow = turnedNarrowSceneIsWanted(forRegularSize: layout.size)
            ? turnedNarrowScene(of: diagram.turnedTopToBottom, regularSize: layout.size, laidOut: { turned in
                try EntityRelationshipLayoutEngine.layout(turned, typography: typography, limits: limits)
            }, scene: DiagramScene.init(layout:)) : nil
        return PreparedMermaidDiagram(kind: .entityRelationship, scene: DiagramScene(layout: layout), preparedNarrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(entityRelationship: diagram),
                                      unappliedStatementCount: diagram.unappliedStatementCount)
    }

    /// A Git graph, and for a narrow column the graph with its commits from the top down.
    func prepared(_ gitGraph: GitGraphDiagram) throws(MermaidDiagramPreparationFailure) -> PreparedMermaidDiagram {
        let layout: GitGraphLayout
        do { layout = try GitGraphLayoutEngine.layout(gitGraph, typography: typography) } catch { throw .gitGraphLayout(error) }
        let narrow = turnedNarrowSceneIsWanted(forRegularSize: layout.size)
            ? turnedNarrowScene(of: gitGraph.turnedToRunDown, regularSize: layout.size, laidOut: { turned in
                try GitGraphLayoutEngine.layout(turned, typography: typography)
            }, scene: DiagramScene.init(layout:)) : nil
        return PreparedMermaidDiagram(kind: .gitGraph, scene: DiagramScene(layout: layout), preparedNarrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(gitGraph: gitGraph))
    }
}
