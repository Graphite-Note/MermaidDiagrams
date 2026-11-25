/**
 * File: ScratchSpan.swift
 * -----------------------
 * Layer: Core
 * Description: A fixed run of plain values in a scratch arena, read and written in place through any copy of it.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

/// `count` plain values one after another in memory a `DiagramScratchArena` handed out. A span is a view: its copies
/// all see and change the same values, so it is passed and kept freely, with no copy on write and no reference
/// counting, and changed through a `let` (its setter does not mutate the span itself). Where code relied on an array
/// staying as it was while another copy changed, it takes `DiagramScratchArena.copy(of:)` instead. A span is valid
/// until the arena is released past it. Every index is checked, as an array's is.
struct ScratchSpan<Element: BitwiseCopyable>: RandomAccessCollection {
    let start: UnsafeMutablePointer<Element>
    let count: Int

    init(start: UnsafeMutablePointer<Element>, count: Int) {
        self.start = start
        self.count = count
    }

    /// A span of no values, for a list not made yet.
    static var empty: ScratchSpan<Element> {
        ScratchSpan(start: UnsafeMutablePointer(bitPattern: MemoryLayout<Element>.alignment).unsafelyUnwrapped, count: 0)
    }

    var startIndex: Int { 0 }
    var endIndex: Int { count }

    @inline(__always)
    subscript(index: Int) -> Element {
        unsafeAddress {
            precondition(index >= 0 && index < count, "Index out of range of a scratch span")
            return UnsafePointer(start + index)
        }
        nonmutating unsafeMutableAddress {
            precondition(index >= 0 && index < count, "Index out of range of a scratch span")
            return start + index
        }
    }

    /// The span's values from `range`, in the same memory.
    @inline(__always)
    func part(_ range: Range<Int>) -> ScratchSpan<Element> {
        precondition(range.lowerBound >= 0 && range.upperBound <= count, "Range out of range of a scratch span")
        return ScratchSpan(start: start + range.lowerBound, count: range.count)
    }

    /// The span's memory, for the standard library's algorithms.
    var buffer: UnsafeMutableBufferPointer<Element> { UnsafeMutableBufferPointer(start: start, count: count) }

    /// Every value set to `value`.
    @inline(__always)
    func fill(with value: Element) {
        start.update(repeating: value, count: count)
    }

    /// The values of `source`, which is as long, copied in.
    @inline(__always)
    func copyElements(from source: ScratchSpan<Element>) {
        precondition(source.count == count, "Copying between scratch spans of different lengths")
        start.update(from: source.start, count: count)
    }

    /// The values of `range` in reverse order. The range is checked once; the swaps inside it are not checked again
    /// (debug builds still check them).
    func reverse(_ range: Range<Int>) {
        precondition(range.lowerBound >= 0 && range.upperBound <= count, "Range out of range of a scratch span")
        var low = range.lowerBound
        var high = range.upperBound - 1
        while low < high {
            assert(low >= 0 && high < count, "a swap within the range checked")
            let value = start[low]
            start[low] = start[high]
            start[high] = value
            low += 1
            high -= 1
        }
    }

    @inline(__always)
    func swapAt(_ first: Int, _ second: Int) {
        let value = self[first]
        self[first] = self[second]
        self[second] = value
    }
}

extension ScratchSpan where Element: Comparable {
    /// The values in ascending order. For values that compare equal only when they are the same (integers), every
    /// sorting algorithm gives this order.
    func sortAscending() {
        var elements = buffer
        elements.sort()
    }
}
