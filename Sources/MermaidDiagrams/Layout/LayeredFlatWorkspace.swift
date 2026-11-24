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
/// which run on any thread). It keeps a few dozen lists of each element type at most, each no longer than the longest
/// list of the layout, which `MermaidDiagramLimits` bounds.
final class LayeredFlatWorkspace {
    // Only the workspace's own methods touch the pools, one call at a time and never from within another, so the
    // runtime's exclusivity checks on them are left out.
    @exclusivity(unchecked) private var integerLists = LayeredListPool<Int>(keeping: 32)
    @exclusivity(unchecked) private var numberLists = LayeredListPool<Double>(keeping: 24)
    @exclusivity(unchecked) private var flagLists = LayeredListPool<Bool>(keeping: 12)
    @exclusivity(unchecked) private var kindLists = LayeredListPool<LayeredVertexKind>(keeping: 2)
    @exclusivity(unchecked) private var endLists = LayeredListPool<LayeredSegmentEnd>(keeping: 4)

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

/// The lists of one element type a workspace keeps, at most as many as it was made to keep (`keeping`, its room
/// reserved once). A taker gets a kept list with room for what it asks, or a new one when none has.
struct LayeredListPool<Element> {
    private var lists: [[Element]] = []
    /// The room of each kept list, read without reaching into the lists themselves.
    private var capacities: [Int] = []
    private let keeping: Int

    init(keeping: Int) {
        self.keeping = keeping
        lists.reserveCapacity(keeping)
        capacities.reserveCapacity(keeping)
    }

    /// A kept list with room for `capacity`, the most recently kept first, taken out of the pool as it is, or nil.
    private mutating func takeFitting(_ capacity: Int) -> [Element]? {
        var index = capacities.count - 1
        while index >= 0 && capacities[index] < capacity { index -= 1 }
        guard index >= 0 else { return nil }
        let last = capacities.count - 1
        if index != last {
            lists.swapAt(index, last)
            capacities.swapAt(index, last)
        }
        capacities.removeLast()
        return lists.removeLast()
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
        guard capacity > 0, lists.count < keeping else { return }
        lists.append(list)
        capacities.append(capacity)
    }
}
