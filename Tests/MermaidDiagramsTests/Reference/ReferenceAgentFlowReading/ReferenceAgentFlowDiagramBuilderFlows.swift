/**
 * File: ReferenceAgentFlowDiagramBuilderFlows.swift
 * -------------------------------------------------
 * Layer: Tests
 * Description: 0.7.0's agent flow reader on UTF-16 code units (AgentFlowDiagramBuilderFlows.swift), kept unchanged but for its
 *              names as the reference the reader on bytes is compared with (AgentFlowReadingEquivalenceTests).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

@testable import MermaidDiagrams

/// What a block's statements give it: a separator or a text, the identifiers a statement names, or a direction.
enum ReferenceAgentFlowDocumentItem: Equatable {
    case text(String)
    case identifiers([String])
    case direction(String)
}

extension ReferenceAgentFlowDiagramBuilder {
    /// A `flow … end` block, Pele's `addSubGraph`: its members are the identifiers its statements name, once each, but
    /// never itself, a node in a `global` block or a node another flow already holds. A flow written again adds its
    /// members to the first, whose title and direction it replaces when it gives them.
    mutating func addFlow(identifier written: ReferenceAgentFlowText?, items: [ReferenceAgentFlowDocumentItem], title: ReferenceAgentFlowText?) throws(MermaidDiagramReadError) -> String {
        var seen: Set<String> = []
        var named: [String] = []
        seen.reserveCapacity(items.count)
        named.reserveCapacity(items.count)
        var direction: String?
        for item in items {
            switch item {
            case .text(let text): if !C4Characters.trimmed(text).isEmpty, seen.insert(text).inserted { named.append(text) }
            case .identifiers(let identifiers):
                for text in identifiers where !C4Characters.trimmed(text).isEmpty && seen.insert(text).inserted { named.append(text) }
            case .direction(let value): direction = value
            }
        }
        let identifier = written.map { written in C4Characters.trimmed(written.text) } ?? "subGraph\(flowCount)"
        flowCount += 1
        let nodes = named.filter { node in node != identifier && !globalNodes.contains(node) && !members.contains(node) }
        members.formUnion(nodes)
        let titleText = C4Characters.trimmed(title?.text ?? "")
        if let existing = flowIndices[identifier] {
            diagram.flows[existing].nodeIdentifiers += nodes
            if !titleText.isEmpty { diagram.flows[existing].title = titleText }
            if let direction, !direction.isEmpty { diagram.flows[existing].directionKeyword = direction }
            return identifier
        }
        try checkNodeLimit()
        flowIndices[identifier] = diagram.flows.count
        diagram.flows.append(AgentFlowFlow(identifier: identifier, nodeIdentifiers: nodes, title: titleText, directionKeyword: direction,
                                           labelType: AgentFlowLabelType(named: title?.type.rawValue)))
        return identifier
    }

    /// A `global … end` block: every node named in it stays out of the flows that name it.
    mutating func addGlobal(_ items: [ReferenceAgentFlowDocumentItem]) {
        var released = false
        func add(_ item: String) {
            let identifier = C4Characters.trimmed(item)
            guard !identifier.isEmpty else { return }
            globalNodes.insert(identifier)
            if members.remove(identifier) != nil { released = true }
        }
        for item in items {
            switch item {
            case .text(let text): add(text)
            case .identifiers(let identifiers): identifiers.forEach(add)
            case .direction: break
            }
        }
        guard released else { return }
        for index in diagram.flows.indices {
            diagram.flows[index].nodeIdentifiers.removeAll { node in globalNodes.contains(node) }
        }
    }

    /// `connector id["Title"]`: a node marked as a connector, titled by its title or else its identifier; written again,
    /// its title replaced when it gives one.
    mutating func addConnector(_ written: ReferenceAgentFlowText?, title: ReferenceAgentFlowText?) throws(MermaidDiagramReadError) -> String {
        let identifier = C4Characters.trimmed(written?.text ?? "")
        guard !identifier.isEmpty else { return "" }
        let titleText = C4Characters.trimmed(title?.text ?? "")
        if connectorIdentifiers.contains(identifier), let index = vertexIndices[identifier] {
            if !titleText.isEmpty { diagram.vertices[index].text = titleText }
            return identifier
        }
        var connector = AgentFlowVertex(identifier: identifier)
        connector.isConnector = true
        connector.text = titleText.isEmpty ? identifier : titleText
        connectorIdentifiers.insert(identifier)
        if !diagram.connectorIdentifiers.contains(identifier) { diagram.connectorIdentifiers.append(identifier) }
        if let index = vertexIndices[identifier] {
            // Mermaid's map keeps a node's first place when it is set again.
            diagram.vertices[index] = connector
        } else {
            try checkNodeLimit()
            vertexIndices[identifier] = diagram.vertices.count
            diagram.vertices.append(connector)
        }
        return identifier
    }

    // MARK: - Where statements sit

    /// Leaves a value as it is: accessing a dictionary's entry through it with a default stores the default when the
    /// entry is missing.
    private static func keep(_ value: inout Int) {}

    private func position(_ span: ReferenceAgentFlowSourceSpan?) -> AgentFlowElementPosition {
        let startLine = span?.firstLine ?? 0
        let startColumn = span?.firstColumn ?? 0
        return AgentFlowElementPosition(startLine: startLine + lineOffset, startColumn: startColumn,
                                        endLine: (span?.lastLine ?? startLine) + lineOffset, endColumn: span?.lastColumn ?? startColumn)
    }

    @discardableResult
    private mutating func pushMapping(_ identifier: String, kind: AgentFlowElementMapping.Kind, position: AgentFlowElementPosition) -> Int {
        diagram.mappings.append(AgentFlowElementMapping(identifier: identifier, kind: kind, position: position))
        isBareMapping.append(false)
        // Looked up once: the default is stored only when the identifier has no mapping yet, and a first one is kept.
        Self.keep(&firstMappings[identifier, default: diagram.mappings.count - 1])
        return diagram.mappings.count - 1
    }

    /// A node named; a bare reference (no brackets) becomes an attachment when metadata follows it.
    mutating func addVertexMapping(_ identifier: String, hasShape: Bool, span: ReferenceAgentFlowSourceSpan) {
        guard !identifier.isEmpty else { return }
        let index = pushMapping(identifier, kind: .vertex, position: position(span))
        if !hasShape { isBareMapping[index] = true }
    }

    /// Widens a node's last mapping over the metadata block after it.
    mutating func extendVertexMapping(_ identifier: String, span: ReferenceAgentFlowSourceSpan) {
        guard !identifier.isEmpty else { return }
        let end = position(span)
        guard let index = diagram.mappings.lastIndex(where: { mapping in mapping.kind == .vertex && mapping.identifier == identifier }) else {
            pushMapping(identifier, kind: .attachment, position: end)
            return
        }
        if isBareMapping[index] {
            isBareMapping[index] = false
            diagram.mappings[index].kind = .attachment
        }
        let current = diagram.mappings[index].position
        if end.endLine > current.endLine || (end.endLine == current.endLine && end.endColumn > current.endColumn) {
            diagram.mappings[index].position.endLine = end.endLine
            diagram.mappings[index].position.endColumn = end.endColumn
        }
    }

    /// An edge statement, by the identifiers after its link joined by `>`.
    mutating func addEdgeMapping(to targets: [String], span: ReferenceAgentFlowSourceSpan) {
        let named = targets.filter { target in !target.isEmpty }
        pushMapping(named.isEmpty ? "edge" : named.joined(separator: ">"), kind: .edge, position: position(span))
    }

    /// A flow or a connector, from its keyword to its `end` or its separator.
    mutating func addBlockMapping(_ identifier: String, kind: AgentFlowElementMapping.Kind, start: ReferenceAgentFlowSourceSpan, end: ReferenceAgentFlowSourceSpan) {
        guard !identifier.isEmpty else { return }
        let first = position(start)
        let last = position(end)
        pushMapping(identifier, kind: kind, position: AgentFlowElementPosition(startLine: first.startLine, startColumn: first.startColumn,
                                                                                 endLine: last.endLine, endColumn: last.endColumn))
    }
}
