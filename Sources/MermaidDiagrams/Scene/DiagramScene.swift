/**
 * File: DiagramScene.swift
 * ------------------------
 * Layer: Core
 * Description: A diagram's painting as a list of shapes and placed text, back to front, its colors given as roles of a
 *              palette, the one form every diagram type is drawn, exported and themed from; its shapes' paths are kept
 *              as their elements in one block, and a Core Graphics path is made only for a reader that asks for one.
 *
 * Authors: Bahey Shalash
 * Version: 0.8
 * Date: 24/11/2026
 */

import CoreGraphics

/// A laid-out diagram's painting, whatever its type: the page it was laid out on and what is painted on it, back to front.
/// Shapes and text name their colors by `DiagramPalette`'s roles (`DiagramPaint`), so a change of theme paints the same
/// scene again in other colors without reading or laying out again. Core Graphics draws it (`DiagramSceneRenderer`), SVG
/// writes it (`DiagramSVGWriter`), and a view can paint it as its own shapes: each item is one fill, stroke, or fill and
/// stroke of one path, whatever its type painted alike already merged into that path, or one placed text.
///
/// The shapes' paths are kept as their elements, as Core Graphics gives a path's elements out, in one block of memory
/// with a small record per item (`DiagramSceneStorage`). `forEachItem` reads them where they are; `items` and `shapes`
/// make a Core Graphics path of each shape on every read.
public struct DiagramScene: Sendable {
    /// The page, its origin at the top left and its y running down, in points.
    public let size: CGSize
    /// The font the text was measured in: each text is drawn in it at its block's own size.
    public let font: DiagramFont
    /// The series colors the diagram's own theme variables set (`pie1`, `cScale0`, `xyChart.plotColorPalette` …), which
    /// its series are painted in over any palette's (`DiagramSeriesColors.palette(over:)`), as Pele's SVG sets them over
    /// the page's; none for most diagrams. The label inks on them are already the paints of the texts they color.
    public let seriesColors: DiagramSeriesColors
    /// The text, back to front, without the shapes.
    public let texts: [DiagramSceneText]
    /// The items' records and the shapes' elements.
    let storage: DiagramSceneStorage
    /// Each shape's painting, in the shapes' order.
    let paintings: [DiagramShapePainting]

    /// A scene of `items`, each shape's path read once into the scene's storage.
    public init(size: CGSize, font: DiagramFont, items: [DiagramSceneItem], seriesColors: DiagramSeriesColors = .none) {
        var builder = DiagramSceneItemCopying()
        for item in items { builder.add(item) }
        self = builder.scene(size: size, font: font, seriesColors: seriesColors)
    }

    init(size: CGSize, font: DiagramFont, seriesColors: DiagramSeriesColors, storage: DiagramSceneStorage, paintings: [DiagramShapePainting],
         texts: [DiagramSceneText]) {
        self.size = size
        self.font = font
        self.seriesColors = seriesColors
        self.storage = storage
        self.paintings = paintings
        self.texts = texts
    }

    /// The palette the scene is painted in where a host's is `palette`: the host's, with the series the diagram's theme
    /// variables set in their colors.
    public func palette(over palette: DiagramPalette) -> DiagramPalette {
        seriesColors.palette(over: palette)
    }

    /// How many items the scene paints.
    public var itemCount: Int { storage.itemCount }

    /// Calls `body` with each item, back to front, where the scene keeps it: a shape's elements are read without a Core
    /// Graphics path. A shape's view keeps the scene's storage, so that it stays valid wherever it is kept.
    public func forEachItem(_ body: (DiagramSceneItemView) throws -> Void) rethrows {
        let storage = storage
        try storage.withContents { contents in
            for index in 0..<contents.itemCount {
                let record = contents.records[index]
                switch record.kind {
                case .shape:
                    try body(.shape(DiagramSceneShapeView(storage: storage, index: index, painting: paintings[Int(record.index)], part: record.part)))
                case .text:
                    try body(.text(texts[Int(record.index)]))
                }
            }
        }
    }

    /// What is painted, back to front, each shape's path made anew from its elements.
    public var items: [DiagramSceneItem] {
        var items: [DiagramSceneItem] = []
        items.reserveCapacity(itemCount)
        forEachItem { item in
            switch item {
            case .shape(let shape): items.append(.shape(DiagramSceneShape(unchangedPath: shape.makePath(), painting: shape.painting, part: shape.part)))
            case .text(let text): items.append(.text(text))
            }
        }
        return items
    }

    /// The shapes, back to front, without the text, each path made anew from its elements.
    public var shapes: [DiagramSceneShape] {
        var shapes: [DiagramSceneShape] = []
        forEachItem { item in
            guard case .shape(let shape) = item else { return }
            shapes.append(DiagramSceneShape(unchangedPath: shape.makePath(), painting: shape.painting, part: shape.part))
        }
        return shapes
    }
}

/// One thing a scene paints: a shape, or placed text.
public enum DiagramSceneItem: Sendable {
    case shape(DiagramSceneShape)
    case text(DiagramSceneText)
}

/// One thing a scene paints, read where the scene keeps it (`DiagramScene.forEachItem`).
public enum DiagramSceneItemView: Sendable {
    case shape(DiagramSceneShapeView)
    case text(DiagramSceneText)
}

/// A shape of a scene read where the scene keeps it: its painting, its part and its path's elements. It holds the scene's
/// storage, which nothing changes once made, so that it may be kept after the `forEachItem` call that gave it and even
/// after its scene; only the points `forEachElement` hands out are valid only inside that call.
public struct DiagramSceneShapeView: Sendable {
    let storage: DiagramSceneStorage
    let index: Int
    public let painting: DiagramShapePainting
    public let part: DiagramScenePart

    /// Calls `body` with each element of the shape's path and its points (a curve's control points before its end), as
    /// Core Graphics gives a path's elements out; the points are valid only inside `body`.
    public func forEachElement(_ body: (DiagramPathVerb, UnsafePointer<CGPoint>) throws -> Void) rethrows {
        try storage.withContents { contents in try contents.forEachElement(ofItemAt: index, body) }
    }

    /// How many elements the shape's path has.
    public var elementCount: Int { storage.withContents { contents in contents.verbRange(ofItemAt: index).count } }

    /// A Core Graphics path of the shape's elements.
    public func makePath() -> CGPath {
        storage.withContents { contents in contents.makePath(ofItemAt: index) }
    }
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
    /// Whether it is drawn in the system's monospaced font at the block's size, as Pele draws terminals and data.
    public let isMonospaced: Bool
    /// The turn about the block's center, in radians, positive turning clockwise on the page (whose y runs down); nil
    /// for text drawn as it lies.
    public let rotation: CGFloat?
    /// The outline stroked under the text, or nil for none: a Sankey diagram's labels in the page's color.
    public let outline: DiagramTextOutline?
    public let part: DiagramScenePart

    public init(block: DiagramTextBlock, paint: DiagramPaint, isBold: Bool = false, isItalic: Bool = false, isMonospaced: Bool = false,
                rotation: CGFloat? = nil, outline: DiagramTextOutline? = nil, part: DiagramScenePart) {
        self.block = block
        self.paint = paint
        self.isBold = isBold
        self.isItalic = isItalic
        self.isMonospaced = isMonospaced
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
