/**
 * File: ReferenceLayeredFlatGroupArrangement.swift
 * ------------------------------------------------
 * Layer: Tests
 * Description: The 0.7.0 layered layout kept as the reference the span layout is checked against: keeps each group of
 *              Pele's layered layout contiguous in its ranks, ordering groups by their mean key.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

@testable import MermaidDiagrams

extension ReferenceLayeredFlatCrossingReduction {
    /// The groups' depths, and each rank arranged by its present positions so that every group is contiguous.
    mutating func prepareGroups() {
        let groupTotal = graph.parentOfGroup.count
        workspace.recycle(groupDepth)
        groupDepth = workspace.integers(count: groupTotal, repeating: 0)
        for group in 0..<groupTotal {
            var parent = group
            while parent >= 0 {
                groupDepth[group] += 1
                parent = graph.parentOfGroup[parent]
            }
        }
        workspace.recycle(groupSum)
        workspace.recycle(groupCount)
        workspace.recycle(groupFirst)
        groupSum = workspace.numbers(count: groupTotal, repeating: 0)
        groupCount = workspace.integers(count: groupTotal, repeating: 0)
        groupFirst = workspace.integers(count: groupTotal, repeating: 0)
        var keys = workspace.numbers(count: graph.vertexCount, repeating: 0)
        for rank in 0...graph.maximumRank {
            for index in graph.rankStart[rank]..<graph.rankStart[rank + 1] { keys[graph.order[index]] = Double(index - graph.rankStart[rank]) }
            arrange(rank: rank, keys: keys)
        }
        workspace.recycle(consume keys)
    }

    /// Orders `rank` by `keys`, every group kept together and placed by the mean key of what it holds there: two
    /// vertices are compared as the items they belong to in their innermost common group (Pele's `arrange`).
    mutating func arrange(rank: Int, keys: [Double]) {
        guard let vertexGroup = graph.vertexGroup else { return }
        let start = graph.rankStart[rank]
        let end = graph.rankStart[rank + 1]
        for index in start..<end {
            var group = vertexGroup[graph.order[index]]
            while group >= 0 {
                groupSum[group] = 0
                groupCount[group] = 0
                group = graph.parentOfGroup[group]
            }
        }
        for index in start..<end {
            let vertex = graph.order[index]
            var group = vertexGroup[vertex]
            while group >= 0 {
                if groupCount[group] == 0 { groupFirst[group] = index }
                groupSum[group] += keys[vertex]
                groupCount[group] += 1
                group = graph.parentOfGroup[group]
            }
        }
        // The row and the merge sort's spare are lists of the reduction, moved out while the comparison reads it.
        var row: [Int] = []
        var spare: [Int] = []
        swap(&row, &arrangedRow)
        swap(&spare, &sortSpare)
        row.removeAll(keepingCapacity: true)
        row.append(contentsOf: graph.order[start..<end])
        row.sortStably(spare: &spare) { first, second in
            compareInGroups(first, second, keys: keys, rankStart: start, vertexGroup: vertexGroup) < 0
        }
        graph.order.replaceSubrange(start..<end, with: row)
        swap(&row, &arrangedRow)
        swap(&spare, &sortSpare)
        for index in start..<end { graph.position[graph.order[index]] = index - start }
    }

    /// Compares two vertices as siblings in their nearest common group; a group as an item is `vertexCount + group`.
    private func compareInGroups(_ first: Int, _ second: Int, keys: [Double], rankStart: Int, vertexGroup: [Int]) -> Double {
        let vertexCount = graph.vertexCount
        let parent = graph.parentOfGroup
        var firstItem = first, secondItem = second
        var firstGroup = vertexGroup[first], secondGroup = vertexGroup[second]
        var firstDepth = firstGroup < 0 ? 0 : groupDepth[firstGroup]
        var secondDepth = secondGroup < 0 ? 0 : groupDepth[secondGroup]
        while firstDepth > secondDepth {
            firstItem = vertexCount + firstGroup
            firstGroup = parent[firstGroup]
            firstDepth -= 1
        }
        while secondDepth > firstDepth {
            secondItem = vertexCount + secondGroup
            secondGroup = parent[secondGroup]
            secondDepth -= 1
        }
        while firstGroup != secondGroup {
            firstItem = vertexCount + firstGroup
            firstGroup = parent[firstGroup]
            secondItem = vertexCount + secondGroup
            secondGroup = parent[secondGroup]
        }
        func value(_ item: Int) -> Double { item >= vertexCount ? groupSum[item - vertexCount] / Double(groupCount[item - vertexCount]) : keys[item] }
        func firstIndex(_ item: Int) -> Int { item >= vertexCount ? groupFirst[item - vertexCount] : rankStart + graph.position[item] }
        let difference = value(firstItem) - value(secondItem)
        if difference != 0 && !difference.isNaN { return difference }
        return Double(firstIndex(firstItem) - firstIndex(secondItem))
    }
}
