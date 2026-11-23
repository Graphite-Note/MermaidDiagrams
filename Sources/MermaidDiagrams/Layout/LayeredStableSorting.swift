/**
 * File: LayeredStableSorting.swift
 * --------------------------------
 * Layer: Core
 * Description: Sorting as JavaScript sorts, stable and with a comparison of NaN counted as a tie, for the port of Pele.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

extension Array {
    /// Sorts as JavaScript's `Array.prototype.sort(compare)` does: stable, a negative comparison putting the first
    /// element before the second, and a comparison that is NaN or 0 a tie that keeps their order. A bottom-up merge sort
    /// between the array and one copy of it.
    mutating func sortStably(by compare: (Element, Element) -> Double) {
        var spare: [Element] = []
        sortStably(spare: &spare) { first, second in compare(first, second) < 0 }
    }

    /// The same order with a comparison whose negative results `isBefore` gives, merging through `spare` (made as long
    /// as the array where it is shorter, and kept by a caller that sorts many times); inlined so that `isBefore` is.
    @inline(__always)
    mutating func sortStably(spare: inout [Element], isBefore: (Element, Element) -> Bool) {
        let count = self.count
        guard count > 1 else { return }
        if count <= Self.insertionSortLimit {
            // Up to the limit, by insertion in place: each element moves before those it compares strictly before.
            withUnsafeMutableBufferPointer { elements in
                for index in 1..<count {
                    let element = elements[index]
                    var position = index
                    while position > 0 && isBefore(element, elements[position - 1]) {
                        elements[position] = elements[position - 1]
                        position -= 1
                    }
                    elements[position] = element
                }
            }
            return
        }
        if spare.count < count { spare = self }
        spare.withUnsafeMutableBufferPointer { spareElements in
            withUnsafeMutableBufferPointer { elements in
                var source = elements
                var target = spareElements
                var width = 1
                while width < count {
                    Self.mergeRuns(of: width, from: source, into: target, count: count, isBefore: isBefore)
                    swap(&source, &target)
                    width *= 2
                }
                if source.baseAddress != elements.baseAddress {
                    for index in 0..<count { elements[index] = source[index] }
                }
            }
        }
    }

    /// Merges each pair of neighbouring sorted runs `width` long of `source` into `target`, the second run's element
    /// first only where it is strictly before.
    @inline(__always)
    private static func mergeRuns(of width: Int, from source: UnsafeMutableBufferPointer<Element>,
                                  into target: UnsafeMutableBufferPointer<Element>, count: Int,
                                  isBefore: (Element, Element) -> Bool) {
        var start = 0
        while start < count {
            let middle = Swift.min(count, start + width)
            let end = Swift.min(count, start + 2 * width)
            var left = start
            var right = middle
            var written = start
            while left < middle && right < end {
                if isBefore(source[right], source[left]) {
                    target[written] = source[right]
                    right += 1
                } else {
                    target[written] = source[left]
                    left += 1
                }
                written += 1
            }
            while left < middle { target[written] = source[left]; left += 1; written += 1 }
            while right < end { target[written] = source[right]; right += 1; written += 1 }
            start += 2 * width
        }
    }

    /// Up to this many elements are sorted in place by insertion, which allocates nothing.
    private static var insertionSortLimit: Int { 16 }
}
