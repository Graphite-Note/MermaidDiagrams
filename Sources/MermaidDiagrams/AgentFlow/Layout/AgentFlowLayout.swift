/**
 * File: AgentFlowLayout.swift
 * ---------------------------
 * Layer: Core
 * Description: An agent flow laid out on a page: its flows' boxes, its nodes in their kinds' palette slots, and its
 *              edges by meaning.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
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
    public let identifier: String
    public let frame: CGRect
    public let title: DiagramTextBlock?
    /// The series color of the flow (Pele's container slots).
    public let paletteSlot: Int
    public let style: DiagramElementStyle?
}

public struct AgentFlowLayoutNode: Equatable, Sendable {
    public let identifier: String
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
}

public struct AgentFlowLayoutEdge: Equatable, Sendable {
    public let identifier: String
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
