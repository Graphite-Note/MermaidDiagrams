/**
 * File: MermaidTypeKeyword.swift
 * ------------------------------
 * Layer: Core
 * Description: The diagram types the reader tells from its keyword's bytes before making a String of it: every type
 *              one exact keyword names; the types told by a prefix or by their reader are named by the keyword's text.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

/// The type a keyword names, told from its bytes: by its length, then its spelling, for every type an exact keyword
/// names (`flowchart`, `graph`, `stateDiagram-v2`, `pie`, `radar-beta` …); `other` for the rest (Ishikawa diagrams in
/// any case, event models, railroad notations, C4 levels, requirement diagrams, and what names no type), which the
/// reader tells from the keyword's text as before. No keyword of `other`'s types is one of the exact keywords.
enum MermaidTypeKeyword {
    case flowchart
    case swimlane
    case stateDiagram
    case classDiagram
    case sequence
    case entityRelationship
    case mindmap
    case timeline
    case pieChart
    case ganttChart
    case gitGraph
    case userJourney
    case quadrantChart
    case xyChart
    case sankey
    case kanban
    case treeView
    case info
    case packet
    case radar
    case treemap
    case venn
    case cynefin
    case wardleyMap
    case block
    case architecture
    case useCase
    case agentFlow
    case other

    init(_ keyword: UnsafeBufferPointer<UInt8>) {
        for (spelling, type) in Self.exactKeywords where spelling.utf8CodeUnitCount == keyword.count && Self.spells(keyword, spelling) {
            self = type
            return
        }
        self = .other
    }

    /// Every exact keyword and its type, as `MermaidDiagramReader` named them by their text.
    private static let exactKeywords: [(StaticString, MermaidTypeKeyword)] = [
        ("graph", .flowchart), ("flowchart", .flowchart), ("flowchart-elk", .flowchart), ("swimlane-beta", .swimlane),
        ("stateDiagram", .stateDiagram), ("stateDiagram-v2", .stateDiagram), ("classDiagram", .classDiagram), ("classDiagram-v2", .classDiagram),
        ("sequenceDiagram", .sequence), ("erDiagram", .entityRelationship), ("mindmap", .mindmap), ("timeline", .timeline), ("pie", .pieChart),
        ("gantt", .ganttChart), ("gitGraph", .gitGraph), ("journey", .userJourney), ("quadrantChart", .quadrantChart), ("xychart", .xyChart),
        ("xychart-beta", .xyChart), ("sankey", .sankey), ("sankey-beta", .sankey), ("kanban", .kanban), ("treeView-beta", .treeView),
        ("info", .info), ("packet", .packet), ("packet-beta", .packet), ("radar-beta", .radar), ("treemap", .treemap), ("treemap-beta", .treemap),
        ("venn-beta", .venn), ("cynefin-beta", .cynefin), ("wardley-beta", .wardleyMap), ("block", .block), ("block-beta", .block),
        ("architecture", .architecture), ("architecture-beta", .architecture), ("usecase-beta", .useCase), ("agentflow-beta", .agentFlow),
    ]

    private static func spells(_ keyword: UnsafeBufferPointer<UInt8>, _ word: StaticString) -> Bool {
        let letters = word.utf8Start
        for index in 0..<keyword.count where keyword[index] != letters[index] { return false }
        return true
    }
}
