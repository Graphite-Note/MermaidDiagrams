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
        let table = Self.exactKeywordsByLength
        guard keyword.count < table.count else {
            self = .other
            return
        }
        for (spelling, type) in table[keyword.count] where Self.spells(keyword, spelling) {
            self = type
            return
        }
        self = .other
    }

    /// The exact keywords and their types by their length, made once.
    private static let exactKeywordsByLength = (0...17).map(exactKeywords(ofLength:))

    /// The exact keywords of one length and their types, as `MermaidDiagramReader` named them by their text.
    private static func exactKeywords(ofLength length: Int) -> [(StaticString, MermaidTypeKeyword)] {
        switch length {
        case 3: [("pie", .pieChart)]
        case 4: [("info", .info)]
        case 5: [("graph", .flowchart), ("gantt", .ganttChart), ("block", .block)]
        case 6: [("sankey", .sankey), ("kanban", .kanban), ("packet", .packet)]
        case 7: [("mindmap", .mindmap), ("journey", .userJourney), ("xychart", .xyChart), ("treemap", .treemap)]
        case 8: [("timeline", .timeline), ("gitGraph", .gitGraph)]
        case 9: [("flowchart", .flowchart), ("erDiagram", .entityRelationship), ("venn-beta", .venn)]
        case 10: [("radar-beta", .radar), ("block-beta", .block)]
        case 11: [("sankey-beta", .sankey), ("packet-beta", .packet)]
        case 12: [("stateDiagram", .stateDiagram), ("classDiagram", .classDiagram), ("xychart-beta", .xyChart), ("treemap-beta", .treemap),
                  ("cynefin-beta", .cynefin), ("wardley-beta", .wardleyMap), ("architecture", .architecture), ("usecase-beta", .useCase)]
        case 13: [("flowchart-elk", .flowchart), ("swimlane-beta", .swimlane), ("quadrantChart", .quadrantChart), ("treeView-beta", .treeView)]
        case 14: [("agentflow-beta", .agentFlow)]
        case 15: [("stateDiagram-v2", .stateDiagram), ("classDiagram-v2", .classDiagram), ("sequenceDiagram", .sequence)]
        case 17: [("architecture-beta", .architecture)]
        default: []
        }
    }

    private static func spells(_ keyword: UnsafeBufferPointer<UInt8>, _ word: StaticString) -> Bool {
        let letters = word.utf8Start
        for index in 0..<keyword.count where keyword[index] != letters[index] { return false }
        return true
    }
}
