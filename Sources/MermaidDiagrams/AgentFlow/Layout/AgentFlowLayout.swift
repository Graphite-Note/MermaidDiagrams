/**
 * File: AgentFlowLayout.swift
 * ---------------------------
 * Layer: Core
 * Description: An agent flow laid out on a page: its flows' boxes, its nodes in their kinds' palette slots, and its
 *              edges by meaning, each identifier a range of the model's bytes until it is read.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 26/11/2026
 */

import CoreGraphics

/// An agent flow laid out on a page whose origin is the top left corner and whose y runs down, in points.
public struct AgentFlowLayout: Equatable, Sendable {
    public let size: CGSize
    public let font: DiagramFont
    /// The title above the diagram, drawn bold, or nil.
    public let title: DiagramTextBlock?
    /// The open flows' boxes, each before the boxes inside it.
    public let flows: [AgentFlowLayoutFlow]
    /// The nodes drawn, collapsed flows among them, in the order of the graph.
    public let nodes: [AgentFlowLayoutNode]
    /// The edges drawn, those between a node and a flow around it last.
    public let edges: [AgentFlowLayoutEdge]
}

/// An open flow's box: a light wash of its palette color with an outline in it, and its title along the top.
public struct AgentFlowLayoutFlow: Equatable, Sendable {
    /// Its identifier's bytes, made a String only when read.
    let identifierText: AgentFlowLayoutIdentifier
    public let frame: CGRect
    public let title: DiagramTextBlock?
    /// The series color of the flow (Pele's container slots).
    public let paletteSlot: Int
    public let style: DiagramElementStyle?
}

public struct AgentFlowLayoutNode: Equatable, Sendable {
    /// Its identifier's bytes, made a String only when read.
    let identifierText: AgentFlowLayoutIdentifier
    /// The shape the node is drawn in; a collapsed flow is a rounded box with a dashed line and three dots.
    public let shape: FlowchartNodeShape
    public let isCollapsedFlow: Bool
    public let frame: CGRect
    public let text: DiagramTextBlock
    /// The series color of the node's kind, or of a collapsed flow's slot.
    public let paletteSlot: Int
    /// What the node means, nil for a collapsed flow.
    public let kind: AgentFlowVertexKind?
    public let style: DiagramElementStyle?
    /// Whether its style sets its text bold, and italic; the size it sets is the text's own (`DiagramTextBlock.fontSize`).
    public let isBold: Bool
    public let isItalic: Bool
}

public struct AgentFlowLayoutEdge: Equatable, Sendable {
    /// Its identifier's bytes, made a String only when read.
    let identifierText: AgentFlowLayoutIdentifier
    /// What it means as Pele draws it: dotted is a reference, a cross a failure, else a step.
    public let semantic: AgentFlowEdgeSemantic
    public let isDotted: Bool
    /// The line, which stops where the mark begins.
    public let path: DiagramPath
    public let targetMark: DiagramEdgeMark?
    /// The edge's text on a patch of the page's color, or nil.
    public let text: DiagramTextBlock?
    public let style: DiagramElementStyle?
}

/// An identifier of a laid-out agent flow's flow, node or edge: a range of the model's bytes, which it holds, made a
/// String only when read, so that a layout whose identifiers are not read makes none.
struct AgentFlowLayoutIdentifier: Equatable, Sendable {
    private let bytes: [UInt8]
    private let range: MermaidTextRange

    init(bytes: [UInt8], range: MermaidTextRange) {
        self.bytes = bytes
        self.range = range
    }

    init(_ string: String) {
        bytes = Array(string.utf8)
        range = MermaidTextRange(start: 0, end: bytes.count)
    }

    var string: String { String(decoding: bytes[range.lowerBound..<range.upperBound], as: UTF8.self) }

    static func == (left: AgentFlowLayoutIdentifier, right: AgentFlowLayoutIdentifier) -> Bool { left.string == right.string }
}

extension AgentFlowLayoutFlow {
    /// The flow's identifier.
    public var identifier: String { identifierText.string }

    init(identifier: String, frame: CGRect, title: DiagramTextBlock?, paletteSlot: Int, style: DiagramElementStyle?) {
        self.init(identifierText: AgentFlowLayoutIdentifier(identifier), frame: frame, title: title, paletteSlot: paletteSlot, style: style)
    }
}

extension AgentFlowLayoutNode {
    /// The node's identifier.
    public var identifier: String { identifierText.string }

    init(identifier: String, shape: FlowchartNodeShape, isCollapsedFlow: Bool, frame: CGRect, text: DiagramTextBlock, paletteSlot: Int,
         kind: AgentFlowVertexKind?, style: DiagramElementStyle?, isBold: Bool, isItalic: Bool) {
        self.init(identifierText: AgentFlowLayoutIdentifier(identifier), shape: shape, isCollapsedFlow: isCollapsedFlow, frame: frame, text: text,
                  paletteSlot: paletteSlot, kind: kind, style: style, isBold: isBold, isItalic: isItalic)
    }
}

extension AgentFlowLayoutEdge {
    /// The edge's identifier.
    public var identifier: String { identifierText.string }

    init(identifier: String, semantic: AgentFlowEdgeSemantic, isDotted: Bool, path: DiagramPath, targetMark: DiagramEdgeMark?, text: DiagramTextBlock?,
         style: DiagramElementStyle?) {
        self.init(identifierText: AgentFlowLayoutIdentifier(identifier), semantic: semantic, isDotted: isDotted, path: path, targetMark: targetMark,
                  text: text, style: style)
    }
}
