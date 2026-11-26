/**
 * File: AgentFlowDiagramBuilderMappings.swift
 * -------------------------------------------
 * Layer: Core
 * Description: Where each statement of an agent flow sits in its text, as Pele's db.ts maps them, on names and ranges,
 *              and the accessibility texts.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

extension AgentFlowDiagramBuilder {
    private func position(_ span: AgentFlowSourceSpan?) -> (startLine: Int32, startColumn: Int32, endLine: Int32, endColumn: Int32) {
        let startLine = span?.firstLine ?? 0
        let startColumn = span?.firstColumn ?? 0
        return (Int32(truncatingIfNeeded: startLine + lineOffset), Int32(truncatingIfNeeded: startColumn),
                Int32(truncatingIfNeeded: (span?.lastLine ?? startLine) + lineOffset), Int32(truncatingIfNeeded: span?.lastColumn ?? startColumn))
    }

    @discardableResult
    private mutating func pushMapping(_ identifier: MermaidTextRange, name: Int32, kind: AgentFlowElementMapping.Kind,
                                      position: (startLine: Int32, startColumn: Int32, endLine: Int32, endColumn: Int32)) -> Int {
        model.mappings.append(AgentFlowMappingRecord(identifier: identifier, name: name, kind: kind, startLine: position.startLine,
                                                     startColumn: position.startColumn, endLine: position.endLine, endColumn: position.endColumn))
        return model.mappings.count - 1
    }

    /// A node named; a bare reference (no brackets) becomes an attachment when metadata follows it.
    mutating func addVertexMapping(_ identifier: AgentFlowNamedText, hasShape: Bool, span: AgentFlowSourceSpan) {
        guard !identifier.range.isEmpty else { return }
        let index = pushMapping(identifier.range, name: identifier.name, kind: .vertex, position: position(span))
        model.mappings[index].isBare = !hasShape
        model.mappings[index].previousVertexMapping = names[identifier.name].lastVertexMapping
        names[identifier.name].lastVertexMapping = Int32(index)
    }

    /// Widens a node's last mapping over the metadata block after it.
    mutating func extendVertexMapping(_ identifier: AgentFlowNamedText, span: AgentFlowSourceSpan) {
        guard !identifier.range.isEmpty else { return }
        let end = position(span)
        let last = names[identifier.name].lastVertexMapping
        guard last >= 0 else {
            pushMapping(identifier.range, name: identifier.name, kind: .attachment, position: end)
            return
        }
        let index = Int(last)
        if model.mappings[index].isBare {
            model.mappings[index].isBare = false
            model.mappings[index].kind = .attachment
            names[identifier.name].lastVertexMapping = model.mappings[index].previousVertexMapping
        }
        let current = model.mappings[index]
        if end.endLine > current.endLine || (end.endLine == current.endLine && end.endColumn > current.endColumn) {
            model.mappings[index].endLine = end.endLine
            model.mappings[index].endColumn = end.endColumn
        }
    }

    /// An edge statement, by the identifiers after its link joined by `>`.
    mutating func addEdgeMapping(to targets: ScratchSpan<AgentFlowNamedText>, span: AgentFlowSourceSpan) {
        var namedCount = 0
        var only = MermaidTextRange.empty
        for target in targets where !target.range.isEmpty {
            namedCount += 1
            only = target.range
        }
        let identifier: MermaidTextRange
        switch namedCount {
        case 0: identifier = constant(.edge)
        case 1: identifier = only
        default:
            let start = model.text.bytes.count
            for target in targets where !target.range.isEmpty {
                if model.text.bytes.count > start { model.text.bytes.append(UInt8(ascii: ">")) }
                model.text.appendCopy(of: target.range)
            }
            identifier = MermaidTextRange(start: start, end: model.text.bytes.count)
        }
        pushMapping(identifier, name: -1, kind: .edge, position: position(span))
    }

    /// A flow or a connector, from its keyword to its `end` or its separator.
    mutating func addBlockMapping(_ identifier: MermaidTextRange, kind: AgentFlowElementMapping.Kind, start: AgentFlowSourceSpan, end: AgentFlowSourceSpan) {
        guard !identifier.isEmpty else { return }
        let first = position(start)
        let last = position(end)
        pushMapping(identifier, name: -1, kind: kind, position: (first.startLine, first.startColumn, last.endLine, last.endColumn))
    }

    // MARK: - Accessibility

    mutating func setAccessibility(_ value: MermaidTextRange, isTitle: Bool) {
        if isTitle {
            model.accessibilityTitle = value
        } else {
            model.accessibilityDescription = replacingRunsAfterLineFeeds(value)
        }
    }

    /// The text with each line feed and the white space after it made one line feed (`/\n\s+/g` to `\n`).
    private mutating func replacingRunsAfterLineFeeds(_ value: MermaidTextRange) -> MermaidTextRange {
        var index = value.lowerBound
        var hasRun = false
        while index < value.upperBound, !hasRun {
            hasRun = model.text.bytes[index] == MermaidByte.newline && index + 1 < value.upperBound
                && JavaScriptWhitespace.length(in: model.text.bytes, at: index + 1) > 0
            index += 1
        }
        guard hasRun else { return value }
        let start = model.text.bytes.count
        index = value.lowerBound
        while index < value.upperBound {
            let byte = model.text.bytes[index]
            model.text.bytes.append(byte)
            index += 1
            guard byte == MermaidByte.newline else { continue }
            while index < value.upperBound, case let length = JavaScriptWhitespace.length(in: model.text.bytes, at: index), length > 0 { index += length }
        }
        return MermaidTextRange(start: start, end: model.text.bytes.count)
    }
}
