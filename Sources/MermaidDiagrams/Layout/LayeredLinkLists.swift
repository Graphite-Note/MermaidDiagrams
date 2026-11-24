/**
 * File: LayeredLinkLists.swift
 * ----------------------------
 * Layer: Core
 * Description: Lists of indices for each of a number of indices, kept one after another in two spans of an arena.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

/// For each index below `count`, a list of indices: what an array of arrays would hold, kept one list after another in
/// two spans of a scratch arena instead of an array per index. Built from links added as pairs of a key and a value:
/// each key's list holds its values in the order the links were added.
struct LayeredLinkLists {
    /// Where each key's list starts in `items`, with the end of the last after it.
    let start: ScratchSpan<Int>
    let items: ScratchSpan<Int>

    /// The lists of `count` keys from the links `keys[index]` to `values[index]`, each key's in the links' order.
    init(count: Int, keys: ScratchSpan<Int>, values: ScratchSpan<Int>, arena: DiagramScratchArena) {
        start = arena.span(count: count + 1, repeating: 0)
        for key in keys { start[key + 1] += 1 }
        for key in 0..<count { start[key + 1] += start[key] }
        items = arena.span(count: keys.count, repeating: 0)
        let fill = arena.copy(of: start.part(0..<count))
        for index in keys.indices {
            items[fill[keys[index]]] = values[index]
            fill[keys[index]] += 1
        }
    }

    /// The list of `key`.
    subscript(key: Int) -> ScratchSpan<Int> { items.part(start[key]..<start[key + 1]) }
}
