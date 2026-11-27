/**
 * File: DiagramSceneShapeRun.swift
 * --------------------------------
 * Layer: Core
 * Description: Shapes painted alike one after the other, opaque and apart, joined as Core Graphics joins paths into one
 *              when the run ends; a fill followed by the stroke of its own path becomes one shape filled and stroked. Its
 *              paths are lanes, joined in the builder's run lane as they come, or Core Graphics paths kept as a list;
 *              its painting is the builder's last, compared where the builder keeps it.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 26/11/2026
 */

import CoreGraphics

/// The shapes a scene builder is merging into one. A run of lanes joins each lane into the builder's run lane as it is
/// added (`DiagramPathLane.addPath`, Core Graphics' rule), so that the lanes given may be given back at once; a run of Core
/// Graphics paths keeps them and joins them once, when the run ends. Bounds are worked out only when a shape comes that
/// may be merged, so that a shape painted unlike the one before it never has its bounds asked. The run's painting is the
/// builder's last (`runPainting`), read where the builder keeps it rather than copied into the run; every test that only
/// compares paintings and parts is made before one that reads paths.
struct DiagramSceneShapeRun {
    let part: DiagramScenePart
    /// The run's Core Graphics paths, as they were given; empty for a run of lanes.
    private var coreGraphicsPaths: [CGPath]
    /// The lane the run's lanes are joined into; nil for a run of Core Graphics paths.
    private let runLane: DiagramPathLane?
    private var pathCount = 1
    /// The paths' bounds together, once asked, which is what a shape added must stay apart from.
    private var bounds: CGRect?

    init(path: CGPath, part: DiagramScenePart) {
        self.part = part
        coreGraphicsPaths = [path]
        runLane = nil
    }

    /// A run whose first shape is `lane`, copied into `runLane`, which is emptied first.
    init(lane: DiagramPathLane, into runLane: DiagramPathLane, part: DiagramScenePart) {
        self.part = part
        runLane.state.pointee.removeAll()
        runLane.addPath(lane)
        coreGraphicsPaths = []
        self.runLane = runLane
    }

    /// Appends the run's elements, joined as Core Graphics joins its paths, to `buffers`.
    func appendElements(to buffers: DiagramSceneRecordBuffers) {
        if let runLane { return buffers.appendElements(of: runLane) }
        guard coreGraphicsPaths.count > 1 else { return buffers.appendElements(of: coreGraphicsPaths[0]) }
        let merged = CGMutablePath()
        for path in coreGraphicsPaths { merged.addPath(path) }
        buffers.appendElements(of: merged)
    }

    // MARK: Core Graphics paths

    /// Adds `path` to a run of Core Graphics paths painted `runPainting` when it is painted alike, of the same part, in
    /// paints at full opacity, apart from the run's shapes; else leaves the run as it is and says so.
    mutating func merge(_ path: CGPath, painting: DiagramShapePainting, runPainting: DiagramShapePainting, part: DiagramScenePart) -> Bool {
        guard runLane == nil, Self.mayMerge(painting, runPainting: runPainting, part: part, runPart: self.part) else { return false }
        let runBounds = bounds ?? coreGraphicsPaths[0].boundingBoxOfPath
        let pathBounds = path.boundingBoxOfPath
        bounds = runBounds
        guard !Self.mayTouch(runBounds, pathBounds, painting: painting) else { return false }
        coreGraphicsPaths.append(path)
        pathCount += 1
        bounds = runBounds.union(pathBounds)
        return true
    }

    /// The painting of a run of one filled Core Graphics path, painted `runPainting`, made that path filled and then
    /// stroked, when `path` is that same path stroked in the same part; nil otherwise.
    func outlinedPainting(_ path: CGPath, painting: DiagramShapePainting, runPainting: DiagramShapePainting,
                          part: DiagramScenePart) -> DiagramShapePainting? {
        guard runLane == nil, pathCount == 1, let outlined = Self.outlined(runPainting, by: painting, part: part, runPart: self.part),
              coreGraphicsPaths[0] === path || coreGraphicsPaths[0] == path else { return nil }
        return outlined
    }

    // MARK: Lanes

    /// Joins `lane` into the run lane when it is painted as the run (`runPainting`), of the same part, opaque and apart
    /// from the run's shapes.
    mutating func merge(_ lane: DiagramPathLane, painting: DiagramShapePainting, runPainting: DiagramShapePainting, part: DiagramScenePart) -> Bool {
        guard let runLane, Self.mayMerge(painting, runPainting: runPainting, part: part, runPart: self.part) else { return false }
        let runBounds = bounds ?? runLane.boundsOfPath
        let laneBounds = lane.boundsOfPath
        bounds = runBounds
        guard !Self.mayTouch(runBounds, laneBounds, painting: painting) else { return false }
        runLane.addPath(lane)
        pathCount += 1
        bounds = runBounds.union(laneBounds)
        return true
    }

    /// The painting of a run of one filled lane, painted `runPainting`, made it filled and then stroked, when `lane` holds
    /// the same path, as Core Graphics compares paths (the same shape held whole, or the same elements), stroked in the
    /// same part; nil otherwise.
    func outlinedPainting(_ lane: DiagramPathLane, painting: DiagramShapePainting, runPainting: DiagramShapePainting,
                          part: DiagramScenePart) -> DiagramShapePainting? {
        guard let runLane, pathCount == 1, let outlined = Self.outlined(runPainting, by: painting, part: part, runPart: self.part),
              runLane.state.pointee.holdsSamePath(as: lane.state) else { return nil }
        return outlined
    }

    // MARK: Rules

    /// A fill in `runPart` and a stroke in the same part made one fill and stroke; nil for any other two.
    private static func outlined(_ runPainting: DiagramShapePainting, by painting: DiagramShapePainting, part: DiagramScenePart,
                                 runPart: DiagramScenePart) -> DiagramShapePainting? {
        guard part == runPart, case .fill(let fill) = runPainting, case .stroke(let paint, let stroke) = painting else { return nil }
        return .fillAndStroke(fill, paint, stroke)
    }

    private static func mayMerge(_ painting: DiagramShapePainting, runPainting: DiagramShapePainting, part: DiagramScenePart,
                                 runPart: DiagramScenePart) -> Bool {
        part == runPart && painting == runPainting && isOpaque(painting)
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

extension DiagramPathLaneState {
    /// Whether `other` holds the path this lane holds, as Core Graphics compares two paths: the same shape held whole, or
    /// the same elements, a shape held whole never equal to elements.
    mutating func holdsSamePath(as other: UnsafeMutablePointer<DiagramPathLaneState>) -> Bool {
        if holdsShape { return other.pointee.holdsShape && other.pointee.held == held }
        guard !other.pointee.holdsShape, verbCount == other.pointee.verbCount, pointCount == other.pointee.pointCount else { return false }
        let otherVerbs = other.pointee.verbs
        let otherPoints = other.pointee.points
        for index in 0..<verbCount where verbs[index] != otherVerbs[index] { return false }
        for index in 0..<pointCount where points[index] != otherPoints[index] { return false }
        return true
    }
}
