/**
 * File: DiagramSceneShapeRun.swift
 * --------------------------------
 * Layer: Core
 * Description: Shapes painted alike one after the other, opaque and apart, kept as a list and merged into one path once,
 *              when the run ends; a fill followed by the stroke of its own path becomes one shape filled and stroked.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import CoreGraphics

/// The shapes a scene builder is merging into one: the first path as it was given, the others' elements added after it
/// as Core Graphics adds one path to another, so that a run of any length costs its paths' elements once.
struct DiagramSceneShapeRun {
    private(set) var painting: DiagramShapePainting
    let part: DiagramScenePart
    private var path: DiagramScenePath
    private var pathCount = 1
    /// The paths' bounds together, which is what a shape added must stay apart from.
    private var bounds: CGRect

    init(path: DiagramScenePath, painting: DiagramShapePainting, part: DiagramScenePart) {
        self.painting = painting
        self.part = part
        self.path = path
        bounds = path.boundingBoxOfPath
    }

    /// The run as one shape: its one path as it was given, or its paths joined into one.
    var shape: DiagramSceneShape {
        DiagramSceneShape(scenePath: path.compacted(), painting: painting, part: part)
    }

    /// Adds `path` to the run when it is painted as the run, of the same part, in paints at full opacity, apart from the
    /// run's shapes; else leaves the run as it is and says so.
    mutating func merge(_ path: DiagramScenePath, painting: DiagramShapePainting, part: DiagramScenePart) -> Bool {
        guard painting == self.painting, part == self.part, Self.isOpaque(painting) else { return false }
        let pathBounds = path.boundingBoxOfPath
        guard !Self.mayTouch(bounds, pathBounds, painting: painting) else { return false }
        self.path.addPath(path)
        pathCount += 1
        bounds = bounds.union(pathBounds)
        return true
    }

    /// Turns a run of one filled path into that path filled and then stroked, when `path` is that same path stroked in
    /// the same part: painted as one shape, it is painted exactly as the fill and the stroke one after the other.
    mutating func outline(_ path: DiagramScenePath, painting: DiagramShapePainting, part: DiagramScenePart) -> Bool {
        guard part == self.part, pathCount == 1, case .fill(let fill) = self.painting, case .stroke(let paint, let stroke) = painting,
              self.path == path else { return false }
        self.painting = .fillAndStroke(fill, paint, stroke)
        return true
    }

    /// How far beyond a path's bounds its edge's smoothing may reach, in points: a pixel at a scale of one half.
    private static let smoothingReach: CGFloat = 2

    /// Whether two shapes may cover a pixel both, where painting them apart and painting them as one blend their edges
    /// differently: their bounds, widened by half the stroke and the smoothing's reach, meet.
    private static func mayTouch(_ first: CGRect, _ second: CGRect, painting: DiagramShapePainting) -> Bool {
        var reach = smoothingReach
        switch painting {
        case .stroke(_, let stroke), .fillAndStroke(_, _, let stroke): reach += stroke.lineWidth / 2
        case .fill, .gradientFill: break
        }
        return first.insetBy(dx: -reach, dy: -reach).intersects(second.insetBy(dx: -reach, dy: -reach))
    }

    /// Whether merging changes nothing a painting covers twice: fills and strokes at full opacity of roles or written
    /// colors without their own transparency. A gradient is never merged.
    private static func isOpaque(_ painting: DiagramShapePainting) -> Bool {
        switch painting {
        case .fill(let paint): isOpaque(paint)
        case .stroke(let paint, _): isOpaque(paint)
        case .fillAndStroke(let fill, let paint, _): isOpaque(fill) && isOpaque(paint)
        case .gradientFill: false
        }
    }

    private static func isOpaque(_ paint: DiagramPaint) -> Bool {
        guard paint.opacity == 1 else { return false }
        if case .color(let color) = paint.source { return color.alpha == 1 }
        return true
    }
}
