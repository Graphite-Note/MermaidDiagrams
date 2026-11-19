/**
 * File: DiagramScene.swift
 * ------------------------
 * Layer: Core
 * Description: A diagram's painting as a list of shapes and placed text, back to front, its colors given as roles of a
 *              palette, the one form every diagram type is drawn, exported and themed from.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 19/11/2026
 */

import CoreGraphics

/// A laid-out diagram's painting, whatever its type: the page it was laid out on and what is painted on it, back to front.
/// Shapes and text name their colors by `DiagramPalette`'s roles (`DiagramPaint`), so a change of theme paints the same
/// scene again in other colors without reading or laying out again. Core Graphics draws it (`DiagramSceneRenderer`), SVG
/// writes it (`DiagramSVGWriter`), and a view can paint it as its own shapes: each item is one fill, stroke, or fill and
/// stroke of one path, whatever its type painted alike already merged into that path, or one placed text.
public struct DiagramScene: Sendable {
    /// The page, its origin at the top left and its y running down, in points.
    public let size: CGSize
    /// The font the text was measured in: each text is drawn in it at its block's own size.
    public let font: DiagramFont
    /// What is painted, back to front.
    public let items: [DiagramSceneItem]

    public init(size: CGSize, font: DiagramFont, items: [DiagramSceneItem]) {
        self.size = size
        self.font = font
        self.items = items
    }

    /// The shapes, back to front, without the text.
    public var shapes: [DiagramSceneShape] {
        items.compactMap { item in
            guard case .shape(let shape) = item else { return nil }
            return shape
        }
    }

    /// The text, back to front, without the shapes.
    public var texts: [DiagramSceneText] {
        items.compactMap { item in
            guard case .text(let text) = item else { return nil }
            return text
        }
    }
}

/// One thing a scene paints: a shape, or placed text.
public enum DiagramSceneItem: Sendable {
    case shape(DiagramSceneShape)
    case text(DiagramSceneText)
}

/// A path filled, stroked, or filled and stroked once: everything of a diagram painted alike and one after the other, in one path.
public struct DiagramSceneShape: Sendable {
    private let storage: DiagramPathStorage
    public let painting: DiagramShapePainting
    /// What of the diagram the shape is, for a writer that names it (`DiagramSVGWriter`'s classes).
    public let part: DiagramScenePart

    /// A shape of a copy of `path`, which no later change to `path` reaches.
    public init(path: CGPath, painting: DiagramShapePainting, part: DiagramScenePart) {
        self.init(unchangedPath: path.copy() ?? path, painting: painting, part: part)
    }

    /// A shape of `unchangedPath` itself, which nothing changes afterwards: a drawing part's finished path.
    init(unchangedPath: CGPath, painting: DiagramShapePainting, part: DiagramScenePart) {
        storage = DiagramPathStorage(path: unchangedPath)
        self.painting = painting
        self.part = part
    }

    /// In the scene's coordinates. Its subpaths are filled together by the nonzero rule.
    public var path: CGPath { storage.path }
}

/// Holds a path no one changes once it is made, so that a scene can be handed from the thread that made it to the one that
/// paints it. Core Graphics does not mark its paths sendable, as a mutable path is not; one never changed is only read.
private final class DiagramPathStorage: @unchecked Sendable {
    let path: CGPath

    init(path: CGPath) {
        self.path = path
    }
}

/// How a shape is painted.
public enum DiagramShapePainting: Hashable, Sendable {
    /// Its inside, in one paint.
    case fill(DiagramPaint)
    /// Its outline, in one paint and stroke.
    case stroke(DiagramPaint, DiagramStroke)
    /// Its inside in the first paint, then its outline in the second paint and the stroke, as an outlined box is
    /// painted: one shape where a fill and a stroke of the same path would be two.
    case fillAndStroke(DiagramPaint, DiagramPaint, DiagramStroke)
    /// Its inside, in a gradient between two paints (a Sankey diagram's bands).
    case gradientFill(DiagramLinearGradient)
}

/// How an outline is stroked.
public struct DiagramStroke: Hashable, Sendable {
    /// In points.
    public let lineWidth: CGFloat
    /// The dashes and gaps, in points, from the start of each subpath; empty for a solid line.
    public let dashLengths: [CGFloat]
    public let lineCap: CGLineCap
    public let lineJoin: CGLineJoin

    public init(lineWidth: CGFloat, dashLengths: [CGFloat] = [], lineCap: CGLineCap = .butt, lineJoin: CGLineJoin = .miter) {
        self.lineWidth = lineWidth
        self.dashLengths = dashLengths
        self.lineCap = lineCap
        self.lineJoin = lineJoin
    }

