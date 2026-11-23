/**
 * File: LayeredStableSorting.swift
 * --------------------------------
 * Layer: Core
 * Description: Sorting as JavaScript sorts, stable and with a comparison of NaN counted as a tie, for the port of Pele.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

extension Array {
    /// Sorts as JavaScript's `Array.prototype.sort(compare)` does: stable, a negative comparison putting the first
    /// element before the second, and a comparison that is NaN or 0 a tie that keeps their order. A bottom-up merge sort.
    mutating func sortStably(by compare: (Element, Element) -> Double) {
        guard count > 1 else { return }
        var source = self
        var target = self
        var width = 1
        while width < count {
            var start = 0
            while start < count {
                let middle = Swift.min(count, start + width)
                let end = Swift.min(count, start + 2 * width)
                var left = start
                var right = middle
                var written = start
                while left < middle && right < end {
                    if compare(source[right], source[left]) < 0 {
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
            swap(&source, &target)
            width *= 2
        }
        self = source
    }
}
