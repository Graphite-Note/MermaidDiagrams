/**
 * File: LayeredScratchArena.swift
 * -------------------------------
 * Layer: Core (redesign prototype)
 * Description: One block of scratch memory a layout takes its working lists from, reset after each layout and kept
 *              from one layout to the next, so that a layout in steady state allocates nothing and counts no references.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

/// A run of `count` elements in an arena: a pointer and a count, copied freely, counting no references. It is valid
/// until its arena is reset; the arena's owner never lets one outlive the layout that took it.
struct ScratchSpan<Element: BitwiseCopyable> {
    let base: UnsafeMutablePointer<Element>
    let count: Int

    @inline(__always) subscript(index: Int) -> Element {
        get { base[index] }
        nonmutating set { base[index] = newValue }
    }

    @inline(__always) func fill(_ value: Element) { base.update(repeating: value, count: count) }
}

/// A list that grows within the room an arena gave it (`capacity`), never past it.
struct ScratchList<Element: BitwiseCopyable> {
    let base: UnsafeMutablePointer<Element>
    let capacity: Int
    var count = 0

    @inline(__always) subscript(index: Int) -> Element {
        get { base[index] }
        nonmutating set { base[index] = newValue }
    }

    @inline(__always) mutating func append(_ element: Element) {
        precondition(count < capacity, "a scratch list grew past the room it was given")
        base[count] = element
        count += 1
    }

    @inline(__always) mutating func removeLast() -> Element {
        count -= 1
        return base[count]
    }
}

/// The arena: chunks of raw memory handed out from the front. When a layout needs more than the present chunk holds,
/// a new chunk is added (the old ones stay valid until reset); at reset, chunks beyond the first are freed and the
/// first is made as large as the layout's high-water mark, so the next layout of that size takes one chunk and no
/// allocation. A chunk larger than `retainedLimit` bytes is not kept past the layout that needed it.
final class LayeredScratchArena {
    private var chunks: [(base: UnsafeMutableRawPointer, size: Int)] = []
    private var current: UnsafeMutableRawPointer
    private var currentSize: Int
    private var used = 0
    private var highWater = 0
    private var usedBeforeCurrent = 0
    static let retainedLimit = 4 << 20

    init(initialSize: Int = 64 << 10) {
        current = UnsafeMutableRawPointer.allocate(byteCount: initialSize, alignment: 16)
        currentSize = initialSize
        chunks.reserveCapacity(8)
        chunks.append((current, initialSize))
    }

    deinit { for chunk in chunks { chunk.base.deallocate() } }

    @inline(__always) private func bytes(_ byteCount: Int) -> UnsafeMutableRawPointer {
        let aligned = (used + 15) & ~15
        if aligned + byteCount <= currentSize {
            used = aligned + byteCount
            return current + aligned
        }
        return grow(byteCount)
    }

    private func grow(_ byteCount: Int) -> UnsafeMutableRawPointer {
        usedBeforeCurrent += used
        let size = max(byteCount, currentSize * 2)
        current = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 16)
        currentSize = size
        chunks.append((current, size))
        used = byteCount
        return current
    }

    func span<Element: BitwiseCopyable>(_ count: Int, repeating value: Element) -> ScratchSpan<Element> {
        let pointer = bytes(count * MemoryLayout<Element>.stride).bindMemory(to: Element.self, capacity: count)
        pointer.initialize(repeating: value, count: count)
        return ScratchSpan(base: pointer, count: count)
    }

    func list<Element: BitwiseCopyable>(capacity: Int, of type: Element.Type = Element.self) -> ScratchList<Element> {
        let pointer = bytes(capacity * MemoryLayout<Element>.stride).bindMemory(to: Element.self, capacity: capacity)
        return ScratchList(base: pointer, capacity: capacity)
    }

    /// Frees everything taken since the last reset.
    func reset() {
        highWater = max(highWater, usedBeforeCurrent + used)
        if chunks.count > 1 || currentSize > Self.retainedLimit {
            for chunk in chunks { chunk.base.deallocate() }
            chunks.removeAll(keepingCapacity: true)
            let size = min(max(highWater + highWater / 4, 64 << 10), max(Self.retainedLimit, 64 << 10))
            current = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 16)
            currentSize = size
            chunks.append((current, size))
            if highWater > Self.retainedLimit { highWater = 0 }
        }
        used = 0
        usedBeforeCurrent = 0
    }
}