    /// Round ends and corners, as most of Pele's lines have.
    public static func rounded(lineWidth: CGFloat, dashLengths: [CGFloat] = []) -> DiagramStroke {
        DiagramStroke(lineWidth: lineWidth, dashLengths: dashLengths, lineCap: .round, lineJoin: .round)
    }
}

/// A fill that runs from one paint to another along a line, and keeps the end paints beyond the line's ends.
public struct DiagramLinearGradient: Hashable, Sendable {
    public let startPaint: DiagramPaint
    public let endPaint: DiagramPaint
    public let startPoint: CGPoint
    public let endPoint: CGPoint
    /// The opacity of the whole fill, over the paints' own.
    public let opacity: CGFloat

    public init(startPaint: DiagramPaint, endPaint: DiagramPaint, startPoint: CGPoint, endPoint: CGPoint, opacity: CGFloat = 1) {
        self.startPaint = startPaint
        self.endPaint = endPaint
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.opacity = opacity
    }
}

/// Text placed in a scene: a measured block, each of its lines centered on the block's center one line height below
/// the last, in the scene's font at the block's size.
public struct DiagramSceneText: Sendable {
    public let block: DiagramTextBlock
    public let paint: DiagramPaint
    public let isBold: Bool
    public let isItalic: Bool
    /// The turn about the block's center, in radians, positive turning clockwise on the page (whose y runs down); nil
    /// for text drawn as it lies.
    public let rotation: CGFloat?
    /// The outline stroked under the text, or nil for none: a Sankey diagram's labels in the page's color.
    public let outline: DiagramTextOutline?
    public let part: DiagramScenePart

    public init(block: DiagramTextBlock, paint: DiagramPaint, isBold: Bool = false, isItalic: Bool = false, rotation: CGFloat? = nil,
                outline: DiagramTextOutline? = nil, part: DiagramScenePart) {
        self.block = block
        self.paint = paint
        self.isBold = isBold
        self.isItalic = isItalic
        self.rotation = rotation
        self.outline = outline
        self.part = part
    }

    /// The font of the text: the scene's font at the block's size.
    public func font(in scene: DiagramScene) -> DiagramFont {
        DiagramFont(postScriptName: scene.font.postScriptName, size: block.fontSize)
    }
}

/// The outline of a text's glyphs, stroked in a paint with round joins under the text itself, which keeps the text legible
/// where it crosses shapes.
public struct DiagramTextOutline: Hashable, Sendable {
    public let paint: DiagramPaint
    /// In points, centered on the glyphs' edges.
    public let lineWidth: CGFloat

    public init(paint: DiagramPaint, lineWidth: CGFloat) {
        self.paint = paint
        self.lineWidth = lineWidth
    }
}

/// What part of a diagram an item paints, by the class Pele's SVG gives it (`pele-` and the raw value).
public enum DiagramScenePart: String, Hashable, Sendable, CaseIterable {
    /// The diagram's title.
    case title
    /// Edges, transitions, messages, links and connectors.
    case edge
    /// The marks at their ends: arrowheads, circles, crosses, cardinalities.
    case marker
    /// The text on edges.
    case edgeLabel = "edge-label"
    /// The patches behind text, which keep lines from running through it.
    case labelBackground = "label-bg"
    /// Nodes and what a chart plots: shapes, states, classes, entities, participants, slices, bars, points, tasks, commits.
    case node
    /// The text in or beside nodes.
    case label
    /// Boxes that hold others: groups, composite states, blocks, sections, lanes, bands.
    case cluster
    /// Their titles.
    case clusterLabel = "cluster-label"
    /// Notes and their text.
    case note
    /// Axes, grids, scales and lifelines.
    case axis
    /// The text along axes.
    case axisLabel = "axis-label"
    /// Legends and their text.
    case legend
    /// A kanban column's count of cards.
    case count
    /// A kanban card's priority mark.
    case priority
    /// A kanban card's ticket.
    case ticket
    /// A kanban card's assignee.
    case assigned
    /// A tree view's lines from each folder to its entries.
    case treeGuides = "tree-guides"
    /// The band behind a highlighted tree view entry.
    case treeHighlight = "tree-highlight"
    /// A tree view entry's description.
    case treeDescription = "tree-description"
    /// An icon drawn from its glyph: a tree view's file and folder icons.
    case icon
    /// An Ishikawa diagram's spine, which runs to its head.
    case ishikawaSpine = "ishikawa-spine"
    /// An Ishikawa diagram's bones, from the spine to each category and cause.
    case ishikawaBones = "ishikawa-bones"
    /// An info diagram's line of the package's version.
    case version
    /// The first and last bit written above a packet diagram's field.
    case bitNumber = "packet-bits"
    /// The rings of a radar chart.
    case graticule
    /// A radar chart's curve.
    case curve
    /// A treemap's section: a box that holds others.
    case section
    /// A treemap's leaf.
    case leaf
    /// The value a treemap writes in a box.
    case value
}
