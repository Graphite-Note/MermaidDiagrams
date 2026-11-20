/**
 * File: UseCaseLayout.swift
 * -------------------------
 * Layer: Core
 * Description: A use case diagram laid out on a page whose y runs down: its system boundaries with their titles, its
 *              relationships' lines, marks and labels, and its actors, use cases, notes and JSON tables with their
 *              texts and looks.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// A use case diagram laid out on a page whose origin is the top left corner and whose y runs down, in points, as Pele
/// lays it out: its boundaries as boxes of a layered layout, the elements in ranks inside them.
public struct UseCaseLayout: Equatable, Sendable {
    public let size: CGSize
    public let font: DiagramFont
    public let title: DiagramTextBlock?
    /// In the order of the diagram's boundaries.
    public let boundaries: [UseCaseLayoutBoundary]
    /// The relationships in the order written, then the notes' connectors.
    public let edges: [UseCaseLayoutEdge]
    /// The actors, the use cases, the notes and the JSON tables, in that order.
    public let nodes: [UseCaseLayoutNode]
}

/// A system boundary: its box, the tab that holds its title when it is a package, and its title.
public struct UseCaseLayoutBoundary: Equatable, Sendable {
    public let identifier: String
    public let frame: CGRect
    public let tabFrame: CGRect?
    public let title: DiagramTextBlock
    public let look: UseCaseLook
}

/// What a node is drawn as.
public enum UseCaseLayoutNodeForm: Equatable, Sendable {
    case actor(UseCaseActorType, isBusiness: Bool)
    case ellipse(isBusiness: Bool)
    case rectangle
    case note
    case jsonTable
}

/// An actor, a use case, a note or a JSON table: its drawn size around its center, its texts placed, and its look.
public struct UseCaseLayoutNode: Equatable, Sendable {
    public let identifier: String
    public let form: UseCaseLayoutNodeForm
    public let center: CGPoint
    /// The size of what is drawn; an actor's figure is the top 60 points of it.
    public let size: CGSize
    public let label: DiagramTextBlock
    /// `«stereotype»`, without lines where it has none.
    public let stereotype: DiagramTextBlock
    /// A JSON table's rows, its header's height and its key column's width.
    public let rows: [UseCaseLayoutJSONRow]
    public let headHeight: CGFloat
    public let keyColumnWidth: CGFloat
    public let look: UseCaseLook

    public var frame: CGRect {
        CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    }
}

/// A row of a JSON table: its key, and its value's lines each placed by its left end.
public struct UseCaseLayoutJSONRow: Equatable, Sendable {
    public let key: DiagramTextBlock
    public let valueLines: [DiagramTextBlock]
}

/// A mark at an end of a relationship: its kind, its tip and the way it points.
public struct UseCaseLayoutMark: Equatable, Sendable {
    public let marker: UseCaseMarker
    public let tip: CGPoint
    public let direction: CGVector
}

/// A relationship or a note's connector: its line, its marks, its label on a patch of the page's color, and how it is
/// painted.
public struct UseCaseLayoutEdge: Equatable, Sendable {
    public let identifier: String
    public let path: DiagramPath
    /// The line's dashes: a note's connector `2 3`, an include or extend `5 4`, an animated relationship `9 5`, else its
    /// style's, else none.
    public let dashLengths: [CGFloat]
    public let startMark: UseCaseLayoutMark?
    public let endMark: UseCaseLayoutMark?
    public let label: DiagramTextBlock?
    public let labelPatch: CGRect?
    /// An include or extend, whose label is muted.
    public let isSemantic: Bool
    public let look: UseCaseLook
    /// The color Pele's ink picks over the filled boundary the line lies in, which replaces the line's.
    public let inkOverFill: DiagramColor?
    /// The fill of the boundary the line lies in, which a hollow mark is filled with instead of the page's color.
    public let fillUnderMarks: DiagramColor?
    /// Whether a wider line of the page's color is drawn under it, as Pele cases a line that crosses the border of a
    /// filled boundary.
    public let isCased: Bool

    public var lineWidth: CGFloat { look.strokeWidth ?? 1 }
}

/// Why a use case diagram was not laid out.
public enum UseCaseLayoutError: Error, Equatable, Sendable {
    /// The layered layout would place more points than `MermaidDiagramLimits.maximumLayoutPointCount`.
    case tooManyLayoutPoints(limit: Int)
}
