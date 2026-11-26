/**
 * File: AgentFlowDiagramBuilderLinks.swift
 * ----------------------------------------
 * Layer: Core
 * Description: An agent flow's edges and link styles as Pele's db.ts records them, on names and ranges: each edge's
 *              identifier made from its ends and how many edges joined them before, counted by pair.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 26/11/2026
 */

/// A link as the grammar read it: its arrow, its line, the ranks it spans, its meaning, its text and identifier.
struct AgentFlowLinkInfo {
    var arrow = AgentFlowArrow.open
    var stroke = AgentFlowStroke.normal
    var length: Int32 = -1
    var semantic: AgentFlowEdgeSemantic?
    var text: AgentFlowText?
    var identifier: MermaidTextRange?

    /// The link an arrow's text describes (`-->`, `--x`, `-.-`, `---`), and when the arrow is split around its text,
    /// the first half (`--`, `-.`), which only says whether the line is dotted: when the halves disagree the link is
    /// `INVALID`, as in Mermaid. An arrow is ASCII once trimmed, so its characters are its bytes.
    init(end: MermaidTextRange, start: MermaidTextRange? = nil, in text: AgentFlowTextBytes) {
        let arrow = text.trimmed(end)
        let bytes = text.bytes
        var lineEnd = arrow.upperBound - 1
        var type = AgentFlowArrow.open
        switch arrow.isEmpty ? 0 : bytes[arrow.upperBound - 1] {
        case UInt8(ascii: "x"): type = .cross
        case UInt8(ascii: ">"): type = .point
        case UInt8(ascii: "-"), UInt8(ascii: "."): lineEnd = arrow.upperBound
        default: break
        }
        var stroke = AgentFlowStroke.normal
        var length = Int32(max(lineEnd, arrow.lowerBound) - arrow.lowerBound) - 1
        let dots = bytes[arrow.lowerBound..<max(lineEnd, arrow.lowerBound)].reduce(0) { count, byte in byte == MermaidByte.period ? count + 1 : count }
        if dots > 0 {
            stroke = .dotted
            length = Int32(dots)
        }
        if let start, (text.contains(start, byte: MermaidByte.period) ? AgentFlowStroke.dotted : .normal) != stroke {
            self.arrow = .invalid
            self.stroke = .invalid
            return
        }
        self.arrow = type
        self.stroke = stroke
        self.length = length
        semantic = switch (type, stroke) {
        case (.point, .normal): .sequence
        case (.cross, .normal): .failure
        case (.open, .dotted): .reference
        default: nil
        }
    }
}

extension AgentFlowDiagramBuilder {
    /// An edge from each of the nodes `starts` to each of `ends`, both runs of `nodes`; the link's identifier goes to the
    /// one from the last start to the first end, compared by name as 0.7.0 compared Strings.
    mutating func addLink(from starts: Range<Int>, to ends: Range<Int>, in nodes: ScratchSpan<AgentFlowNamedText>,
                          link: AgentFlowLinkInfo) throws(MermaidDiagramReadError) {
        let identifier = link.identifier.map { written in removingFirstCommercialAt(written) }
        let lastStart = nodes[starts.upperBound - 1].name
        let firstEnd = nodes[ends.lowerBound].name
        for start in starts {
            for end in ends {
                let isNamed = nodes[start].name == lastStart && nodes[end].name == firstEnd
                try addSingleLink(from: nodes[start], to: nodes[end], link: link, identifier: isNamed ? identifier : nil)
            }
        }
    }

    private mutating func addSingleLink(from start: AgentFlowNamedText, to end: AgentFlowNamedText, link: AgentFlowLinkInfo,
                                        identifier: MermaidTextRange?) throws(MermaidDiagramReadError) {
        let existing = pairCounts.count(start.name, end.name)
        var userName: Int32 = -1
        if let identifier, !identifier.isEmpty {
            let name = name(of: identifier)
            if edgeIndex(of: name, identifier: identifier) < 0 { userName = name }
        }
        let edgeIdentifier: MermaidTextRange
        if let identifier, userName >= 0 { edgeIdentifier = identifier } else { edgeIdentifier = madeIdentifier(start.range, end.range, number: existing == 0 ? 0 : existing + 1) }
        var edge = AgentFlowEdgeRecord(start: start.range, end: end.range, startName: start.name, endName: end.name, identifier: edgeIdentifier,
                                       identifierName: userName, isUserDefinedIdentifier: userName >= 0, arrow: link.arrow, stroke: link.stroke,
                                       semantic: link.semantic, length: link.length < 0 ? -1 : min(link.length, 10))
        edge.interpolation = model.defaultInterpolation
        if let text = link.text {
            edge.text = model.text.unquoted(model.text.trimmed(text.range))
            edge.labelType = text.type
        }
        guard model.edges.count < limits.maximumEdgeCount else { throw .tooManyEdges(limit: limits.maximumEdgeCount) }
        if userName >= 0 { names[userName].edge = Int32(model.edges.count) }
        model.edges.append(edge)
        pairCounts.set(start.name, end.name, to: existing + 1)
    }

