/**
 * File: DiagramSceneRecordBuffers.swift
 * -------------------------------------
 * Layer: Core
 * Description: The blocks a scene builder records its items' records, verbs and points into, kept by each thread between
 *              scenes, then copied once into the scene's own storage; a builder begun while another of the same thread
 *              records gets blocks of its own, and blocks grown past a mebibyte are freed.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
import Darwin

/// A builder's records, verbs and points as they are recorded, in blocks that grow and that the thread keeps
/// (`borrow()`), so that a thread making scene after scene allocates nothing here once its blocks have grown. A shape's
/// elements are appended as Core Graphics gives them out; `makeStorage` copies everything into the scene's storage.
final class DiagramSceneRecordBuffers {
    private(set) var records: UnsafeMutablePointer<DiagramSceneItemRecord>
    private(set) var verbs: UnsafeMutablePointer<DiagramPathVerb>
    private(set) var points: UnsafeMutablePointer<CGPoint>
    private(set) var recordCount = 0
    private(set) var verbCount = 0
    private(set) var pointCount = 0
    private var recordCapacity: Int
    private var verbCapacity: Int
    private var pointCapacity: Int
    /// Whether a builder holds the blocks.
    private var isBorrowed = false

    /// The most bytes a thread's blocks keep between scenes.
    static let largestKeptByteCount = 1 << 20
    private static let smallCapacity = 64

    init() {
        recordCapacity = Self.smallCapacity
        verbCapacity = Self.smallCapacity * 2
        pointCapacity = Self.smallCapacity * 4
        records = .allocate(capacity: recordCapacity)
        verbs = .allocate(capacity: verbCapacity)
        points = .allocate(capacity: pointCapacity)
    }

    deinit {
        records.deallocate()
        verbs.deallocate()
        points.deallocate()
    }

    // MARK: The thread's blocks

    private static let threadKey: pthread_key_t = {
        var key = pthread_key_t()
        pthread_key_create(&key) { buffers in Unmanaged<DiagramSceneRecordBuffers>.fromOpaque(buffers).release() }
        return key
    }()

    /// The calling thread's blocks, emptied, or blocks of their own when a builder of this thread holds the thread's.
    static func borrow() -> DiagramSceneRecordBuffers {
        let buffers: DiagramSceneRecordBuffers
        if let stored = pthread_getspecific(threadKey) {
            buffers = Unmanaged<DiagramSceneRecordBuffers>.fromOpaque(stored).takeUnretainedValue()
        } else {
            buffers = DiagramSceneRecordBuffers()
            pthread_setspecific(threadKey, Unmanaged.passRetained(buffers).toOpaque())
        }
        guard !buffers.isBorrowed else { return DiagramSceneRecordBuffers() }
        buffers.isBorrowed = true
        buffers.trimIfLarge()
        buffers.removeAll()
        return buffers
    }

    /// Hands the blocks back to their thread when the builder holding them ends.
    func giveBack() {
        isBorrowed = false
    }

    func removeAll() {
        recordCount = 0
        verbCount = 0
        pointCount = 0
    }

    /// The counts, which `rollBack(to:)` returns to after something was recorded for a moment.
    var counts: (records: Int, verbs: Int, points: Int) { (recordCount, verbCount, pointCount) }

    func rollBack(to counts: (records: Int, verbs: Int, points: Int)) {
        recordCount = counts.records
        verbCount = counts.verbs
        pointCount = counts.points
    }

    // MARK: Recording

    /// A record of the next item: a shape whose elements are appended next, or a text.
    func appendRecord(kind: DiagramSceneItemKind, part: DiagramScenePart, index: Int) {
        if recordCount == recordCapacity { growRecords() }
        records[recordCount] = DiagramSceneItemRecord(firstVerb: Int32(truncatingIfNeeded: verbCount), firstPoint: Int32(truncatingIfNeeded: pointCount),
                                                      index: Int32(truncatingIfNeeded: index), kind: kind, part: part)
        recordCount &+= 1
    }

    /// One element and its points.
    @inline(__always)
    func append(_ verb: DiagramPathVerb, _ elementPoints: UnsafePointer<CGPoint>) {
        let count = verb.pointCount
        if verbCapacity == verbCount || pointCapacity &- pointCount < count { grow(verbs: 1, points: count) }
        verbs[verbCount] = verb
        verbCount &+= 1
        for index in 0..<count { points[pointCount &+ index] = elementPoints[index] }
        pointCount &+= count
    }

    /// Elements given as blocks, copied at once.
    func append(verbs addedVerbs: UnsafePointer<DiagramPathVerb>, verbCount addedVerbCount: Int, points addedPoints: UnsafePointer<CGPoint>,
                pointCount addedPointCount: Int) {
        if verbCapacity &- verbCount < addedVerbCount || pointCapacity &- pointCount < addedPointCount {
            grow(verbs: addedVerbCount, points: addedPointCount)
        }
        (verbs + verbCount).initialize(from: addedVerbs, count: addedVerbCount)
        (points + pointCount).initialize(from: addedPoints, count: addedPointCount)
        verbCount &+= addedVerbCount
        pointCount &+= addedPointCount
    }

    /// A Core Graphics path's elements as it gives them out (`CGPathApply`), through a C function that appends each one.
    func appendElements(of path: CGPath) {
        path.apply(info: Unmanaged.passUnretained(self).toOpaque()) { info, element in
            let buffers = Unmanaged<DiagramSceneRecordBuffers>.fromOpaque(info.unsafelyUnwrapped).takeUnretainedValue()
            let verb: DiagramPathVerb
            switch element.pointee.type {
            case .moveToPoint: verb = .move
            case .addLineToPoint: verb = .line
            case .addQuadCurveToPoint: verb = .quadraticCurve
            case .addCurveToPoint: verb = .cubicCurve
            case .closeSubpath: verb = .close
            @unknown default: return
            }
            buffers.append(verb, UnsafePointer(element.pointee.points))
        }
    }

    /// A lane's elements as it gives them out.
    func appendElements(of lane: DiagramPathLane) {
        let state = lane.state
        guard state.pointee.held == nil else { return lane.forEachElement { verb, elementPoints in append(verb, elementPoints) } }
        append(verbs: state.pointee.verbs, verbCount: state.pointee.verbCount, points: state.pointee.points, pointCount: state.pointee.pointCount)
    }

    // MARK: Storage

    /// A scene's storage holding everything recorded.
    func makeStorage() -> DiagramSceneStorage {
        DiagramSceneStorage.make(itemCount: recordCount, verbCount: verbCount, pointCount: pointCount) { contents in
            contents.records.initialize(from: records, count: recordCount)
            contents.verbs.initialize(from: verbs, count: verbCount)
            contents.points.initialize(from: points, count: pointCount)
        }
    }

    // MARK: Room

    private func growRecords() {
        let grown = recordCapacity * 2
        let block = UnsafeMutablePointer<DiagramSceneItemRecord>.allocate(capacity: grown)
        block.initialize(from: records, count: recordCount)
        records.deallocate()
        records = block
        recordCapacity = grown
    }

    @inline(never)
    private func grow(verbs addedVerbs: Int, points addedPoints: Int) {
        if verbCapacity - verbCount < addedVerbs {
            let grown = max(verbCapacity * 2, verbCount + addedVerbs)
            let block = UnsafeMutablePointer<DiagramPathVerb>.allocate(capacity: grown)
            block.initialize(from: verbs, count: verbCount)
            verbs.deallocate()
            verbs = block
            verbCapacity = grown
        }
        if pointCapacity - pointCount < addedPoints {
            let grown = max(pointCapacity * 2, pointCount + addedPoints)
            let block = UnsafeMutablePointer<CGPoint>.allocate(capacity: grown)
            block.initialize(from: points, count: pointCount)
            points.deallocate()
            points = block
            pointCapacity = grown
        }
    }

    /// The bytes the blocks take.
    var capacityByteCount: Int {
        recordCapacity * MemoryLayout<DiagramSceneItemRecord>.stride + verbCapacity + pointCapacity * MemoryLayout<CGPoint>.stride
    }

    /// Frees blocks a large scene grew and starts again from small ones.
    private func trimIfLarge() {
        guard capacityByteCount > Self.largestKeptByteCount else { return }
        records.deallocate()
        verbs.deallocate()
        points.deallocate()
        recordCapacity = Self.smallCapacity
        verbCapacity = Self.smallCapacity * 2
        pointCapacity = Self.smallCapacity * 4
        records = .allocate(capacity: recordCapacity)
        verbs = .allocate(capacity: verbCapacity)
        points = .allocate(capacity: pointCapacity)
    }
}

/// Copies a host's items into a scene as they are, each shape's path read once and none merged
/// (`DiagramScene.init(size:font:items:seriesColors:)`).
struct DiagramSceneItemCopying: ~Copyable {
    private let buffers = DiagramSceneRecordBuffers.borrow()
    private var paintings: [DiagramShapePainting] = []
    private var texts: [DiagramSceneText] = []

    deinit {
        buffers.giveBack()
    }

    mutating func add(_ item: DiagramSceneItem) {
        switch item {
        case .shape(let shape):
            buffers.appendRecord(kind: .shape, part: shape.part, index: paintings.count)
            buffers.appendElements(of: shape.path)
            paintings.append(shape.painting)
        case .text(let text):
            buffers.appendRecord(kind: .text, part: text.part, index: texts.count)
            texts.append(text)
        }
    }

    func scene(size: CGSize, font: DiagramFont, seriesColors: DiagramSeriesColors) -> DiagramScene {
        DiagramScene(size: size, font: font, seriesColors: seriesColors, storage: buffers.makeStorage(), paintings: paintings, texts: texts)
    }
}
