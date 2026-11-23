/**
 * File: MindmapParser.swift
 * -------------------------
 * Layer: Core
 * Description: Reads a mindmap's outline into its tree.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.3
 * Date: 23/11/2026
 */

/// Reads a mindmap's lines after its `mindmap` keyword, the rest of the keyword's own line included, as the outline Mermaid's
/// mindmap and kanban grammars share (`MermaidOutlineReader`): a node per line, indented to show its place in the tree;
/// an icon (`::icon(…)`) or classes (`:::…`) for the node above it, read and not drawn; or accessibility text. Mermaid's
/// mindmap grammar has no accessibility text: its `accTitle` and `accDescr` would be nodes, and here they are read for a
/// screen reader, as the other types read them.
enum MindmapParser {
    /// Reads the mindmap whose keyword ends at the cursor. A mindmap without a node is an error, as in Mermaid.
    static func parse(_ cursor: MermaidTextCursor, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> MindmapDiagram {
        var builder = MindmapTreeBuilder(limits: limits)
        try MermaidOutlineReader.read(cursor, grammar: .mindmap, into: &builder)
        guard !builder.diagram.nodes.isEmpty else { throw .invalidSyntax(line: lastLine(of: cursor), problem: .expectedNode) }
        var diagram = builder.diagram
        diagram.seriesColors = MermaidThemeSeriesPalette.mindmap.seriesColors(in: cursor)
        return diagram
    }

    /// The line the text ends on, where a mindmap without a node is missing its root.
    private static func lastLine(of cursor: MermaidTextCursor) -> Int {
        var end = cursor
        end.advance(by: cursor.bytes.count)
        return end.line
    }
}
