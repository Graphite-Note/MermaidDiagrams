/**
 * File: ScratchSorting.swift
 * --------------------------
 * Layer: Core
 * Description: The stable sort Pele's layouts rely on, as JavaScript's Array.prototype.sort orders, on scratch spans.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

extension ScratchSpan {
    /// Sorts as `Array.sortStably(spare:isBefore:)` does, step for step, so that a comparison that is not a strict
    /// order (NaN) gives the same order too: up to sixteen values by insertion in place, more by a bottom-up merge
    /// sort between the span and room for as many values taken from `arena` and given back before returning.
    @inline(__always)
    func sortStably(in arena: DiagramScratchArena, isBefore: (Element, Element) -> Bool) {
        let count = self.count
        guard count > 1 else { return }
        if count <= Self.insertionSortLimit {
            for index in 1..<count {
                let element = start[index]
                var position = index
                while position > 0 && isBefore(element, start[position - 1]) {
                    start[position] = start[position - 1]
                    position -= 1
                }
                start[position] = element
            }
            return
        }
        let mark = arena.mark()
        defer { arena.release(to: mark) }
        let spare: ScratchSpan<Element> = arena.uninitializedSpan(count: count)
        var source = start
        var target = spare.start
        var width = 1
        while width < count {
            Self.mergeRuns(of: width, from: source, into: target, count: count, isBefore: isBefore)
            swap(&source, &target)
            width *= 2
        }
        if source != start { start.update(from: source, count: count) }
    }

    /// Sorts the values of `range` the same way.
    @inline(__always)
    func sortStably(_ range: Range<Int>, in arena: DiagramScratchArena, isBefore: (Element, Element) -> Bool) {
        part(range).sortStably(in: arena, isBefore: isBefore)
    }

    /// Merges each pair of neighbouring sorted runs `width` long of `source` into `target`, the second run's element
    /// first only where it is strictly before.
    @inline(__always)
    private static func mergeRuns(of width: Int, from source: UnsafeMutablePointer<Element>, into target: UnsafeMutablePointer<Element>,
                                  count: Int, isBefore: (Element, Element) -> Bool) {
        var runStart = 0
        while runStart < count {
            let middle = Swift.min(count, runStart + width)
            let end = Swift.min(count, runStart + 2 * width)
            var left = runStart
            var right = middle
            var written = runStart
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
            runStart += 2 * width
        }
    }

    /// Up to this many values are sorted in place by insertion, as `Array.sortStably` does.
    private static var insertionSortLimit: Int { 16 }
}

extension ScratchList {
    /// Sorts the list's values as `ScratchSpan.sortStably(in:isBefore:)` does.
    @inline(__always)
    func sortStably(in arena: DiagramScratchArena, isBefore: (Element, Element) -> Bool) {
        elements.sortStably(in: arena, isBefore: isBefore)
    }
}
