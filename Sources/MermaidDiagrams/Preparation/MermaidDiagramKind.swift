/**
 * File: MermaidDiagramKind.swift
 * ------------------------------
 * Layer: Core
 * Description: The diagram types drawn, with Pele's name of each and what a screen reader calls one without a title.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// A diagram type the package reads, lays out and draws.
public enum MermaidDiagramKind: String, CaseIterable, Sendable {
    case flowchart
    case sequence
    case classDiagram
    case stateDiagram
    case entityRelationship
    case pieChart
    case ganttChart
    case gitGraph
    case mindmap
    case timeline
    case userJourney
    case quadrantChart
    case xyChart
    case sankey

    /// Pele's name of the type, which its SVG's root class (`pele-<name>`) and role description carry.
    public var peleName: String {
        switch self {
        case .flowchart: "flowchart"
        case .sequence: "sequence"
        case .classDiagram: "class"
        case .stateDiagram: "state"
        case .entityRelationship: "er"
        case .pieChart: "pie"
        case .ganttChart: "gantt"
        case .gitGraph: "gitGraph"
        case .mindmap: "mindmap"
        case .timeline: "timeline"
        case .userJourney: "journey"
        case .quadrantChart: "quadrantChart"
        case .xyChart: "xychart"
        case .sankey: "sankey"
        }
    }

    /// What a screen reader calls a diagram of the type that has no title, in English.
    public var spokenName: String {
        switch self {
        case .flowchart: "Flowchart"
        case .sequence: "Sequence diagram"
        case .classDiagram: "Class diagram"
        case .stateDiagram: "State diagram"
        case .entityRelationship: "Entity relationship diagram"
        case .pieChart: "Pie chart"
        case .ganttChart: "Gantt chart"
        case .gitGraph: "Git graph"
        case .mindmap: "Mindmap"
        case .timeline: "Timeline"
        case .userJourney: "User journey"
        case .quadrantChart: "Quadrant chart"
        case .xyChart: "XY chart"
        case .sankey: "Sankey diagram"
        }
    }
}

extension MermaidDiagram {
    /// The diagram's type.
    public var kind: MermaidDiagramKind {
        switch self {
        case .flowchart: .flowchart
        case .stateDiagram: .stateDiagram
        case .classDiagram: .classDiagram
        case .sequence: .sequence
        case .entityRelationship: .entityRelationship
        case .mindmap: .mindmap
        case .timeline: .timeline
        case .pieChart: .pieChart
        case .ganttChart: .ganttChart
        case .gitGraph: .gitGraph
        case .userJourney: .userJourney
        case .quadrantChart: .quadrantChart
        case .xyChart: .xyChart
        case .sankey: .sankey
        }
    }
}
