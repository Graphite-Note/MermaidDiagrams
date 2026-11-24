/**
 * File: DiagramSceneBuilder.swift
 * -------------------------------
 * Layer: Core
 * Description: Collects a scene's items back to front, leaving out what paints nothing, merging a shape into the one
 *              before it when both are painted alike, opaque and apart, and a fill and the stroke of its path into one.
 *
 * Authors: Bahey Shalash
 * Version: 0.5
 * Date: 24/11/2026
 */

import CoreGraphics

/// Collects a scene's items back to front, as each diagram type's scene is made from its drawing parts. An empty path
/// or a text without lines paints nothing and is left out. A shape painted as the one just before it, of the same part,
/// in a paint at full opacity, apart from it, is merged into that one's path, so that a consumer paints as few shapes as
/// possible; the shapes of such a run are joined into one path once, when the run ends. Shapes that touch, or are
/// translucent, are not merged: where two shapes share a pixel, painting them one after the other is not painting them as
/// one. A path filled and then stroked is one shape painted both ways (`DiagramShapePainting.fillAndStroke`). The paths it
/// is given are kept as they are: each is a drawing part's finished path, which nothing changes afterwards.
struct DiagramSceneBuilder {
    private var finishedItems: [DiagramSceneItem] = []
    /// The shapes being merged into the last shape, not yet joined.
    private var openRun: DiagramSceneShapeRun?

    /// The items so far, back to front, the open run's shapes joined.
    var items: [DiagramSceneItem] {
        guard let openRun else { return finishedItems }
        return finishedItems + [.shape(openRun.shape)]
    }

    mutating func fill(_ path: CGPath, _ paint: DiagramPaint, part: DiagramScenePart) {
        add(path, painting: .fill(paint), part: part)
    }

    mutating func stroke(_ path: CGPath, _ paint: DiagramPaint, _ stroke: DiagramStroke, part: DiagramScenePart) {
        add(path, painting: .stroke(paint, stroke), part: part)
    }

    /// Fills `path` and then strokes it, as a box with an outline is painted: one shape painted both ways.
    mutating func fillAndStroke(_ path: CGPath, fill: DiagramPaint, stroke paint: DiagramPaint, _ stroke: DiagramStroke, part: DiagramScenePart) {
        add(path, painting: .fillAndStroke(fill, paint, stroke), part: part)
    }

    mutating func fill(_ path: CGPath, _ gradient: DiagramLinearGradient, part: DiagramScenePart) {
        add(path, painting: .gradientFill(gradient), part: part)
    }

    mutating func text(_ block: DiagramTextBlock?, _ paint: DiagramPaint, isBold: Bool = false, isItalic: Bool = false, isMonospaced: Bool = false,
                       rotation: CGFloat? = nil, outline: DiagramTextOutline? = nil, part: DiagramScenePart) {
        guard let block, block.lineCount > 0 else { return }
        finishRun()
        finishedItems.append(.text(DiagramSceneText(block: block, paint: paint, isBold: isBold, isItalic: isItalic, isMonospaced: isMonospaced,
                                                    rotation: rotation, outline: outline, part: part)))
    }

    mutating func texts(_ blocks: [DiagramTextBlock], _ paint: DiagramPaint, isBold: Bool = false, isItalic: Bool = false, isMonospaced: Bool = false,
                        outline: DiagramTextOutline? = nil, part: DiagramScenePart) {
        for block in blocks { text(block, paint, isBold: isBold, isItalic: isItalic, isMonospaced: isMonospaced, outline: outline, part: part) }
    }

    /// Keeps the next shape apart from the shapes before it, which it would otherwise be merged into: for pieces drawn one
    /// over another, which are painted one by one.
    mutating func keepNextShapeApart() {
        finishRun()
    }

    /// The diagram's title, bold in the foreground color.
    mutating func title(_ block: DiagramTextBlock?) {
        text(block, .foreground, isBold: true, part: .title)
    }

    func scene(size: CGSize, font: DiagramFont, seriesColors: DiagramSeriesColors = .none) -> DiagramScene {
        DiagramScene(size: size, font: font, items: items, seriesColors: seriesColors)
    }

    /// `path` merged into the open run, or made the outline of its one filled path, or else the start of a new run.
    private mutating func add(_ path: CGPath, painting: DiagramShapePainting, part: DiagramScenePart) {
        guard !path.isEmpty else { return }
        if openRun?.outline(path, painting: painting, part: part) == true || openRun?.merge(path, painting: painting, part: part) == true { return }
        finishRun()
        openRun = DiagramSceneShapeRun(path: path, painting: painting, part: part)
    }

    /// The open run joined into its shape, after the items before it.
    private mutating func finishRun() {
        guard let openRun else { return }
        finishedItems.append(.shape(openRun.shape))
        self.openRun = nil
    }
}
