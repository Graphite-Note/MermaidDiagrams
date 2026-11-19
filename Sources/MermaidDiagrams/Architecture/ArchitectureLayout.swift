/**
 * File: ArchitectureLayout.swift
 * ------------------------------
 * Layer: Core
 * Description: A laid-out architecture diagram: its groups' boxes and heads, its edges' lines, arrows and text, its
 *              services' squares, icons and titles and its junctions' dots, on a page whose origin is its top left.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// An architecture diagram laid out on a page whose origin is the top left corner and whose y runs down, in points, as
/// Pele lays it out: the bold title above; the groups' boxes; the edges; their texts; the services and junctions.
public struct ArchitectureLayout: Equatable, Sendable {
    public let size: CGSize
    /// The font the titles were measured in, at the size the options set; the diagram's title is in its bold.
    public let font: DiagramFont
    public let title: DiagramTextBlock?
    public let groups: [ArchitectureLayoutGroup]
    public let edges: [ArchitectureLayoutEdge]
    /// The edges' texts, each drawn on a patch of the page's color 8 points wider than it.
    public let edgeTexts: [DiagramTextBlock]
    public let nodes: [ArchitectureLayoutNode]
}

/// An icon's slot: its name and its square.
public struct ArchitectureLayoutIcon: Equatable, Sendable {
    public let name: String
    public let frame: CGRect
}

/// A group's box, the icon at the start of its head and its title after it.
public struct ArchitectureLayoutGroup: Equatable, Sendable {
    public let identifier: String
    public let frame: CGRect
    public let icon: ArchitectureLayoutIcon?
    public let title: DiagramTextBlock?
}

/// An edge's line and the arrows at its ends.
public struct ArchitectureLayoutEdge: Equatable, Sendable {
    public let sourceIdentifier: String
    public let targetIdentifier: String
    public let path: DiagramPath
    public let sourceArrow: DiagramEdgeMark?
    public let targetArrow: DiagramEdgeMark?
}

/// A service or a junction.
public struct ArchitectureLayoutNode: Equatable, Sendable {
    public enum Form: Equatable, Sendable {
        /// The icon's square, the icon in it or the text written for it, and the title below.
        case service(square: CGRect, icon: ArchitectureLayoutIcon?, iconText: DiagramTextBlock?, title: DiagramTextBlock?)
        /// A dot of `radius` at `center`.
        case junction(center: CGPoint, radius: CGFloat)
    }

    public let identifier: String
    public let form: Form
}