    /// `L_start_end_number`, Mermaid's identifier for an edge its text does not name.
    private mutating func madeIdentifier(_ start: MermaidTextRange, _ end: MermaidTextRange, number: Int) -> MermaidTextRange {
        let first = model.text.bytes.count
        model.text.bytes.append(76)
        model.text.bytes.append(MermaidByte.underscore)
        model.text.appendCopy(of: start)
        model.text.bytes.append(MermaidByte.underscore)
        model.text.appendCopy(of: end)
        model.text.bytes.append(MermaidByte.underscore)
        AgentFlowPairCounts.appendDecimal(number, to: &model.text.bytes)
        return MermaidTextRange(start: first, end: model.text.bytes.count)
    }

    /// The identifier without its first `@`, as 0.7.0's Foundation search removed it.
    private mutating func removingFirstCommercialAt(_ written: MermaidTextRange) -> MermaidTextRange {
        guard model.text.isASCII(written) else {
            let text = model.text.string(written)
            return model.text.append(Self.replacingFirst("@", with: "", in: text).utf8)
        }
        guard let at = model.text.bytes[written.lowerBound..<written.upperBound].firstIndex(of: UInt8(ascii: "@")) else { return written }
        if at == written.upperBound - 1 { return MermaidTextRange(start: written.lowerBound, end: at) }
        if at == written.lowerBound { return MermaidTextRange(start: at + 1, end: written.upperBound) }
        let start = model.text.bytes.count
        model.text.appendCopy(of: MermaidTextRange(start: written.lowerBound, end: at))
        model.text.appendCopy(of: MermaidTextRange(start: at + 1, end: written.upperBound))
        return MermaidTextRange(start: start, end: model.text.bytes.count)
    }

    // MARK: - Link styles

    /// `linkStyle … interpolate`: the default curve, or the curve of each edge named by index.
    mutating func updateLinkInterpolation(positions: [MermaidTextRange], interpolation: MermaidTextRange, line: Int) throws(MermaidDiagramReadError) {
        for position in positions {
            if isDefaultPosition(position) {
                model.defaultInterpolation = interpolation
            } else {
                model.edges[try edgeIndex(at: position, line: line)].interpolation = interpolation
            }
        }
    }

    /// `linkStyle … styles`: the default edge style, or the style of each edge named by index, given `fill:none` when it
    /// sets no fill.
    mutating func updateLink(positions: [MermaidTextRange], styles: [MermaidTextRange], line: Int) throws(MermaidDiagramReadError) {
        for position in positions {
            if isDefaultPosition(position) {
                model.defaultEdgeStyle = styleRun(styles)
                continue
            }
            let index = try edgeIndex(at: position, line: line)
            var kept = styles
            if !kept.isEmpty, !kept.contains(where: hasFillPrefix) { kept.append(constant(.fillNone)) }
            model.edges[index].style = styleRun(kept)
        }
    }

    private func isDefaultPosition(_ position: MermaidTextRange) -> Bool {
        model.text.equals(position, AgentFlowConstantText.defaultClass.bytes)
    }

    /// Whether a style starts with `fill`, as 0.7.0's `hasPrefix` found it.
    private func hasFillPrefix(_ style: MermaidTextRange) -> Bool {
        guard model.text.isASCII(style) else { return model.text.string(style).hasPrefix("fill") }
        return style.count >= 4 && model.text.bytes[style.lowerBound..<(style.lowerBound + 4)].elementsEqual(Self.fillWord)
    }

    static let fillWord = Array("fill".utf8)

    /// The styles as a run of the model's style ranges.
    private mutating func styleRun(_ styles: [MermaidTextRange]) -> Range<Int32> {
        let start = Int32(model.styleRanges.count)
        model.styleRanges += styles
        return start..<Int32(model.styleRanges.count)
    }

    /// The edge at an index written in the text; Mermaid refuses one past the edges.
    private func edgeIndex(at position: MermaidTextRange, line: Int) throws(MermaidDiagramReadError) -> Int {
        var index = 0
        var isNumber = !position.isEmpty
        for byte in model.text.bytes[position.lowerBound..<position.upperBound] {
            guard byte >= 48, byte <= 57, index <= (Int.max - 9) / 10 else {
                isNumber = false
                break
            }
            index = index * 10 + Int(byte - 48)
        }
        guard isNumber, index < model.edges.count else {
            throw .invalidSyntax(line: line, problem: .agentFlow(.linkStyleIndexOutOfBounds(index: model.text.string(position), edgeCount: model.edges.count)))
        }
        return index
    }
}
