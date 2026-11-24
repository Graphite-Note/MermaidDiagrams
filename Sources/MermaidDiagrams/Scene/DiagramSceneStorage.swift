/**
 * File: DiagramSceneStorage.swift
 * -------------------------------
 * Layer: Core
 * Description: What a scene paints, in one block of memory made once: a small record for each item back to front, then
 *              the points and the verbs of every shape's path, as Core Graphics gives a path's elements out.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics

/// Whether an item of a scene is a shape or a text.
enum DiagramSceneItemKind: UInt8, Sendable {
    case shape
    case text
}

/// One item of a scene, 16 bytes. A shape's elements are the verbs from `firstVerb` to the next record's (or to the end),
/// its points from `firstPoint`; a text's record keeps the counts where it lies, so that the shapes on either side are
/// bounded alike.
struct DiagramSceneItemRecord: Sendable {
    var firstVerb: Int32
    var firstPoint: Int32
    /// A shape's painting in the scene's paintings, a text's place in its texts.
    var index: Int32
    var kind: DiagramSceneItemKind
    var part: DiagramScenePart
}

/// The counts of a storage's three regions.
struct DiagramSceneStorageHeader: Sendable {
    var itemCount: Int
    var verbCount: Int
    var pointCount: Int
}

/// The unit the storage's block is counted in: 16 bytes, the size of a record and of a point.
struct DiagramSceneStorageWord {
    var low: UInt64
    var high: UInt64
}

/// The records, points and verbs of a scene in one allocation that nothing changes once made, so that a scene is handed
/// from the thread that made it to the threads that paint and write it (hence sendable: it is only read). Points follow
/// the records, verbs the points.
struct DiagramSceneStorage: @unchecked Sendable {
    private let block: ManagedBuffer<DiagramSceneStorageHeader, DiagramSceneStorageWord>

    /// A storage with room for exactly these counts, its regions bound to their types and left for `fill` to write.
    static func make(itemCount: Int, verbCount: Int, pointCount: Int,
                     fill: (DiagramSceneStorageContents) -> Void) -> DiagramSceneStorage {
        let verbWords = (verbCount + MemoryLayout<DiagramSceneStorageWord>.stride - 1) / MemoryLayout<DiagramSceneStorageWord>.stride
        let block = ManagedBuffer<DiagramSceneStorageHeader, DiagramSceneStorageWord>.create(minimumCapacity: itemCount + pointCount + verbWords) { _ in
            DiagramSceneStorageHeader(itemCount: itemCount, verbCount: verbCount, pointCount: pointCount)
        }
        block.withUnsafeMutablePointerToElements { words in
            let block = UnsafeMutableRawPointer(words)
            let records = block.bindMemory(to: DiagramSceneItemRecord.self, capacity: itemCount)
            let points = (block + itemCount * MemoryLayout<DiagramSceneStorageWord>.stride).bindMemory(to: CGPoint.self, capacity: pointCount)
            let verbs = (block + (itemCount + pointCount) * MemoryLayout<DiagramSceneStorageWord>.stride)
                .bindMemory(to: DiagramPathVerb.self, capacity: verbCount)
            fill(DiagramSceneStorageContents(records: records, points: points, verbs: verbs, itemCount: itemCount, verbCount: verbCount))
        }
        return DiagramSceneStorage(block: block)
    }

    /// Calls `body` with the storage's regions, valid only inside it.
    @inline(__always)
    func withContents<Result>(_ body: (DiagramSceneStorageContents) throws -> Result) rethrows -> Result {
        try block.withUnsafeMutablePointers { header, words in
            let block = UnsafeMutableRawPointer(words)
            let counts = header.pointee
            let stride = MemoryLayout<DiagramSceneStorageWord>.stride
            return try body(DiagramSceneStorageContents(
                records: block.assumingMemoryBound(to: DiagramSceneItemRecord.self),
                points: (block + counts.itemCount * stride).assumingMemoryBound(to: CGPoint.self),
                verbs: (block + (counts.itemCount + counts.pointCount) * stride).assumingMemoryBound(to: DiagramPathVerb.self),
                itemCount: counts.itemCount, verbCount: counts.verbCount))
        }
    }

    var itemCount: Int { block.header.itemCount }
}

/// The regions of a scene's storage: its records, its points and its verbs.
struct DiagramSceneStorageContents {
    let records: UnsafeMutablePointer<DiagramSceneItemRecord>
    let points: UnsafeMutablePointer<CGPoint>
    let verbs: UnsafeMutablePointer<DiagramPathVerb>
    let itemCount: Int
    let verbCount: Int

    /// The verbs of the shape at `index`: from its record's first to the next record's, or to the end.
    @inline(__always)
    func verbRange(ofItemAt index: Int) -> Range<Int> {
        let start = Int(records[index].firstVerb)
        let end = index + 1 < itemCount ? Int(records[index + 1].firstVerb) : verbCount
        return start..<end
    }

    /// Calls `body` with each element of the shape at `index` and its points, as Core Graphics gives them out.
    @inline(__always)
    func forEachElement(ofItemAt index: Int, _ body: (DiagramPathVerb, UnsafePointer<CGPoint>) throws -> Void) rethrows {
        var point = UnsafePointer(points + Int(records[index].firstPoint))
        for verbIndex in verbRange(ofItemAt: index) {
            let verb = verbs[verbIndex]
            try body(verb, point)
            point += verb.pointCount
        }
    }

    /// A Core Graphics path of the shape at `index`'s elements, for a reader that needs one. A move after a move, which
    /// `move(to:)` would put in its place, is added as a path of its own, as Core Graphics copies one.
    func makePath(ofItemAt index: Int) -> CGMutablePath {
        let path = CGMutablePath()
        var lastVerb: DiagramPathVerb?
        forEachElement(ofItemAt: index) { verb, elementPoints in
            defer { lastVerb = verb }
            switch verb {
            case .move where lastVerb == .move:
                let lone = CGMutablePath()
                lone.move(to: elementPoints[0])
                path.addPath(lone)
            case .move: path.move(to: elementPoints[0])
            case .line: path.addLine(to: elementPoints[0])
            case .quadraticCurve: path.addQuadCurve(to: elementPoints[1], control: elementPoints[0])
            case .cubicCurve: path.addCurve(to: elementPoints[2], control1: elementPoints[0], control2: elementPoints[1])
            case .close: path.closeSubpath()
            }
        }
        return path
    }
}
