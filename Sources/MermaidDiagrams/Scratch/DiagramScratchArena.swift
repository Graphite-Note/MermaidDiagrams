/**
 * File: DiagramScratchArena.swift
 * -------------------------------
 * Layer: Core
 * Description: One reusable region of working memory per thread, handed out in spans and lists of plain values and
 *              taken back all at once, so that a layout's working lists cost no allocation and no reference counting.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import Foundation

/// Working memory handed out by moving a cursor through chunks of bytes, and taken back by moving it back: to a mark
/// taken earlier (`release(to:)`), or to the start (`reset()`). A chunk is never moved, so a span taken from the arena
/// stays valid while more is taken; growth adds a chunk. Only plain values (`BitwiseCopyable`) live here: nothing is
/// retained, initialized or destroyed, and taking memory back is setting the cursor.
///
/// Each thread has its own arena (`withCurrentThread`), so no lock is needed; a call made from within another on the same
/// thread (an agent flow laying a flowchart out, a narrow fitting) takes a mark and gives back only what it took. After
/// the outermost call the arena keeps at most `retainedByteLimit` bytes of chunks and frees the rest, so a large graph
/// does not leave its memory behind; `releaseCurrentThreadArena()` frees all of it, for a host short of memory.
final class DiagramScratchArena {
    /// The most bytes of chunks an arena keeps between two outermost uses.
    static let retainedByteLimit = 256 * 1024
    /// The size of an arena's first chunk; each later chunk is at least twice the size of the one before it.
    static let firstChunkByteCount = 16 * 1024
    /// Every allocation starts at a multiple of this, enough for any plain value the layouts keep.
    static let alignment = 16

    /// A chunk of bytes, allocated once and freed when the arena trims or goes away.
    private struct Chunk {
        let start: UnsafeMutableRawPointer
        let byteCount: Int
    }

    private var chunks: [Chunk] = []
    /// The chunk the cursor is in, and the cursor and the end of that chunk.
    private var chunkIndex = 0
    private var cursor: UnsafeMutableRawPointer
    private var chunkEnd: UnsafeMutableRawPointer
    /// How many calls of `withCurrentThread` are running on this arena.
    private var depth = 0

    init() {
        let first = Chunk(start: Self.allocateChunk(byteCount: Self.firstChunkByteCount), byteCount: Self.firstChunkByteCount)
        chunks.append(first)
        cursor = first.start
        chunkEnd = first.start + first.byteCount
    }

    deinit {
        for chunk in chunks { chunk.start.deallocate() }
    }

    /// The bytes of every chunk the arena holds now.
    var heldByteCount: Int { chunks.reduce(0) { total, chunk in total + chunk.byteCount } }

    /// How many chunks the arena holds now.
    var chunkCount: Int { chunks.count }

    private static func allocateChunk(byteCount: Int) -> UnsafeMutableRawPointer {
        UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: alignment)
    }

    /// `byteCount` bytes, aligned to `alignment`, valid until the arena is released past them.
    @inline(__always)
    func allocate(byteCount: Int) -> UnsafeMutableRawPointer {
        let misalignment = Int(bitPattern: cursor) & (Self.alignment - 1)
        let start = misalignment == 0 ? cursor : cursor + (Self.alignment - misalignment)
        if byteCount <= chunkEnd - start {
            cursor = start + byteCount
            return start
        }
        return allocateInNextChunk(byteCount: byteCount)
    }

    /// Moves the cursor to the next chunk that holds `byteCount` bytes, freeing kept chunks too small on the way and
    /// adding a chunk when none is left.
    private func allocateInNextChunk(byteCount: Int) -> UnsafeMutableRawPointer {
        while chunkIndex + 1 < chunks.count && chunks[chunkIndex + 1].byteCount < byteCount {
            chunks[chunkIndex + 1].start.deallocate()
            chunks.remove(at: chunkIndex + 1)
        }
        if chunkIndex + 1 == chunks.count {
            let size = max(byteCount, 2 * chunks[chunkIndex].byteCount)
            chunks.append(Chunk(start: Self.allocateChunk(byteCount: size), byteCount: size))
        }
        chunkIndex += 1
        let chunk = chunks[chunkIndex]
        cursor = chunk.start + byteCount
        chunkEnd = chunk.start + chunk.byteCount
        return chunk.start
    }

    /// Room for `count` values of `Element`, holding whatever was there before.
    @inline(__always)
    func uninitializedSpan<Element: BitwiseCopyable>(count: Int) -> ScratchSpan<Element> {
        precondition(count >= 0, "A span cannot hold a negative count")
        let (byteCount, overflow) = MemoryLayout<Element>.stride.multipliedReportingOverflow(by: count)
        precondition(!overflow, "A span this long does not fit in memory")
        let start = allocate(byteCount: byteCount)
        return ScratchSpan(start: start.bindMemory(to: Element.self, capacity: count), count: count)
    }

    /// `count` values, each `value`.
    @inline(__always)
    func span<Element: BitwiseCopyable>(count: Int, repeating value: Element) -> ScratchSpan<Element> {
        let span: ScratchSpan<Element> = uninitializedSpan(count: count)
        span.fill(with: value)
        return span
    }

    /// A span of its own holding what `span` holds.
    @inline(__always)
    func copy<Element: BitwiseCopyable>(of span: ScratchSpan<Element>) -> ScratchSpan<Element> {
        let copy: ScratchSpan<Element> = uninitializedSpan(count: span.count)
        copy.copyElements(from: span)
        return copy
    }

    /// An empty list with room for `capacity` values before it grows.
    @inline(__always)
    func list<Element: BitwiseCopyable>(capacity: Int, of elementType: Element.Type = Element.self) -> ScratchList<Element> {
        ScratchList(storage: uninitializedSpan(count: max(capacity, 0)), arena: self)
    }

    /// Where the cursor is now, to give back later everything taken after it.
    struct Mark {
        fileprivate let chunkIndex: Int
        fileprivate let cursor: UnsafeMutableRawPointer
    }

    func mark() -> Mark { Mark(chunkIndex: chunkIndex, cursor: cursor) }

    /// Gives back everything taken since `mark`: the spans and lists taken after it must no longer be used. The chunks
    /// stay, to be used again.
    func release(to mark: Mark) {
        #if DEBUG
        poisonFreedBytes(from: mark)
        #endif
        chunkIndex = mark.chunkIndex
        cursor = mark.cursor
        chunkEnd = chunks[chunkIndex].start + chunks[chunkIndex].byteCount
    }

    /// Gives back everything, and frees the chunks beyond the first ones that together hold at most
    /// `retainedByteLimit` bytes; the first chunk is always kept.
    func reset() {
        release(to: Mark(chunkIndex: 0, cursor: chunks[0].start))
        var kept = chunks[0].byteCount
        var keptCount = 1
        while keptCount < chunks.count && kept + chunks[keptCount].byteCount <= Self.retainedByteLimit {
            kept += chunks[keptCount].byteCount
            keptCount += 1
        }
        for chunk in chunks[keptCount...] { chunk.start.deallocate() }
        chunks.removeSubrange(keptCount...)
    }

    /// Frees every chunk but the first, which shrinks back to its first size.
    fileprivate func releaseMemory() {
        for chunk in chunks { chunk.start.deallocate() }
        chunks.removeAll()
        let first = Chunk(start: Self.allocateChunk(byteCount: Self.firstChunkByteCount), byteCount: Self.firstChunkByteCount)
        chunks.append(first)
        chunkIndex = 0
        cursor = first.start
        chunkEnd = first.start + first.byteCount
    }

    #if DEBUG
    /// Fills the bytes `release(to:)` gives back with a pattern, so that a span read after its release reads nonsense
    /// in tests instead of the numbers it held.
    private func poisonFreedBytes(from mark: Mark) {
        var index = mark.chunkIndex
        var start = mark.cursor
        while index <= chunkIndex {
            let end = index == chunkIndex ? cursor : chunks[index].start + chunks[index].byteCount
            if end > start { start.initializeMemory(as: UInt8.self, repeating: 0xA5, count: end - start) }
            index += 1
            if index < chunks.count { start = chunks[index].start }
        }
    }
    #endif

    /// Runs `body` with the calling thread's arena, and gives back what `body` took: everything, trimming the arena,
    /// when no other call is running on this thread; else everything taken since this call began. Nothing `body`
    /// took from the arena may be used after it returns.
    @inline(__always)
    static func withCurrentThread<Result>(_ body: (DiagramScratchArena) throws -> Result) rethrows -> Result {
        let arena = current
        let start = arena.mark()
        arena.depth += 1
        defer {
            arena.depth -= 1
            if arena.depth == 0 { arena.reset() } else { arena.release(to: start) }
        }
        return try body(arena)
    }

    /// Frees the memory the calling thread's arena keeps, all but one small chunk; nothing happens while a call of
    /// `withCurrentThread` is running on this thread. For a host told that memory is short: preparing never needs it.
    static func releaseCurrentThreadArena() {
        guard let arena = existingCurrent, arena.depth == 0 else { return }
        arena.releaseMemory()
    }

    /// The calling thread's arena, made the first time.
    static var current: DiagramScratchArena {
        if let arena = existingCurrent { return arena }
        let arena = DiagramScratchArena()
        pthread_setspecific(DiagramScratchArenaThreadKey.key, Unmanaged.passRetained(arena).toOpaque())
        return arena
    }

    private static var existingCurrent: DiagramScratchArena? {
        guard let pointer = pthread_getspecific(DiagramScratchArenaThreadKey.key) else { return nil }
        return Unmanaged<DiagramScratchArena>.fromOpaque(pointer).takeUnretainedValue()
    }
}

/// The key of each thread's arena, whose destructor frees it when its thread ends.
private enum DiagramScratchArenaThreadKey {
    static let key: pthread_key_t = {
        var key = pthread_key_t()
        let status = pthread_key_create(&key) { pointer in
            Unmanaged<DiagramScratchArena>.fromOpaque(pointer).release()
        }
        precondition(status == 0, "No thread key is left for the scratch arena")
        return key
    }()
}
