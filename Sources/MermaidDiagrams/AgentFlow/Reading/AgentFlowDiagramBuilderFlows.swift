/**
 * File: AgentFlowDiagramBuilderFlows.swift
 * ----------------------------------------
 * Layer: Core
 * Description: An agent flow's flows, global blocks and connectors as Pele's db.ts records them, on names and ranges.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 26/11/2026
 */

/// What a block's statements give it: a name (a node a statement names, a flow closed, a connector, an accessibility
/// text), or a direction.
struct AgentFlowDocumentItem {
    var isDirection: Bool
    var text: AgentFlowNamedText
}

extension AgentFlowDiagramBuilder {
    /// A `flow … end` block, Pele's `addSubGraph`: its members are the names `items` give, once each, but never itself,
    /// a node in a `global` block or a node another flow already holds. A flow written again adds its members to the
    /// first, whose title and direction it replaces when it gives them. Returns its identifier.
    mutating func addFlow(identifier written: AgentFlowText?, items: ScratchSpan<AgentFlowDocumentItem>,
                          title: AgentFlowText?) throws(MermaidDiagramReadError) -> AgentFlowNamedText {
        let identifierRange = written.map { written in model.text.trimmed(written.range) } ?? madeFlowIdentifier()
        let identifier = AgentFlowNamedText(range: identifierRange, name: name(of: identifierRange))
        flowCount += 1
        let titleText = model.text.trimmed(title?.range ?? .empty)
        var flow = names[identifier.name].flow
        let isNew = flow < 0
        if isNew {
            try checkNodeLimit()
            flow = Int32(model.flows.count)
        }
        // Each name is gathered once: its role keeps the block it was last gathered for, numbered by the blocks closed.
        let stamp = Int32(truncatingIfNeeded: flowCount)
        var direction: MermaidTextRange?
        for item in items {
            if item.isDirection {
                direction = item.text.range
                continue
            }
            let name = item.text.name
            guard !model.text.trimmed(item.text.range).isEmpty, names[name].gatheredInFlow != stamp else { continue }
            names[name].gatheredInFlow = stamp
            guard name != identifier.name, !names[name].isGlobal, !names[name].isMember else { continue }
            names[name].isMember = true
            model.members.append(AgentFlowMember(flow: flow, name: name, identifier: item.text.range))
        }
        if !isNew {
            if !titleText.isEmpty { model.flows[Int(flow)].title = titleText }
            if let direction, !direction.isEmpty { model.flows[Int(flow)].directionKeyword = direction }
            return identifier
        }
        names[identifier.name].flow = flow
        model.flows.append(AgentFlowFlowRecord(identifier: identifierRange, name: identifier.name, title: titleText, directionKeyword: direction,
                                               labelType: title?.type ?? .markdown))
        return identifier
    }

    /// `subGraphN`, Mermaid's identifier for a flow its text does not name.
    private mutating func madeFlowIdentifier() -> MermaidTextRange {
        let start = model.text.bytes.count
        model.text.bytes.append(contentsOf: Self.subgraphWord)
        AgentFlowPairCounts.appendDecimal(flowCount, to: &model.text.bytes)
        return MermaidTextRange(start: start, end: model.text.bytes.count)
    }

    private static let subgraphWord = Array("subGraph".utf8)

    /// A `global … end` block: every node named in it stays out of the flows that name it. A flow's member that becomes
    /// global is dropped from it when the model is read (`AgentFlowGraphBuilding`), as 0.7.0 dropped it here.
    mutating func addGlobal(_ items: ScratchSpan<AgentFlowDocumentItem>) {
        for item in items where !item.isDirection {
            let trimmed = model.text.trimmed(item.text.range)
            guard !trimmed.isEmpty else { continue }
            let name = trimmed == item.text.range ? item.text.name : name(of: trimmed)
            names[name].isGlobal = true
            names[name].isMember = false
        }
    }

    /// `connector id["Title"]`: a node marked as a connector, titled by its title or else its identifier; written again,
    /// its title replaced when it gives one. Returns its identifier, empty for none.
    mutating func addConnector(_ written: AgentFlowText?, title: AgentFlowText?) throws(MermaidDiagramReadError) -> AgentFlowNamedText {
        let identifier = model.text.trimmed(written?.range ?? .empty)
        guard !identifier.isEmpty else { return AgentFlowNamedText(range: identifier, name: -1) }
        let name = name(of: identifier)
        let titleText = model.text.trimmed(title?.range ?? .empty)
        let role = names[name]
        if role.isConnector, role.vertex >= 0 {
            if !titleText.isEmpty { model.vertices[Int(role.vertex)].text = titleText }
            return AgentFlowNamedText(range: identifier, name: name)
        }
        var connector = AgentFlowVertexRecord(identifier: identifier, name: name, firstAttribute: Int32(model.vertexAttributes.count))
        connector.isConnector = true
        connector.text = titleText.isEmpty ? identifier : titleText
        connector.hasText = true
        names[name].isConnector = true
        model.connectorIdentifiers.append(identifier)
        if role.vertex >= 0 {
            // Mermaid's map keeps a node's first place when it is set again.
            model.vertices[Int(role.vertex)] = connector
        } else {
            try checkNodeLimit()
            names[name].vertex = Int32(model.vertices.count)
            model.vertices.append(connector)
        }
        return AgentFlowNamedText(range: identifier, name: name)
    }
}
