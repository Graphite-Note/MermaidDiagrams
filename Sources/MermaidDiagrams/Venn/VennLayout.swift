/**
 * File: VennLayout.swift
 * ----------------------
 * Layer: Core
 * Description: A Venn diagram laid out on a page whose y runs down: its circles, the overlaps a style outlines, the text
 *              in each region with its color, and the title.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

import CoreGraphics

/// A Venn diagram laid out on a page whose origin is the top left corner and whose y runs down, in points, as Pele lays
/// it out: one circle per set, its area in proportion to the set's size, the largest 100 points in radius or grown so
/// that every region holds its text; the overlaps a style gives a look of their own; each region's text at its roomiest
/// point; the bold title above.
public struct VennLayout: Equatable, Sendable {
    public let size: CGSize
    /// The font the title was measured in (bold); a set's text is in its size, an overlap's in seven eighths of it, a
    /// region's texts in thirteen sixteenths.
    public let font: DiagramFont
    public let title: DiagramTextBlock?
    /// The circles, in the order the statements first name their sets, each in its series color.
    public let sets: [VennLayoutSet]
    /// The overlaps a style outlines or fills, in the order of the statements.
    public let overlaps: [VennLayoutOverlap]
    /// The text of each set and overlap stated, in the order of the statements.
    public let regions: [VennLayoutRegion]
}

/// A set's circle: filled in its series color at a fifth of its opacity and outlined in it, unless its style says
/// otherwise.
public struct VennLayoutSet: Equatable, Sendable {
    public let identifier: String
    public let center: CGPoint
    public let radius: CGFloat
    public let seriesIndex: Int
    public let appearance: VennAppearance
}

/// An overlap a style gives a look of its own, drawn over the circles.
public struct VennLayoutOverlap: Equatable, Sendable {
    public let sets: [String]
    public let outline: VennRegionOutline
    public let appearance: VennAppearance
}

/// The lines written in a region: its label first, then its texts, one under the other around its roomiest point.
public struct VennLayoutRegion: Equatable, Sendable {
    public let sets: [String]
    public let lines: [VennLayoutRegionLine]
}

/// A line of a region: the set's or overlap's label, or one of its texts (`text`), in its color.
public struct VennLayoutRegionLine: Equatable, Sendable {
    public let text: DiagramTextBlock
    /// Whether it is one of the region's texts, drawn in the muted color unless a color is given.
    public let isRegionText: Bool
    /// The color its style writes, else the text color picked over a fill a style writes, else nil for the usual one.
    public let color: DiagramColor?
    /// The `opacity` its style writes, or nil.
    public let opacity: Double?
    /// Drawn in bold or italic as its style writes: a label measured so too, a text measured upright and regular as Pele
    /// measures it.
    public let isBold: Bool
    public let isItalic: Bool
}

/// Why a Venn diagram is not laid out.
public enum VennLayoutError: Error, Equatable, Sendable {
    /// The overlaps the diagram states and implies, or the circles its regions weigh while they look for room for their
    /// text (each region its own circles and the others that cut into it, summed), are more than the layout limit,
    /// `MermaidDiagramLimits.maximumLayoutPointCount`.
    case tooManyOverlaps(limit: Int)
}
