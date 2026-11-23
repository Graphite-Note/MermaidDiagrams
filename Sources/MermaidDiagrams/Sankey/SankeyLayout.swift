/**
 * File: SankeyLayout.swift
 * ------------------------
 * Layer: Core
 * Description: A Sankey diagram laid out on a page: bars, bands, labels and title.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import CoreGraphics

/// A Sankey diagram laid out on a page whose origin is the top left corner and whose y runs down, in points, as Pele
/// lays it out: the bold title above, the nodes as bars in columns, the bands between them, and each node's label
/// beside its bar. Drawing it needs only colors.
public struct SankeyLayout: Equatable, Sendable {
    public let size: CGSize
    /// The font the title was measured in; labels are in the same font at their own `fontSize`.
    public let font: DiagramFont
    public let title: DiagramTextBlock?
    /// One bar per node, in the order the rows first name them.
    public let nodes: [SankeyLayoutNode]
    /// One band per link, in the order of the rows.
    public let links: [SankeyLayoutLink]
    /// One label per node, in the order of `nodes`.
    public let labels: [SankeyLayoutLabel]
    /// How the bands are colored (`SankeyOptions.linkColor`).
    public let linkColor: SankeyLinkColor
    /// What every band is painted in when `linkColor` names a color or a palette's variable (`SankeyOptions.fixedLinkPaint`).
    public let fixedLinkPaint: DiagramPaint?
    /// Whether the labels are outlined in the page's color (`SankeyOptions.isOutlined`).
    public let hasOutlinedLabels: Bool
}

public struct SankeyLayoutNode: Equatable, Sendable {
    /// The node's place among the diagram's nodes, which picks its series color.
    public let seriesIndex: Int
    /// The bar, at least a point tall.
    public let frame: CGRect
    /// The color the options give the node (`SankeyOptions.nodeColors`) in place of its series color, or nil.
    public let color: DiagramColor?
    /// What the options paint the node in (`SankeyOptions.nodePaints`), a color or a palette's role, or nil.
    public let paint: DiagramPaint?
}

/// A band from the right side of one bar to the left side of another, its edges S-curves with their control points
/// halfway across.
public struct SankeyLayoutLink: Equatable, Sendable {
    public let sourceSeriesIndex: Int
    public let targetSeriesIndex: Int
    /// Where the band leaves its source, across.
    public let startX: CGFloat
    /// Where the band enters its target, across.
    public let endX: CGFloat
    /// The middle of the band where it leaves its source and where it enters its target.
    public let sourceY: CGFloat
    public let targetY: CGFloat
    /// Half the band's thickness, at least half a point.
    public let halfThickness: CGFloat
}

/// A node's label beside its bar: its name in the text color, then its value in the muted color, unless the
/// diagram's options hide values.
public struct SankeyLayoutLabel: Equatable, Sendable {
    public let name: DiagramTextBlock
    public let value: DiagramTextBlock?
}

/// Why a Sankey diagram is not laid out.
public enum SankeyLayoutError: Error, Equatable, Sendable {
    /// A link leads back to a node it comes from: a Sankey diagram's flows have no cycles, and Pele refuses them.
    case circularLinks
    /// No longer thrown: the options Pele reads for Sankey diagrams are all drawn. The case stays so that code that names it
    /// still compiles.
    case optionsNotDrawn
}
