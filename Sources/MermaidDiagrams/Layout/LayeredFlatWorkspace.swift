/**
 * File: LayeredFlatWorkspace.swift
 * --------------------------------
 * Layer: Core
 * Description: The working lists of the layered layout, made once per layout and reused by each of its passes.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

/// The lists the layered layout works in, kept from one pass to the next and from one flat layout to the next within a
/// compound layout: a pass takes a list of the length it needs, filled with one value, and gives it back when it is
/// done, so that the storage a pass let go of is used again by a later one instead of being allocated and freed again.
/// A workspace is made by each top-level layout call and lives no longer than it (no state is shared between layouts,
/// which run on any thread). It keeps at most 32 lists of each element type, each no longer than the longest list of
/// the layout, which `MermaidDiagramLimits` bounds.
final class LayeredFlatWorkspace {
    // Only the workspace's own methods touch the pools, one call at a time and never from within another, so the
    // runtime's exclusivity checks on them are left out.
    @exclusivity(unchecked) private var integerLists = LayeredListPool<32, Int>()
    @exclusivity(unchecked) private var numberLists = LayeredListPool<24, Double>()
    @exclusivity(unchecked) private var flagLists = LayeredListPool<12, Bool>()
    @exclusivity(unchecked) private var kindLists = LayeredListPool<2, LayeredVertexKind>()
    @exclusivity(unchecked) private var endLists = LayeredListPool<4, LayeredSegmentEnd>()

    init() {}

    /// A list of `count` integers, each `value`.
    func integers(count: Int, repeating value: Int) -> [Int] { integerLists.take(count: count, repeating: value) }

    /// An empty list of integers with room for at least `capacity`.
    func emptyIntegers(capacity: Int) -> [Int] { integerLists.takeEmpty(capacity: capacity) }

    /// A list of `count` numbers, each `value`.
    func numbers(count: Int, repeating value: Double) -> [Double] { numberLists.take(count: count, repeating: value) }

    /// An empty list of numbers with room for at least `capacity`.
    func emptyNumbers(capacity: Int) -> [Double] { numberLists.takeEmpty(capacity: capacity) }

    /// A list of `count` flags, each `value`.
    func flags(count: Int, repeating value: Bool) -> [Bool] { flagLists.take(count: count, repeating: value) }

    /// A list of `count` vertex kinds, each `value`.
    func kinds(count: Int, repeating value: LayeredVertexKind) -> [LayeredVertexKind] { kindLists.take(count: count, repeating: value) }

    /// An empty list of segment ends with room for at least `capacity`.
    func emptyEnds(capacity: Int) -> [LayeredSegmentEnd] { endLists.takeEmpty(capacity: capacity) }

    /// Takes back a list its holder is done with. A list still shared with another holder is kept too: the next taker's
    /// first change copies it, as any shared array would be, so nothing a holder still reads is ever changed.
    func recycle(_ list: consuming [Int]) { integerLists.keep(list) }
    func recycle(_ list: consuming [Double]) { numberLists.keep(list) }
    func recycle(_ list: consuming [Bool]) { flagLists.keep(list) }
    func recycle(_ list: consuming [LayeredVertexKind]) { kindLists.keep(list) }
    func recycle(_ list: consuming [LayeredSegmentEnd]) { endLists.keep(list) }
}

/// The lists of one element type a workspace keeps, at most `keeping`, held in the workspace itself so that keeping
/// them costs no allocation of its own. A taker gets a kept list with room for what it asks, or a new one when none has.
struct LayeredListPool<let keeping: Int, Element> {
    private var lists = InlineArray<keeping, [Element]>(repeating: [])
    /// The room of each kept list, read without reaching into the lists themselves.
    private var capacities = InlineArray<keeping, Int>(repeating: 0)
    private var count = 0

    /// A kept list with room for `capacity`, the most recently kept first, taken out of the pool as it is, or nil.
    private mutating func takeFitting(_ capacity: Int) -> [Element]? {
        var index = count - 1
        while index >= 0 && capacities[index] < capacity { index -= 1 }
        guard index >= 0 else { return nil }
        count -= 1
        var list: [Element] = []
        swap(&list, &lists[index])
        if index != count {
            // The last kept list moves into the place taken from.
            var last: [Element] = []
            swap(&last, &lists[count])
            lists[index] = last
            capacities[index] = capacities[count]
        }
        return list
    }

    mutating func take(count: Int, repeating value: Element) -> [Element] {
        guard var list = takeFitting(count) else { return [Element](repeating: value, count: count) }
        // The list keeps the elements it had: as many as are needed are overwritten and the rest removed or added.
        if list.count > count { list.removeLast(list.count - count) }
        list.withUnsafeMutableBufferPointer { elements in elements.update(repeating: value) }
        if list.count < count { list.append(contentsOf: repeatElement(value, count: count - list.count)) }
        return list
    }

    mutating func takeEmpty(capacity: Int) -> [Element] {
        if var list = takeFitting(capacity) {
            list.removeAll(keepingCapacity: true)
            return list
        }
        var list: [Element] = []
        list.reserveCapacity(capacity)
        return list
    }

    mutating func keep(_ list: consuming [Element]) {
        let capacity = list.capacity
        guard capacity > 0, count < keeping else { return }
        lists[count] = list
        capacities[count] = capacity
        count += 1
    }
}
