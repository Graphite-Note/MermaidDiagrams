/**
 * File: ScratchList.swift
 * -----------------------
 * Layer: Core
 * Description: A list of plain values that grows inside a scratch arena, for work whose length is found as it goes.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

/// A list in a `DiagramScratchArena`: values appended until its room is full move to room twice as large in the same
/// arena (the old room stays taken until the arena is released past it), so a list never traps for want of room and
/// never allocates on its own. One owner appends to a list: a copy of it shares its values but not its count, so a list
/// is passed `inout` or read through `elements`. Valid until the arena is released past it.
struct ScratchList<Element: BitwiseCopyable>: RandomAccessCollection {
    private var storage: ScratchSpan<Element>
    private(set) var count = 0
    private let arena: DiagramScratchArena

    init(storage: ScratchSpan<Element>, arena: DiagramScratchArena) {
        self.storage = storage
        self.arena = arena
    }

    var startIndex: Int { 0 }
    var endIndex: Int { count }
    var capacity: Int { storage.count }

    @inline(__always)
    subscript(index: Int) -> Element {
        unsafeAddress {
            precondition(index >= 0 && index < count, "Index out of range of a scratch list")
            return UnsafePointer(storage.start + index)
        }
        nonmutating unsafeMutableAddress {
            precondition(index >= 0 && index < count, "Index out of range of a scratch list")
            return storage.start + index
        }
    }

    /// The values the list holds now, as a span over its room: valid until the list next grows.
    var elements: ScratchSpan<Element> { ScratchSpan(start: storage.start, count: count) }

    @inline(__always)
    mutating func append(_ element: Element) {
        if count == storage.count { grow(toHold: count + 1) }
        (storage.start + count).initialize(to: element)
        count += 1
    }

    /// Appends every value of `span`.
    mutating func append(contentsOf span: ScratchSpan<Element>) {
        if count + span.count > storage.count { grow(toHold: count + span.count) }
        (storage.start + count).update(from: span.start, count: span.count)
        count += span.count
    }

    @inline(__always)
    mutating func removeLast() -> Element {
        precondition(count > 0, "Removing the last value of an empty scratch list")
        count -= 1
        return storage[count]
    }

    @inline(__always)
    mutating func popLast() -> Element? {
        guard count > 0 else { return nil }
        count -= 1
        return storage[count]
    }

    /// Empties the list, keeping its room.
    @inline(__always)
    mutating func removeAll() { count = 0 }

    /// Room for `capacity` values without growing.
    mutating func reserveCapacity(_ capacity: Int) {
        if capacity > storage.count { grow(toHold: capacity) }
    }

    private mutating func grow(toHold needed: Int) {
        let grown: ScratchSpan<Element> = arena.uninitializedSpan(count: Swift.max(needed, 2 * storage.count, 8))
        grown.start.update(from: storage.start, count: count)
        storage = grown
    }
}

extension ScratchList where Element == Int {
    /// Appends the integers of `range`, in order.
    mutating func append(contentsOf range: Range<Int>) {
        reserveCapacity(count + range.count)
        for value in range { append(value) }
    }
}
