/**
 * File: ReferenceArchitectureGridPlacement.swift
 * ----------------------------------------------
 * Layer: Tests
 * Description: 0.7.0's placement of an architecture diagram's items on its grid (Pele's placeOnGrid), frozen as main 2a0cc65
 *              placed them, which the placement is compared with.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import Foundation
@testable import MermaidDiagrams

/// Pele's `placeOnGrid`. Items are the nodes (0 to N-1) then the groups (N to N+G-1); containers are the groups (0 to
/// G-1) then the root (G). A link asks for one item to sit beside another: it belongs to the innermost container that
/// holds both its ends, and relates the two children of that container its ends are in.
struct ReferenceArchitectureGridPlacement {
    let nodeCount: Int
    let groupCount: Int
    var parents: [Int]
    var depths: [Int]
    var children: [[Int]]
    var links = ReferenceArchitectureGridLinks()
    var x: [Int]
    var y: [Int]
    var widths: [Int]
    var heights: [Int]
    var isPlaced: [Bool]
    /// The items placed in the current container, in the order placed, and where the current part starts in it.
    var order: [Int] = []
    var partStart = 0
    var cells: [Int: Int] = [:]
    var largeItems: [Int] = []
    var reaches: [ReferenceArchitectureSlideKey: Int] = [:]

    /// Blocks up to this many cells are found through the map of cells; larger ones are compared one by one.
    static let smallBlockCells = 64

    static func grid(of diagram: ArchitectureDiagram) -> ArchitectureGrid {
        var placement = ReferenceArchitectureGridPlacement(diagram)
        for container in stride(from: placement.groupCount - 1, through: 0, by: -1) { placement.layOut(container) }
        placement.layOut(placement.groupCount)
        return placement.grid
    }

    private init(_ diagram: ArchitectureDiagram) {
        nodeCount = diagram.nodes.count
        groupCount = diagram.groups.count
        let itemCount = nodeCount + groupCount
        parents = [Int](repeating: groupCount, count: itemCount)
        depths = [Int](repeating: 0, count: groupCount + 1)
        children = [[Int]](repeating: [], count: groupCount + 1)
        x = [Int](repeating: 0, count: itemCount)
        y = x
        widths = [Int](repeating: 1, count: itemCount)
        heights = widths
        isPlaced = [Bool](repeating: false, count: itemCount)
        for (group, declared) in diagram.groups.enumerated() {
            if let parent = declared.parentIndex, parent != group {
                parents[nodeCount + group] = parent
                depths[group] = depths[parent] + 1
            } else {
                depths[group] = 1
            }
        }
        for (node, declared) in diagram.nodes.enumerated() {
            if let group = declared.groupIndex { parents[node] = group }
            children[parents[node]].append(node)
        }
        for group in 0..<groupCount { children[parents[nodeCount + group]].append(nodeCount + group) }
        addLinks(of: diagram)
    }

    /// The alignments' links (a row's members left to right, a column's top to bottom), then the edges' between unlike
    /// sides, then between like sides, which say least about where their ends go.
    private mutating func addLinks(of diagram: ArchitectureDiagram) {
        for alignment in diagram.alignments {
            for (first, second) in zip(alignment.memberIndices, alignment.memberIndices.dropFirst()) {
                addLink(first, second, alignment.isRow ? .right : .bottom, alignment.isRow ? .left : .top, isHint: true)
            }
        }
        for likeSides in [false, true] {
            for edge in diagram.edges where (edge.sourceSide == edge.targetSide) == likeSides {
                addLink(edge.sourceIndex, edge.targetIndex, edge.sourceSide, edge.targetSide, isHint: false)
            }
        }
    }

    private mutating func addLink(_ first: Int, _ second: Int, _ firstSide: ArchitectureSide, _ secondSide: ArchitectureSide, isHint: Bool) {
        guard first != second else { return }
        var firstItem = first
        var secondItem = second
        var firstContainer = parents[first]
        var secondContainer = parents[second]
        while firstContainer != secondContainer {
            if depths[firstContainer] >= depths[secondContainer] {
                firstItem = nodeCount + firstContainer
                firstContainer = parents[firstItem]
            } else {
                secondItem = nodeCount + secondContainer
                secondContainer = parents[secondItem]
            }
        }
        links.add(ReferenceArchitectureGridLink(firstNode: first, secondNode: second, firstSide: firstSide, secondSide: secondSide, firstItem: firstItem,
                                       secondItem: secondItem), isHint: isHint)
    }

    /// The grid: each group's rectangle where its parent's is, each node's cell where its group's is.
    private var grid: ArchitectureGrid {
        var groupColumns = [Int](repeating: 0, count: groupCount)
        var groupRows = groupColumns
        for group in 0..<groupCount {
            let parent = parents[nodeCount + group]
            groupColumns[group] = x[nodeCount + group] + (parent == groupCount ? 0 : groupColumns[parent])
            groupRows[group] = y[nodeCount + group] + (parent == groupCount ? 0 : groupRows[parent])
        }
        let nodeColumns = (0..<nodeCount).map { node in x[node] + (parents[node] == groupCount ? 0 : groupColumns[parents[node]]) }
        let nodeRows = (0..<nodeCount).map { node in y[node] + (parents[node] == groupCount ? 0 : groupRows[parents[node]]) }
        return ArchitectureGrid(nodeColumns: nodeColumns, nodeRows: nodeRows, groupColumns: groupColumns, groupRows: groupRows,
                                groupColumnCounts: Array(widths[nodeCount...]), groupRowCounts: Array(heights[nodeCount...]),
                                groupIsEmpty: (0..<groupCount).map { group in children[group].isEmpty })
    }
}

/// A link: the two nodes it joins and their sides, and the two items of their shared container they are in.
struct ReferenceArchitectureGridLink {
    let firstNode: Int
    let secondNode: Int
    let firstSide: ArchitectureSide
    let secondSide: ArchitectureSide
    let firstItem: Int
    let secondItem: Int
}

/// The links, and for each item the links of alignments and of edges it is an end of, in the order added.
struct ReferenceArchitectureGridLinks {
    private(set) var all: [ReferenceArchitectureGridLink] = []
    private(set) var hintLinksByItem: [Int: [Int]] = [:]
    private(set) var edgeLinksByItem: [Int: [Int]] = [:]

    mutating func add(_ link: ReferenceArchitectureGridLink, isHint: Bool) {
        let index = all.count
        all.append(link)
        if isHint {
            hintLinksByItem[link.firstItem, default: []].append(index)
            hintLinksByItem[link.secondItem, default: []].append(index)
        } else {
            edgeLinksByItem[link.firstItem, default: []].append(index)
            edgeLinksByItem[link.secondItem, default: []].append(index)
        }
    }
}

/// The key under which how far a block must slide is kept.
struct ReferenceArchitectureSlideKey: Hashable {
    let column: Int
    let row: Int
    let width: Int
    let height: Int
    let stepX: Int
    let stepY: Int
}
