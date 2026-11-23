/**
 * File: MermaidDiagramReader.swift
 * --------------------------------
 * Layer: Core
 * Description: Reads Mermaid text: front matter, comments, directives and the diagram's type.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.22
 * Date: 23/11/2026
 */

import Foundation

/// A diagram read from Mermaid text, by type.
public enum MermaidDiagram: Equatable, Sendable {
    case flowchart(FlowchartDiagram)
    case stateDiagram(StateDiagram)
    case classDiagram(ClassDiagram)
    case sequence(SequenceDiagram)
    case entityRelationship(EntityRelationshipDiagram)
    case mindmap(MindmapDiagram)
    case timeline(TimelineDiagram)
    case pieChart(PieChart)
    case ganttChart(GanttChart)
    case gitGraph(GitGraphDiagram)
    case userJourney(UserJourneyDiagram)
    case quadrantChart(QuadrantChart)
    case xyChart(XYChart)
    case sankey(SankeyDiagram)
    case kanban(KanbanBoard)
    case treeView(TreeViewDiagram)
    case ishikawa(IshikawaDiagram)
    case info(InfoDiagram)
    case packet(PacketDiagram)
    case radar(RadarChart)
    case treemap(TreemapDiagram)
    case venn(VennDiagram)
    case cynefin(CynefinDiagram)
    case wardleyMap(WardleyMap)
    case eventModel(EventModelDiagram)
    case railroad(RailroadDiagram)
    case c4(C4Diagram)
    case block(BlockDiagram)
    case architecture(ArchitectureDiagram)
    case requirement(RequirementDiagram)
    /// A swimlane diagram: a flowchart whose top-level groups are lanes, read as a flowchart is.
    case swimlane(FlowchartDiagram)
    case useCase(UseCaseDiagram)
    case agentFlow(AgentFlowDiagram)
}

