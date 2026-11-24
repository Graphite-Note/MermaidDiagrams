/**
 * File: DiagramTextScratchList.swift
 * ----------------------------------
 * Layer: Core
 * Description: A growing list of plain values that a thread's text measuring keeps and reuses, emptied by setting its
 *              count, with no reference counting, no copy on write and no exclusivity check.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

/// A list of plain values in memory it owns: appending checks only its room, emptying it keeps its memory. It is held
/// by one owner (a thread's `DiagramTextThreadState`, which frees it) and moved, never copied: a copy would share the
/// memory.
struct DiagramTextScratchList<Element: BitwiseCopyable> {
    private(set) var start: UnsafeMutablePointer<Element>
    private(set) var count = 0
    private var capacity: Int

    init(capacity: Int = 16) {
        self.capacity = max(capacity, 1)
        start = .allocate(capacity: self.capacity)
    }

    /// Frees the memory; the list must not be used after.
    func free() {
        start.deallocate()
    }

    var isEmpty: Bool { count == 0 }

    var last: Element? { count > 0 ? start[count - 1] : nil }

    @inline(__always)
    subscript(index: Int) -> Element {
        get { start[index] }
        nonmutating set { start[index] = newValue }
    }

    @inline(__always)
    mutating func append(_ element: Element) {
        if count == capacity { grow(to: capacity * 2) }
        start[count] = element
        count += 1
    }

    mutating func append(contentsOf elements: UnsafeBufferPointer<Element>) {
        guard let source = elements.baseAddress, !elements.isEmpty else { return }
        if count + elements.count > capacity { grow(to: max(capacity * 2, count + elements.count)) }
        (start + count).update(from: source, count: elements.count)
        count += elements.count
    }

    /// Room for `count` values in all, so that pointers into the list stay valid while it is filled to that.
    mutating func reserveCapacity(_ count: Int) {
        if count > capacity { grow(to: count) }
    }

    mutating func removeLast() {
        count -= 1
    }

    mutating func removeAll() {
        count = 0
    }

    /// The values as a buffer, valid until the list grows.
    var buffer: UnsafeBufferPointer<Element> {
        UnsafeBufferPointer(start: start, count: count)
    }

    private mutating func grow(to newCapacity: Int) {
        let grown = UnsafeMutablePointer<Element>.allocate(capacity: newCapacity)
        grown.update(from: start, count: count)
        start.deallocate()
        start = grown
        capacity = newCapacity
    }
}
