/**
 * File: MermaidDiagramKind.swift
 * ------------------------------
 * Layer: Core
 * Description: The diagram types drawn, with Pele's name of each and what a screen reader calls one without a title.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
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
    case kanban
    case treeView
    case ishikawa
    case info
    case packet
    case radar
    case treemap
    case venn
    case cynefin
    case wardleyMap
    case eventModel
    case railroad
    case block

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
        case .kanban: "kanban"
        case .treeView: "treeView"
        case .ishikawa: "ishikawa"
        case .info: "info"
        case .packet: "packet"
        case .radar: "radar"
        case .treemap: "treemap"
        case .venn: "venn"
        case .cynefin: "cynefin"
        case .wardleyMap: "wardley"
        case .eventModel: "eventmodeling"
        case .railroad: "railroad"
        case .block: "block"
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
        case .kanban: "Kanban board"
        case .treeView: "Tree view"
        case .ishikawa: "Ishikawa diagram"
        case .info: "Info diagram"
        case .packet: "Packet diagram"
        case .radar: "Radar chart"
        case .treemap: "Treemap"
        case .venn: "Venn diagram"
        case .cynefin: "Cynefin framework"
        case .wardleyMap: "Wardley map"
        case .eventModel: "Event model"
        case .railroad: "Railroad diagram"
        case .block: "Block diagram"
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
        case .kanban: .kanban
        case .treeView: .treeView
        case .ishikawa: .ishikawa
        case .info: .info
        case .packet: .packet
        case .radar: .radar
        case .treemap: .treemap
        case .venn: .venn
        case .cynefin: .cynefin
        case .wardleyMap: .wardleyMap
        case .eventModel: .eventModel
        case .railroad: .railroad
        case .block: .block
        }
    }
}