/// Reads Mermaid text as Pele does (preprocess.ts): line breaks made line feeds, the front matter (`---` … `---`),
/// whose `title:` is kept and which is refused when it is not YAML, tags' attributes put in single quotation marks,
/// directives (`%%{init: …}%%`) taken out wherever they
/// stand, a colour's last semicolon dropped (`MermaidPreprocessing`), comments, then the keyword that names the
/// diagram's type and the diagram itself.
public enum MermaidDiagramReader {
    public static func read(_ source: String, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> MermaidDiagram {
        guard source.utf8.count <= limits.maximumSourceBytes else { throw .sourceTooLarge(limitBytes: limits.maximumSourceBytes) }
        var (title, cursor) = try preprocessed(source)
        skipCommentsAndBlankLines(&cursor)
        guard let keyword = readTypeKeyword(&cursor) else {
            throw cursor.isAtEnd ? .noDiagram : .invalidSyntax(line: cursor.line, problem: .unexpectedText(cursor.excerpt()))
        }
        return try diagram(named: keyword, at: cursor, limits: limits, frontMatterTitle: title)
    }

    /// The diagram of the type `keyword` names, read from `cursor`: one of the fourteen types this package read first, or
    /// else one of those it reads since.
    private static func diagram(named keyword: String, at cursor: MermaidTextCursor, limits: MermaidDiagramLimits,
                                frontMatterTitle title: String?) throws(MermaidDiagramReadError) -> MermaidDiagram {
        switch keyword {
        case "flowchart", "graph", "flowchart-elk": return .flowchart(titled(try FlowchartParser.parse(cursor, limits: limits), frontMatterTitle: title))
        case "stateDiagram", "stateDiagram-v2": return .stateDiagram(titled(try StateDiagramParser.parse(cursor, limits: limits), frontMatterTitle: title))
        case "classDiagram", "classDiagram-v2": return .classDiagram(titled(try ClassDiagramParser.parse(cursor, limits: limits), frontMatterTitle: title))
        case "sequenceDiagram": return .sequence(titled(try SequenceParser.parse(cursor, limits: limits), frontMatterTitle: title))
        case "erDiagram": return .entityRelationship(titled(try EntityRelationshipParser.parse(cursor, limits: limits), frontMatterTitle: title))
        case "mindmap": return .mindmap(titled(try MindmapParser.parse(cursor, limits: limits), frontMatterTitle: title))
        case "timeline": return .timeline(titled(try TimelineParser.parse(cursor, limits: limits), frontMatterTitle: title))
        case "pie": return .pieChart(titled(try PieChartParser.parse(cursor, limits: limits), frontMatterTitle: title))
        case "gantt": return .ganttChart(titled(try GanttChartParser.parse(cursor, limits: limits), frontMatterTitle: title))
        case "gitGraph": return .gitGraph(titled(try GitGraphParser.parse(cursor, limits: limits), frontMatterTitle: title))
        case "journey": return .userJourney(titled(try UserJourneyParser.parse(cursor, limits: limits), frontMatterTitle: title))
        case "quadrantChart": return .quadrantChart(titled(try QuadrantChartParser.parse(cursor, limits: limits), frontMatterTitle: title))
        case "xychart", "xychart-beta": return .xyChart(titled(try XYChartParser.parse(cursor, limits: limits), frontMatterTitle: title))
        case "sankey", "sankey-beta": return .sankey(titled(try SankeyParser.parse(cursor, limits: limits), frontMatterTitle: title))
        default: return try newerDiagram(named: keyword, at: cursor, limits: limits, frontMatterTitle: title)
        }
    }

    /// The diagram of one of the types this package reads since its first fourteen, from the kanban board on, most of them
    /// written `-beta` in Mermaid.
    private static func newerDiagram(named keyword: String, at cursor: MermaidTextCursor, limits: MermaidDiagramLimits,
                                     frontMatterTitle title: String?) throws(MermaidDiagramReadError) -> MermaidDiagram {
        switch keyword {
        case "kanban": return .kanban(titled(try KanbanParser.parse(cursor, limits: limits), frontMatterTitle: title))
        case "treeView-beta": return .treeView(titled(try TreeViewParser.parse(cursor, limits: limits), frontMatterTitle: title))
        // Pele reads `ishikawa` and `ishikawa-beta` in any case, and what follows them on their line as text.
        case _ where keyword.lowercased().hasPrefix("ishikawa"):
            return .ishikawa(titled(try IshikawaParser.parse(keyword: keyword, endingAt: cursor, limits: limits), frontMatterTitle: title))
        case "info": return .info(titled(try InfoDiagramParser.parse(cursor), frontMatterTitle: title))
        case "packet", "packet-beta": return .packet(titled(try PacketDiagramParser.parse(cursor, limits: limits), frontMatterTitle: title))
        case "radar-beta": return .radar(titled(try RadarChartParser.parse(cursor, limits: limits), frontMatterTitle: title))
        case "treemap", "treemap-beta": return .treemap(titled(try TreemapDiagramParser.parse(cursor, limits: limits), frontMatterTitle: title))
        case "venn-beta": return .venn(titled(try VennParser.parse(cursor, limits: limits), frontMatterTitle: title))
        case "cynefin-beta": return .cynefin(titled(try CynefinParser.parse(cursor, limits: limits), frontMatterTitle: title))
        case "wardley-beta": return .wardleyMap(titled(try WardleyMapParser.parse(cursor, limits: limits), frontMatterTitle: title))
        case _ where keyword.hasPrefix("eventmodeling"):
            return .eventModel(titled(try EventModelParser.parse(cursor, keyword: keyword, limits: limits), frontMatterTitle: title))
        case _ where RailroadNotation(typeKeyword: keyword) != nil:
            return .railroad(titled(try RailroadParser.parse(cursor, keyword: keyword, limits: limits), frontMatterTitle: title))
        case _ where C4DiagramLevel(rawValue: keyword) != nil:
            return .c4(titled(try C4Parser.parse(keyword: keyword, endingAt: cursor, limits: limits), frontMatterTitle: title))
        case "block", "block-beta": return .block(titled(try BlockParser.parse(cursor, keyword: keyword, limits: limits), frontMatterTitle: title))
        case "architecture", "architecture-beta":
            return .architecture(titled(try ArchitectureParser.parse(cursor, keyword: keyword, limits: limits), frontMatterTitle: title))
        // Pele detects any text that starts with `requirement` as a requirement diagram; its lexer then reads the keyword.
        case _ where keyword.hasPrefix("requirement"):
            return .requirement(titled(try RequirementParser.parse(cursor, keyword: keyword, limits: limits), frontMatterTitle: title))
        case "swimlane-beta": return .swimlane(titled(try FlowchartParser.parse(cursor, limits: limits), frontMatterTitle: title))
        case "usecase-beta": return .useCase(titled(try UseCaseParser.parse(keyword: keyword, endingAt: cursor, limits: limits), frontMatterTitle: title))
        case "agentflow-beta": return .agentFlow(titled(try AgentFlowParser.parse(cursor, keyword: keyword, limits: limits), frontMatterTitle: title))
        default: throw .unsupportedDiagramType(keyword: keyword)
        }
    }

    /// `diagram` with the title its own `title` statement gives, else the front matter's, as in Mermaid.
    private static func titled<Diagram: TitledMermaidDiagram>(_ diagram: Diagram, frontMatterTitle: String?) -> Diagram {
        var titledDiagram = diagram
        if titledDiagram.title == nil { titledDiagram.title = frontMatterTitle }
        return titledDiagram
    }

    /// The front matter's title, and a cursor after the front matter on the text preprocessed as Pele does: line breaks
    /// made line feeds, tags' attributes single-quoted, directives removed, a colour's last semicolon dropped. A line
    /// the cursor counts is a line of that text: lines a directive spans count as one.
    static func preprocessed(_ source: String) throws(MermaidDiagramReadError) -> (title: String?, cursor: MermaidTextCursor) {
        var written = Array(source.utf8)
        if written.starts(with: byteOrderMark) { written.removeFirst(byteOrderMark.count) }
        let sourceBytes = MermaidPreprocessing.singleQuotingTagAttributes(MermaidPreprocessing.normalizedLineBreaks(written))
        let readFrontMatter = MermaidReadFrontMatter(in: sourceBytes)
        let (title, start) = try frontMatterTitleAndEnd(readFrontMatter, in: sourceBytes)
        let bytes = MermaidPreprocessing.droppingColorSemicolons(MermaidPreprocessing.removingDirectives(from: sourceBytes, from: start), from: start)
        var cursor = MermaidTextCursor(bytes: bytes, sourceBytes: sourceBytes)
        cursor.readFrontMatter = readFrontMatter
        cursor.advance(by: start)
        return (title, cursor)
    }

    /// The front matter's title and where the text after it starts (0 without front matter), found and read as Pele's
    /// `preprocess` does (`MermaidFrontMatter`). Front matter that is not YAML is refused, as Pele refuses it; a first
    /// line that is `---` alone with no closing fence is reported as unclosed front matter, where Pele finds no diagram.
    private static func frontMatterTitleAndEnd(_ read: MermaidReadFrontMatter,
                                               in bytes: [UInt8]) throws(MermaidDiagramReadError) -> (title: String?, end: Int) {
        guard let frontMatter = read.frontMatter else {
            var opening = MermaidTextCursor(bytes: bytes)
            opening.skipSpaces()
            if opening.hasPrefix(fence), opening.readRestOfLine() == "---" { throw .invalidSyntax(line: 1, problem: .unclosedFrontMatter) }
            return (nil, 0)
        }
        guard let value = read.value else {
            let firstLine = frontMatter.body.split(separator: "\n").first { line in !line.allSatisfy(\.isWhitespace) } ?? ""
            throw .invalidSyntax(line: 2, problem: .unexpectedText(String(firstLine.trimmingCharacters(in: .whitespaces).prefix(24))))
        }
        return (MermaidFrontMatter.title(in: value), frontMatter.end)
    }

    /// Skips what comes before the diagram's keyword: blank space, and comments, each to the end of its line.
    private static func skipCommentsAndBlankLines(_ cursor: inout MermaidTextCursor) {
        while true {
            cursor.skipWhitespace()
            guard cursor.hasPrefix(commentStart) else { return }
            cursor.skipToEndOfLine()
        }
    }

    /// The keyword that names the type: a letter, then letters, digits and `-` (`stateDiagram-v2`).
    private static func readTypeKeyword(_ cursor: inout MermaidTextCursor) -> String? {
        guard let first = cursor.peek(), MermaidByte.isLetter(first) else { return nil }
        let start = cursor.position
        while let byte = cursor.peek(), MermaidByte.isLetter(byte) || MermaidByte.isDigit(byte) || byte == MermaidByte.hyphen { cursor.advance() }
        return cursor.position > start ? cursor.text(from: start, to: cursor.position) : nil
    }

    private static let byteOrderMark: [UInt8] = [0xEF, 0xBB, 0xBF]
    private static let commentStart = Array("%%".utf8)
    private static let fence = Array("---".utf8)
}
