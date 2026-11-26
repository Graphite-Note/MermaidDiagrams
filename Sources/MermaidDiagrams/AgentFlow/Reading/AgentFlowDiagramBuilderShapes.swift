/**
 * File: AgentFlowDiagramBuilderShapes.swift
 * -----------------------------------------
 * Layer: Core
 * Description: What a node's metadata mapping gives it as Mermaid applies it (a shape, checked as Mermaid checks it, and
 *              a label), and the edges an identifier names, the made identifiers named only when one could be meant.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

extension AgentFlowDiagramBuilder {
    /// A metadata mapping's `shape` and `label`, as Mermaid applies them: a shape must be text, in lowercase without an
    /// underscore as written, and one Mermaid knows once its alias is resolved.
    mutating func apply(_ facts: AgentFlowMetadataFacts, toVertex index: Int, line: Int) throws(MermaidDiagramReadError) {
        if let shape = facts.shape, shape.isTruthy {
            guard case .text(let authored) = shape else {
                throw .invalidSyntax(line: line, problem: .agentFlow(.unknownShape(shape.value(in: model.text).javaScriptText)))
            }
            model.vertices[index].type = try validShape(authored, line: line)
        }
        if let label = facts.label, label.isTruthy {
            model.vertices[index].text = label.javaScriptText(in: &model.text)
            model.vertices[index].hasText = true
            model.vertices[index].labelType = facts.labelType.map(labelType(of:)) ?? .markdown
        }
    }

    /// The label type a metadata value names: Mermaid's `labelType`, one of the three names as text, else Markdown.
    private func labelType(of value: AgentFlowMetadataValue) -> AgentFlowLabelType {
        for (type, word) in Self.labelTypeWords where isText(value, word) { return type }
        return .markdown
    }

    private static let labelTypeWords = [AgentFlowLabelType.text, .string, .markdown].map { type in (type, Array(type.rawValue.utf8)) }

    /// The number of the shape `authored` names once its alias is resolved, or the error Mermaid gives for it.
    private func validShape(_ authored: MermaidTextRange, line: Int) throws(MermaidDiagramReadError) -> Int16 {
        guard model.text.isASCII(authored) else { return try validShape(written: model.text.string(authored), line: line) }
        let bytes = model.text.bytes[authored.lowerBound..<authored.upperBound]
        guard !bytes.contains(where: { byte in (byte >= 65 && byte <= 90) || byte == MermaidByte.underscore }) else {
            throw .invalidSyntax(line: line, problem: .agentFlow(.shapeNameNotLowercase(model.text.string(authored))))
        }
        let number = AgentFlowShapeNames.number(of: bytes)
        let resolved = number >= 0 ? AgentFlowShapeNames.resolved[Int(number)] : -1
        guard resolved >= 0, AgentFlowShapeNames.isValid[Int(resolved)] else {
            let name = resolved >= 0 ? AgentFlowShapeNames.names[Int(resolved)] : model.text.string(authored)
            throw .invalidSyntax(line: line, problem: .agentFlow(.unknownShape(name)))
        }
        return resolved
    }

    /// `validShape` of a name beyond ASCII, checked on its String as 0.7.0 checked it.
    private func validShape(written authored: String, line: Int) throws(MermaidDiagramReadError) -> Int16 {
        guard authored == authored.lowercased(), !FoundationTextOnBytes.contains(authored, character: MermaidByte.underscore) else {
            throw .invalidSyntax(line: line, problem: .agentFlow(.shapeNameNotLowercase(authored)))
        }
        let resolved = AgentFlowShapes.resolvingAlias(authored)
        guard AgentFlowShapes.isValidShape(resolved) else { throw .invalidSyntax(line: line, problem: .agentFlow(.unknownShape(resolved))) }
        return AgentFlowShapeNames.number(resolved)
    }

    // MARK: - Edges by identifier

    /// The first edge whose identifier is the name `name` (written `identifier`), or -1.
    mutating func edgeIndex(of name: Int32, identifier: MermaidTextRange) -> Int {
        if names[name].edge < 0, firstUnnamedEdge < model.edges.count, couldBeMadeIdentifier(identifier) { nameEdgeIdentifiers() }
        return Int(names[name].edge)
    }

    /// Whether `identifier` starts as the identifiers the reader makes (`L_`): only such a name can be one of them, as
    /// no character beyond ASCII is canonically `L` or `_`.
    private func couldBeMadeIdentifier(_ identifier: MermaidTextRange) -> Bool {
        identifier.count >= 2 && model.text.bytes[identifier.lowerBound] == 76 && model.text.bytes[identifier.lowerBound + 1] == MermaidByte.underscore
    }

    /// Names the identifiers made for the edges since the last named one, in order, each edge the first of its
    /// identifier unless an earlier one has it.
    mutating func nameEdgeIdentifiers() {
        while firstUnnamedEdge < model.edges.count {
            let edge = firstUnnamedEdge
            firstUnnamedEdge += 1
            guard model.edges[edge].identifierName < 0 else { continue }
            let name = name(of: model.edges[edge].identifier)
            model.edges[edge].identifierName = name
            if names[name].edge < 0 { names[name].edge = Int32(edge) }
        }
    }
}
