/**
 * File: DiagramSceneBuilder.swift
 * -------------------------------
 * Layer: Core
 * Description: Collects a scene's items back to front, leaving out what paints nothing and merging a shape into the one
 *              before it when both are painted alike, opaque and apart.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// Collects a scene's items back to front, as each diagram type's scene is made from its drawing parts. An empty path
/// or a text without lines paints nothing and is left out. A shape painted as the one just before it, of the same part,
/// in a paint at full opacity, apart from it, is merged into that one's path, so that a consumer paints as few shapes as
/// possible. Shapes that touch, or are translucent, are not merged: where two shapes share a pixel, painting them one after
/// the other is not painting them as one. The paths it is
/// given are kept as they are: each is a drawing part's finished path, which nothing changes afterwards.
struct DiagramSceneBuilder {
    private(set) var items: [DiagramSceneItem] = []

    mutating func fill(_ path: CGPath, _ paint: DiagramPaint, part: DiagramScenePart) {
        add(path, painting: .fill(paint), part: part)
    }

    mutating func stroke(_ path: CGPath, _ paint: DiagramPaint, _ stroke: DiagramStroke, part: DiagramScenePart) {
        add(path, painting: .stroke(paint, stroke), part: part)
    }

    /// Fills `path` and then strokes it, as a box with an outline is painted.
    mutating func fillAndStroke(_ path: CGPath, fill: DiagramPaint, stroke paint: DiagramPaint, _ stroke: DiagramStroke, part: DiagramScenePart) {
        self.fill(path, fill, part: part)
        self.stroke(path, paint, stroke, part: part)
    }

    mutating func fill(_ path: CGPath, _ gradient: DiagramLinearGradient, part: DiagramScenePart) {
        add(path, painting: .gradientFill(gradient), part: part)
    }

    mutating func text(_ block: DiagramTextBlock?, _ paint: DiagramPaint, isBold: Bool = false, isItalic: Bool = false, rotation: CGFloat? = nil,
                       part: DiagramScenePart) {
        guard let block, !block.lines.isEmpty else { return }
        items.append(.text(DiagramSceneText(block: block, paint: paint, isBold: isBold, isItalic: isItalic, rotation: rotation, part: part)))
    }

    mutating func texts(_ blocks: [DiagramTextBlock], _ paint: DiagramPaint, isBold: Bool = false, part: DiagramScenePart) {
        for block in blocks { text(block, paint, isBold: isBold, part: part) }
    }

    /// The diagram's title, bold in the foreground color.
    mutating func title(_ block: DiagramTextBlock?) {
        text(block, .foreground, isBold: true, part: .title)
    }

    func scene(size: CGSize, font: DiagramFont) -> DiagramScene {
        DiagramScene(size: size, font: font, items: items)
    }

    private mutating func add(_ path: CGPath, painting: DiagramShapePainting, part: DiagramScenePart) {
        guard !path.isEmpty else { return }
        if case .shape(let last) = items.last, last.painting == painting, last.part == part, Self.isOpaque(painting),
           !Self.mayTouch(last.path, path, painting: painting) {
            let merged = CGMutablePath()
            merged.addPath(last.path)
            merged.addPath(path)
            items[items.count - 1] = .shape(DiagramSceneShape(unchangedPath: merged, painting: painting, part: part))
            return
        }
        items.append(.shape(DiagramSceneShape(unchangedPath: path, painting: painting, part: part)))
    }

    /// How far beyond a path's bounds its edge's smoothing may reach, in points: a pixel at a scale of one half.
    private static let smoothingReach: CGFloat = 2

    /// Whether two paths may cover a pixel both, where painting them apart and painting them as one blend their edges
    /// differently: their bounds, widened by half the stroke and the smoothing's reach, meet.
    private static func mayTouch(_ first: CGPath, _ second: CGPath, painting: DiagramShapePainting) -> Bool {
        var reach = smoothingReach
        if case .stroke(_, let stroke) = painting { reach += stroke.lineWidth / 2 }
        return first.boundingBoxOfPath.insetBy(dx: -reach, dy: -reach).intersects(second.boundingBoxOfPath.insetBy(dx: -reach, dy: -reach))
    }

    /// Whether merging changes nothing a painting covers twice: a fill or a stroke at full opacity of a role or a
    /// written color without its own transparency. A gradient is never merged.
    private static func isOpaque(_ painting: DiagramShapePainting) -> Bool {
        let paint: DiagramPaint
        switch painting {
        case .fill(let fillPaint): paint = fillPaint
        case .stroke(let strokePaint, _): paint = strokePaint
        case .gradientFill: return false
        }
        guard paint.opacity == 1 else { return false }
        if case .color(let color) = paint.source { return color.alpha == 1 }
        return true
    }
}
