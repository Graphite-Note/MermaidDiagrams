/**
 * File: ReferenceAgentFlowDiagramBuilderLinks.swift
 * -------------------------------------------------
 * Layer: Tests
 * Description: 0.7.0's agent flow reader on UTF-16 code units (AgentFlowDiagramBuilderLinks.swift), kept unchanged but for its
 *              names as the reference the reader on bytes is compared with (AgentFlowReadingEquivalenceTests).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import Foundation
@testable import MermaidDiagrams

/// A link as the grammar read it: its arrow, its line, the ranks it spans, its meaning, its text and identifier.
struct ReferenceAgentFlowLinkInfo: Equatable {
    var type: String
    var stroke: String
    var length: Int?
    var semantic: AgentFlowEdgeSemantic?
    var text: ReferenceAgentFlowText?
    var identifier: String?

    /// The link an arrow's text describes (`-->`, `--x`, `-.-`, `---`), and when the arrow is split around its text,
    /// the first half (`--`, `-.`), which only says whether the line is dotted: when the halves disagree the link is
    /// `INVALID`, as in Mermaid.
    init(end: String, start: String? = nil) {
        let arrow = C4Characters.trimmed(end)
        var line = String(arrow.dropLast())
        var type = "arrow_open"
        switch arrow.last {
        case "x": type = "arrow_cross"
        case ">": type = "arrow_point"
        case "-", ".": line = arrow
        default: break
        }
        var stroke = "normal"
        var length = line.utf16.count - 1
        let dots = line.filter { character in character == "." }.count
        if dots > 0 {
            stroke = "dotted"
            length = dots
        }
        if let start, (FoundationTextOnBytes.contains(start, character: MermaidByte.period) ? "dotted" : "normal") != stroke {
            self.type = "INVALID"
            self.stroke = "INVALID"
            return
        }
        self.type = type
        self.stroke = stroke
        self.length = length
        semantic = switch (type, stroke) {
        case ("arrow_point", "normal"): .sequence
        case ("arrow_cross", "normal"): .failure
        case ("arrow_open", "dotted"): .reference
        default: nil
        }
    }
}


extension ReferenceAgentFlowDiagramBuilder {
    /// An edge from each of `starts` to each of `ends`; the link's identifier goes to the one from the last start to the
    /// first end.
    mutating func addLink(from starts: [String], to ends: [String], link: ReferenceAgentFlowLinkInfo) throws(MermaidDiagramReadError) {
        let identifier = link.identifier.map { written in Self.removingFirstCommercialAt(written) }
        for start in starts {
            for end in ends {
                let isNamed = start == starts.last && end == ends.first
                try addSingleLink(from: start, to: end, link: link, identifier: isNamed ? identifier : nil)
            }
        }
    }

    private mutating func addSingleLink(from start: String, to end: String, link: ReferenceAgentFlowLinkInfo,
                                        identifier: String?) throws(MermaidDiagramReadError) {
        let pair = start + "\u{0}" + end
        let existing = pairCounts[pair] ?? 0
        let isUserDefined = identifier.map { written in !written.isEmpty && edgeIndices[written] == nil } ?? false
        var edge = AgentFlowEdge(start: start, end: end,
                                 identifier: isUserDefined ? identifier ?? "" : "L_\(start)_\(end)_\(existing == 0 ? 0 : existing + 1)")
        edge.isUserDefinedIdentifier = isUserDefined
        edge.interpolation = diagram.defaultInterpolation
        if let text = link.text {
            edge.text = Self.unquoted(C4Characters.trimmed(text.text))
            edge.labelType = text.type
        }
        edge.type = link.type
        edge.stroke = link.stroke
        edge.length = link.length.map { length in min(length, 10) }
        edge.semantic = link.semantic
        guard diagram.edges.count < limits.maximumEdgeCount else { throw .tooManyEdges(limit: limits.maximumEdgeCount) }
        if edgeIndices[edge.identifier] == nil { edgeIndices[edge.identifier] = diagram.edges.count }
        diagram.edges.append(edge)
        pairCounts[pair] = existing + 1
    }

    /// `linkStyle … interpolate`: the default curve, or the curve of each edge named by index.
    mutating func updateLinkInterpolation(positions: [String], interpolation: String, line: Int) throws(MermaidDiagramReadError) {
        for position in positions {
            if position == "default" { diagram.defaultInterpolation = interpolation } else { diagram.edges[try edgeIndex(at: position, line: line)].interpolation = interpolation }
        }
    }

    /// `linkStyle … styles`: the default edge style, or the style of each edge named by index, given `fill:none` when it
    /// sets no fill.
    mutating func updateLink(positions: [String], styles: [String], line: Int) throws(MermaidDiagramReadError) {
        for position in positions {
            if position == "default" {
                diagram.defaultEdgeStyle = styles
                continue
            }
            let index = try edgeIndex(at: position, line: line)
            var kept = styles
            if !kept.isEmpty, !kept.contains(where: { style in style.hasPrefix("fill") }) { kept.append("fill:none") }
            diagram.edges[index].style = kept
        }
    }

    /// The edge at an index written in the text; Mermaid refuses one past the edges.
    private func edgeIndex(at position: String, line: Int) throws(MermaidDiagramReadError) -> Int {
        guard let index = Int(position), index >= 0, index < diagram.edges.count else {
            throw .invalidSyntax(line: line, problem: .agentFlow(.linkStyleIndexOutOfBounds(index: position, edgeCount: diagram.edges.count)))
        }
        return index
    }

    /// `classDef a,b styles`: escaped commas kept, the others separating styles; a style that sets a color is also a
    /// style of the text, its `fill` read as `bgFill`.
    mutating func addClass(_ identifiers: String, styles: [String]) {
        let joined = styles.joined(separator: ",").replacingOccurrences(of: "\\,", with: "\u{0}")
        let split = joined.replacingOccurrences(of: ",", with: ";").replacingOccurrences(of: "\u{0}", with: ",")
            .split(separator: ";", omittingEmptySubsequences: false).map(String.init)
        for identifier in identifiers.split(separator: ",", omittingEmptySubsequences: false).map(String.init) {
            let index = classIndices[identifier] ?? diagram.classDefinitions.count
            if index == diagram.classDefinitions.count {
                classIndices[identifier] = index
                diagram.classDefinitions.append(AgentFlowClassDefinition(identifier: identifier))
            }
            for style in split {
                if style.contains("color") {
                    diagram.classDefinitions[index].textStyles.append(Self.replacingFirst("fill", with: "bgFill", in: style))
                }
                diagram.classDefinitions[index].styles.append(style)
            }
        }
    }

    /// `class a,b name` and `a:::name`: the class on each node, edge and flow of those identifiers.
    mutating func setClass(_ identifiers: String, className: String) {
        for identifier in identifiers.split(separator: ",", omittingEmptySubsequences: false).map(String.init) {
            if let vertex = vertexIndices[identifier] { diagram.vertices[vertex].classes.append(className) }
            if let edge = edgeIndices[identifier] { diagram.edges[edge].classes.append(className) }
            if let flow = flowIndices[identifier] { diagram.flows[flow].classes.append(className) }
        }
    }

    mutating func setTooltip(_ identifiers: String, tooltip: String) {
        for identifier in identifiers.split(separator: ",", omittingEmptySubsequences: false) { tooltips[String(identifier)] = tooltip }
    }

    /// `click a href "url"`: the link kept as written (the scene draws no links), the node marked clickable.
    mutating func setLink(_ identifiers: String, url: String, target: String? = nil) {
        let link = C4Characters.trimmed(url)
        for identifier in identifiers.split(separator: ",", omittingEmptySubsequences: false) {
            guard let vertex = vertexIndices[String(identifier)] else { continue }
            diagram.vertices[vertex].link = link.isEmpty ? nil : link
            diagram.vertices[vertex].linkTarget = target
        }
        setClass(identifiers, className: "clickable")
    }

    mutating func setDirection(_ written: String) {
        var direction = C4Characters.trimmed(written)
        if FoundationTextOnBytes.contains(direction, character: MermaidByte.lessThan) { direction = "RL" }
        if FoundationTextOnBytes.contains(direction, character: UInt8(ascii: "^")) { direction = "BT" }
        if FoundationTextOnBytes.contains(direction, character: MermaidByte.greaterThan) { direction = "LR" }
        if FoundationTextOnBytes.contains(direction, character: UInt8(ascii: "v")) { direction = "TB" }
        if direction == "TD" { direction = "TB" }
        diagram.directionKeyword = direction
    }

    static func removingFirstCommercialAt(_ text: String) -> String {
        replacingFirst("@", with: "", in: text)
    }

    static func replacingFirst(_ target: String, with replacement: String, in text: String) -> String {
        guard let range = text.range(of: target) else { return text }
        return text.replacingCharacters(in: range, with: replacement)
    }
}
