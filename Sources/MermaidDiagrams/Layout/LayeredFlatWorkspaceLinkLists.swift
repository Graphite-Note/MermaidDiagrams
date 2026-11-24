/**
 * File: LayeredFlatWorkspaceLinkLists.swift
 * -----------------------------------------
 * Layer: Core
 * Description: Lists of indices for each of a number of indices, kept one after another in two lists of a workspace.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

/// For each index below `count`, a list of indices: what an array of arrays would hold, kept one list after another so
/// that the whole costs two lists of the workspace instead of an array per index. Built from links added as pairs of a
/// key and a value: each key's list holds its values in the order the links were added.
struct LayeredLinkLists {
    /// Where each key's list starts in `items`, with the end of the last after it.
    private(set) var start: [Int]
    private(set) var items: [Int]

    /// The lists of `count` keys from the links `keys[index]` to `values[index]`, each key's in the links' order.
    init(count: Int, keys: [Int], values: [Int], workspace: LayeredFlatWorkspace) {
        start = workspace.integers(count: count + 1, repeating: 0)
        for key in keys { start[key + 1] += 1 }
        for key in 0..<count { start[key + 1] += start[key] }
        items = workspace.integers(count: keys.count, repeating: 0)
        var fill = workspace.emptyIntegers(capacity: count)
        fill.append(contentsOf: start[0..<count])
        for index in keys.indices {
            items[fill[keys[index]]] = values[index]
            fill[keys[index]] += 1
        }
        workspace.recycle(consume fill)
    }

    /// The list of `key`.
    subscript(key: Int) -> ArraySlice<Int> { items[start[key]..<start[key + 1]] }

    /// Gives the lists back to `workspace`.
    consuming func recycle(into workspace: LayeredFlatWorkspace) {
        workspace.recycle(start)
        workspace.recycle(items)
    }
}
