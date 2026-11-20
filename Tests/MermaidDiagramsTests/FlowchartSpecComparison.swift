/**
 * File: FlowchartSpecComparison.swift
 * -----------------------------------
 * Layer: Tests
 * Description: Reads a text of Mermaid's flowchart specs with the package and compares the flowchart with what Pele's
 *              flowchart database made of it: refused or read, the direction, the nodes, the edges and the groups.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import Foundation
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

/// How the package's reading of one spec text differs from Pele's, each a short word: `refused` (one refused it, the
/// other read it), `direction`, `nodes` (the identifiers, in the order first named), `node texts`, `edges` (their ends),
/// `edge marks`, `edge strokes`, `edge lengths`, `edge texts`, `groups` (their identifiers and what is directly inside).
enum FlowchartSpecComparison {
    static func differences(_ pele: PeleParsedFlowchart) -> [String] {
        let diagram: FlowchartDiagram
        do {
            // Pele's spec adapter hands every text to the flowchart's parser; the package reads `swimlane-beta` as a
            // swimlane diagram, which holds a flowchart.
            switch try MermaidDiagramReader.read(pele.source, limits: .standard) {
            case .flowchart(let read), .swimlane(let read): diagram = read
            default: return pele.error == nil ? ["refused"] : []
            }
        } catch {
            return pele.error == nil ? ["refused"] : []
        }
        guard pele.error == nil else { return ["refused"] }
        var found: [String] = []
        if diagram.direction != direction(pele.direction) { found.append("direction") }
        let identifiers = diagram.nodes.map(\.identifier)
        if identifiers != (pele.nodes ?? []).map(\.id) { found.append("nodes") }
        let peleTexts = Dictionary((pele.nodes ?? []).map { node in (node.id, text(node.text)) }, uniquingKeysWith: { first, _ in first })
        if diagram.nodes.contains(where: { node in peleTexts[node.identifier].map { $0 != text(node.label) } ?? false }) {
            found.append("node texts")
        }
        found += edgeDifferences(diagram, pele.edges ?? [])
        if Set(groups(diagram)) != Set((pele.subgraphs ?? []).map { group in Group(identifier: group.id, members: Set(group.nodes)) }) {
            found.append("groups")
        }
        return found
    }

    private static func edgeDifferences(_ diagram: FlowchartDiagram, _ peleEdges: [PeleParsedFlowchart.Edge]) -> [String] {
        let mine = diagram.edges
        let ends = mine.map { edge in [diagram.nodes[edge.sourceIndex].identifier, diagram.nodes[edge.targetIndex].identifier] }
        guard ends == peleEdges.map({ edge in [edge.start, edge.end] }) else { return ["edges"] }
        var found: [String] = []
        if zip(mine, peleEdges).contains(where: { edge, pele in marks(of: edge) != pele.type }) { found.append("edge marks") }
        if zip(mine, peleEdges).contains(where: { edge, pele in stroke(of: edge) != pele.stroke }) { found.append("edge strokes") }
        if zip(mine, peleEdges).contains(where: { edge, pele in edge.minimumRankSpan != pele.length }) { found.append("edge lengths") }
        if zip(mine, peleEdges).contains(where: { edge, pele in text(edge.label ?? DiagramLabel("")) != text(pele.text) }) {
            found.append("edge texts")
        }
        return found
    }

    /// A group's identifier and what is directly inside it. Pele lists groups as they end, the package each before the
    /// groups inside it, so the groups are compared as a set.
    private struct Group: Hashable {
        let identifier: String
        let members: Set<String>
    }

    private static func groups(_ diagram: FlowchartDiagram) -> [Group] {
        diagram.subgraphs.map { group in
            Group(identifier: group.identifier,
                  members: Set(group.nodeIndices.map { index in diagram.nodes[index].identifier }
                    + group.childSubgraphIndices.map { index in diagram.subgraphs[index].identifier }))
        }
    }

    /// Pele's direction as written (`TB`, `TD`, `BT`, `LR`, `RL`, `>`, `<`, `^`, `v`), top to bottom when none is.
    private static func direction(_ written: String?) -> FlowchartDirection {
        guard let written else { return .topToBottom }
        return FlowchartDirection(keyword: written) ?? .topToBottom
    }

    /// Pele's edge type: the target's mark, `double_` when the source has one too.
    private static func marks(of edge: FlowchartEdge) -> String {
        func name(_ arrowhead: FlowchartArrowhead) -> String {
            switch arrowhead {
            case .none: "arrow_open"
            case .arrow: "arrow_point"
            case .circle: "arrow_circle"
            case .cross: "arrow_cross"
            }
        }
        return (edge.sourceArrowhead == .none ? "" : "double_") + name(edge.targetArrowhead)
    }

    private static func stroke(of edge: FlowchartEdge) -> String {
        switch edge.stroke {
        case .solid: "normal"
        case .dotted: "dotted"
        case .thick: "thick"
        case .invisible: "invisible"
        }
    }

    /// A label's lines joined by line feeds.
    private static func text(_ label: DiagramLabel) -> String {
        label.lines.joined(separator: "\n")
    }

    /// Pele's text as it is drawn: its lines broken at `<br>` and trimmed, a Markdown string without its backticks and
    /// its bold and italic marks, as the package's label holds it.
    private static func text(_ peleText: String) -> String {
        var written = peleText
        if written.count >= 2, written.hasPrefix("`"), written.hasSuffix("`") {
            written = String(written.dropFirst().dropLast()).replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "*", with: "")
        }
        return written.replacingOccurrences(of: "<br/>", with: "<br>").replacingOccurrences(of: "<br />", with: "<br>")
            .components(separatedBy: "<br>").map { line in line.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
    }
}
