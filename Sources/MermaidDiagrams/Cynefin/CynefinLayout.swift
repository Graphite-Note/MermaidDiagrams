/**
 * File: CynefinLayout.swift
 * -------------------------
 * Layer: Core
 * Description: A Cynefin framework laid out on a page whose y runs down: the domains' regions, their wavy boundaries and
 *              the cliff, the confusion ellipse, each domain's block of text and items, and the transitions.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// A Cynefin framework laid out on a page whose origin is the top left corner and whose y runs down, in points, as Pele
/// lays it out: four quadrants around a confusion ellipse in the middle, waving boundaries between them and the cliff
/// between Clear and Chaotic, each domain's name, decision model, practice and items in the middle of its quadrant, and
/// the transitions as curves bowing away from the middle.
public struct CynefinLayout: Equatable, Sendable {
    public let size: CGSize
    /// The font the domains' names and the title were measured in (bold); subtitles are in thirteen sixteenths of its size
    /// in italic, items in seven eighths, transitions' labels in thirteen sixteenths.
    public let font: DiagramFont
    public let title: DiagramTextBlock?
    /// The four quadrants' regions in Pele's order (Complex, Complicated, Chaotic, Clear), each filled in its series color.
    public let regions: [CynefinLayoutRegion]
    /// The fold between Complex and Complicated, then the boundaries west and east of the middle, drawn dashed.
    public let boundaries: [DiagramPath]
    /// The cliff between Chaotic and Clear, drawn as a solid line.
    public let cliff: DiagramPath
    /// The confusion ellipse's frame.
    public let confusion: CGRect
    /// The domains' blocks: the four quadrants', then confusion's.
    public let blocks: [CynefinLayoutBlock]
    public let transitions: [CynefinLayoutTransition]
}

/// A quadrant's region, a closed outline of lines and the boundaries' curves, and its series color.
public struct CynefinLayoutRegion: Equatable, Sendable {
    public let domain: CynefinDomain
    public let outline: DiagramPath
    public let seriesIndex: Int
}

/// A domain's block: its name (bold), its decision model and practice (italic, muted), and its items as badges.
public struct CynefinLayoutBlock: Equatable, Sendable {
    public let domain: CynefinDomain
    public let name: DiagramTextBlock
    public let subtitles: [DiagramTextBlock]
    public let badges: [CynefinLayoutBadge]
    /// The block's extent around its center.
    public let frame: CGRect
}

/// An item of a domain: its box and its text; the last of confusion's may stand for the items not shown (`+2 more`),
/// drawn dashed and muted.
public struct CynefinLayoutBadge: Equatable, Sendable {
    public let frame: CGRect
    public let text: DiagramTextBlock
    public let isOverflow: Bool
}

/// A transition: its curve from the edge of one block to the edge of the other, the arrow at its end, and its label.
public struct CynefinLayoutTransition: Equatable, Sendable {
    public let from: CynefinDomain
    public let to: CynefinDomain
    public let path: DiagramPath
    public let arrow: DiagramEdgeMark
    public let label: DiagramTextBlock?
}
