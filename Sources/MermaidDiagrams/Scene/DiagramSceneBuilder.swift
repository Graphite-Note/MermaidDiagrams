/**
 * File: DiagramSceneBuilder.swift
 * -------------------------------
 * Layer: Core
 * Description: Collects a scene's items back to front, leaving out what paints nothing, merging a shape into the one
 *              before it when both are painted alike, opaque and apart, and a fill and the stroke of its path into one;
 *              it records into the thread's blocks and makes the scene's storage once, at the end.
 *
 * Authors: Bahey Shalash
 * Version: 0.8
 * Date: 24/11/2026
 */

import CoreGraphics

/// Collects a scene's items back to front, as each diagram type's scene is made from its drawing parts. An empty path
/// or a text without lines paints nothing and is left out. A shape painted as the one just before it, of the same part,
/// in a paint at full opacity, apart from it, is merged into that one's path, so that a consumer paints as few shapes as
/// possible; the shapes of such a run are joined into one path as Core Graphics joins paths. Shapes that touch, or are
/// translucent, are not merged: where two shapes share a pixel, painting them one after the other is not painting them as
/// one. A path filled and then stroked is one shape painted both ways (`DiagramShapePainting.fillAndStroke`).
///
/// Shapes come as lanes of a workspace's recording (`init(workspace:)`), which are copied as they are added and may be
/// given back at once, or as Core Graphics paths, which are kept as they are given (each is a drawing part's finished
/// path) and read once when their run ends. A lane never joins a run of Core Graphics paths, nor a path a run of lanes.
/// Each finished shape's elements are recorded in the thread's blocks (`DiagramSceneRecordBuffers`), which the scene's
/// storage is copied from once; a builder is not copied, so that two never record into the same blocks.
struct DiagramSceneBuilder: ~Copyable {
    private let buffers: DiagramSceneRecordBuffers
    /// The lane a run of lanes is joined in, made with the builder, before any lane a drawing makes and gives back.
    private let runLane: DiagramPathLane?
    /// The shapes being merged into the last shape, not yet recorded.
    private var openRun: DiagramSceneShapeRun?

    /// A builder of Core Graphics paths alone, or also of the lanes of `workspace`'s recording, which it is made in.
    init(workspace: DiagramSceneWorkspace? = nil) {
        buffers = DiagramSceneRecordBuffers.borrow()
        runLane = workspace?.makeLane()
    }

    deinit {
        buffers.giveBack()
    }

    /// The items so far, back to front, the open run's shapes joined: a reading for tests, each shape's path made anew.
    var items: [DiagramSceneItem] {
        scene(size: .zero, font: DiagramFont(postScriptName: nil, size: 0)).items
    }

    // MARK: Core Graphics paths

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

    // MARK: Lanes

    mutating func fill(_ lane: DiagramPathLane, _ paint: DiagramPaint, part: DiagramScenePart) {
        add(lane, painting: .fill(paint), part: part)
    }

    mutating func stroke(_ lane: DiagramPathLane, _ paint: DiagramPaint, _ stroke: DiagramStroke, part: DiagramScenePart) {
        add(lane, painting: .stroke(paint, stroke), part: part)
    }

    mutating func fillAndStroke(_ lane: DiagramPathLane, fill: DiagramPaint, stroke paint: DiagramPaint, _ stroke: DiagramStroke,
                                part: DiagramScenePart) {
        add(lane, painting: .fillAndStroke(fill, paint, stroke), part: part)
    }

    mutating func fill(_ lane: DiagramPathLane, _ gradient: DiagramLinearGradient, part: DiagramScenePart) {
        add(lane, painting: .gradientFill(gradient), part: part)
    }

    // MARK: Text

    mutating func text(_ block: DiagramTextBlock?, _ paint: DiagramPaint, isBold: Bool = false, isItalic: Bool = false, isMonospaced: Bool = false,
                       rotation: CGFloat? = nil, outline: DiagramTextOutline? = nil, part: DiagramScenePart) {
        guard let block, block.lineCount > 0 else { return }
        finishRun()
        buffers.appendRecord(kind: .text, part: part, index: buffers.texts.count)
        buffers.texts.append(DiagramSceneText(block: block, paint: paint, isBold: isBold, isItalic: isItalic, isMonospaced: isMonospaced,
                                      rotation: rotation, outline: outline, part: part))
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

    // MARK: The scene

    /// The scene of everything added so far, the open run's shapes joined; the builder may go on.
    func scene(size: CGSize, font: DiagramFont, seriesColors: DiagramSeriesColors = .none) -> DiagramScene {
        guard let openRun else { return buffers.makeScene(size: size, font: font, seriesColors: seriesColors) }
        let counts = buffers.counts
        defer {
            buffers.rollBack(to: counts)
            buffers.paintings.removeLast()
        }
        buffers.appendRecord(kind: .shape, part: openRun.part, index: buffers.paintings.count)
        openRun.appendElements(to: buffers)
        buffers.paintings.append(openRun.painting)
        return buffers.makeScene(size: size, font: font, seriesColors: seriesColors)
    }

    /// `path` merged into the open run, or made the outline of its one filled path, or else the start of a new run.
    private mutating func add(_ path: CGPath, painting: DiagramShapePainting, part: DiagramScenePart) {
        guard !path.isEmpty else { return }
        if openRun?.outline(path, painting: painting, part: part) == true || openRun?.merge(path, painting: painting, part: part) == true { return }
        finishRun()
        openRun = DiagramSceneShapeRun(path: path, painting: painting, part: part)
    }

    /// `lane` merged into the open run, or made the outline of its one filled path, or else copied as the start of a new run.
    private mutating func add(_ lane: DiagramPathLane, painting: DiagramShapePainting, part: DiagramScenePart) {
        guard !lane.isEmpty else { return }
        if openRun?.outline(lane, painting: painting, part: part) == true || openRun?.merge(lane, painting: painting, part: part) == true { return }
        finishRun()
        guard let runLane else { preconditionFailure("lanes are added to a builder made with their workspace") }
        openRun = DiagramSceneShapeRun(lane: lane, into: runLane, painting: painting, part: part)
    }

    /// The open run recorded as one shape, after the items before it.
    private mutating func finishRun() {
        guard let openRun else { return }
        buffers.appendRecord(kind: .shape, part: openRun.part, index: buffers.paintings.count)
        openRun.appendElements(to: buffers)
        buffers.paintings.append(openRun.painting)
        self.openRun = nil
    }
}
