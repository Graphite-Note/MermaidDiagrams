/**
 * File: ArchitectureGridPlacement.swift
 * -------------------------------------
 * Layer: Core
 * Description: Places an architecture diagram's nodes and groups in grid cells as Pele's placeOnGrid does: each edge's
 *              sides put its ends beside each other, groups laid out innermost first and placed in their parent as one
 *              block, unconnected parts side by side.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

/// The cells of an architecture diagram: each node's, and each group's rectangle of cells (one cell for an empty one).
struct ArchitectureGrid: Equatable {
    var nodeColumns: [Int]
    var nodeRows: [Int]
    var groupColumns: [Int]
    var groupRows: [Int]
    var groupColumnCounts: [Int]
    var groupRowCounts: [Int]
    /// Whether each group holds nothing.
    var groupIsEmpty: [Bool]
}

/// Pele's `placeOnGrid`. Items are the nodes (0 to N-1) then the groups (N to N+G-1); containers are the groups (0 to
/// G-1) then the root (G). A link asks for one item to sit beside another: it belongs to the innermost container that
/// holds both its ends, and relates the two children of that container its ends are in.
struct ArchitectureGridPlacement {
    let nodeCount: Int
    let groupCount: Int
    var parents: [Int]
    var depths: [Int]
    var children: [[Int]]
    var links = ArchitectureGridLinks()
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
    var reaches: [ArchitectureSlideKey: Int] = [:]

    /// Blocks up to this many cells are found through the map of cells; larger ones are compared one by one.
    static let smallBlockCells = 64

    static func grid(of diagram: ArchitectureDiagram) -> ArchitectureGrid {
        var placement = ArchitectureGridPlacement(diagram)
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
        links.finish(itemCount: itemCount)
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
        links.add(ArchitectureGridLink(firstNode: first, secondNode: second, firstSide: firstSide, secondSide: secondSide, firstItem: firstItem,
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
struct ArchitectureGridLink {
    let firstNode: Int
    let secondNode: Int
    let firstSide: ArchitectureSide
    let secondSide: ArchitectureSide
    let firstItem: Int
    let secondItem: Int
}

/// The links, and for each item the links of alignments and of edges it is an end of, in the order added: every link
/// is added first, then `finish(itemCount:)` sorts the ends by item, keeping their order, into one list of each kind
/// with where each item's run starts.
struct ArchitectureGridLinks {
    private(set) var all: [ArchitectureGridLink] = []
    /// Whether each link of `all` is an alignment's.
    private var isHintLink: [Bool] = []
    private var hintStarts: [Int] = [0]
    private var hintLinks: [Int] = []
    private var edgeStarts: [Int] = [0]
    private var edgeLinks: [Int] = []

    mutating func add(_ link: ArchitectureGridLink, isHint: Bool) {
        all.append(link)
        isHintLink.append(isHint)
    }

    /// Sorts the links' ends by item, `itemCount` items, each item's in the order the links were added, the first end
    /// of a link before its second.
    mutating func finish(itemCount: Int) {
        (hintStarts, hintLinks) = ends(itemCount: itemCount, ofHints: true)
        (edgeStarts, edgeLinks) = ends(itemCount: itemCount, ofHints: false)
    }

    private func ends(itemCount: Int, ofHints: Bool) -> (starts: [Int], links: [Int]) {
        var starts = [Int](repeating: 0, count: itemCount + 1)
        for (index, link) in all.enumerated() where isHintLink[index] == ofHints {
            starts[link.firstItem + 1] += 1
            starts[link.secondItem + 1] += 1
        }
        for item in 0..<itemCount { starts[item + 1] += starts[item] }
        var next = starts
        var links = [Int](repeating: 0, count: starts[itemCount])
        for (index, link) in all.enumerated() where isHintLink[index] == ofHints {
            links[next[link.firstItem]] = index
            next[link.firstItem] += 1
            links[next[link.secondItem]] = index
            next[link.secondItem] += 1
        }
        return (starts, links)
    }

    /// The links of alignments `item` is an end of, in the order added.
    func hintLinks(of item: Int) -> ArraySlice<Int> {
        item + 1 < hintStarts.count ? hintLinks[hintStarts[item]..<hintStarts[item + 1]] : []
    }

    /// The links of edges `item` is an end of, in the order added.
    func edgeLinks(of item: Int) -> ArraySlice<Int> {
        item + 1 < edgeStarts.count ? edgeLinks[edgeStarts[item]..<edgeStarts[item + 1]] : []
    }
}

/// The key under which how far a block must slide is kept.
struct ArchitectureSlideKey: Hashable {
    let column: Int
    let row: Int
    let width: Int
    let height: Int
    let stepX: Int
    let stepY: Int
}
