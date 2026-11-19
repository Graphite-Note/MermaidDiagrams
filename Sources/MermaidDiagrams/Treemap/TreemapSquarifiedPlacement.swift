/**
 * File: TreemapSquarifiedPlacement.swift
 * --------------------------------------
 * Layer: Core
 * Description: Places a treemap's boxes by the squarified algorithm, as Pele does: areas by value, rows along the shorter
 *              side, sections with a header band and an inset around their children.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// A node's box while a treemap is placed. All numbers are as JavaScript's doubles, which Pele's layout is written in.
struct TreemapBox {
    /// The node's index in the diagram; a box's index in the list is the same.
    let nodeIndex: Int
    let parent: Int?
    /// The position among the top-level nodes of the branch the box belongs to, which picks its color.
    let series: Int
    /// A leaf's own value, or the sum of the leaves under a section.
    var value: Double
    var children: [Int] = []
    /// Whether a section keeps a band for its header; small sections give it to their children.
    var isHeaded = false
    var header: Double = 0
    var x: Double = 0
    var y: Double = 0
    var width: Double = 0
    var height: Double = 0
}

/// The space a treemap keeps between its boxes and around what a section holds.
struct TreemapInsets {
    let gap: Double
    /// Above a section's children, and the shorter band a small section keeps instead.
    let header: Double
    let shortHeader: Double
    /// On the other three sides of a section's children.
    let side: Double
}

enum TreemapSquarifiedPlacement {
    /// The boxes of `nodes` (one per node, in the nodes' order) and the indexes of those placed, parents before children, within
    /// a frame `width` by `height`. A node with no positive value, and a section with none under it, is not placed.
    static func place(_ nodes: [TreemapNode], width: Double, height: Double, insets: TreemapInsets) -> (boxes: [TreemapBox], placed: [Int]) {
        var placement = Placement(boxes: boxes(of: nodes), insets: insets)
        placement.place(placement.rootBoxes, x: 0, y: 0, width: width, height: height)
        var index = 0
        while index < placement.placed.count {
            placement.placeChildren(ofBoxAt: placement.placed[index])
            index += 1
        }
        return (placement.boxes, placement.placed)
    }

    /// The boxes with their series and values: a leaf's own value, a section's the sum of those under it.
    private static func boxes(of nodes: [TreemapNode]) -> [TreemapBox] {
        var boxes: [TreemapBox] = []
        var rootCount = 0
        for (index, node) in nodes.enumerated() {
            var series = rootCount
            if let parent = node.parentIndex { series = boxes[parent].series } else { rootCount += 1 }
            boxes.append(TreemapBox(nodeIndex: index, parent: node.parentIndex, series: series, value: node.size))
            if let parent = node.parentIndex { boxes[parent].children.append(index) }
        }
        // A node comes after its parent, so going back from the last one adds each into its parent after its own children.
        for index in boxes.indices.reversed() {
            if let parent = boxes[index].parent { boxes[parent].value += boxes[index].value }
        }
        return boxes
    }

    private struct Placement {
        var boxes: [TreemapBox]
        let insets: TreemapInsets
        var placed: [Int] = []

        var rootBoxes: [Int] { boxes.indices.filter { index in boxes[index].parent == nil } }

        /// Places the children of a section that were placed: under a header and inside an inset where there is room for
        /// them, else in the section's whole box.
        mutating func placeChildren(ofBoxAt index: Int) {
            let box = boxes[index]
            guard !box.children.isEmpty else { return }
            let side = insets.side
            let top = box.height - insets.header - side >= 12 ? insets.header : insets.shortHeader
            let isHeaded = box.width > max(24, 2 * side) && box.height - top - side >= 8
            boxes[index].isHeaded = isHeaded
            boxes[index].header = isHeaded ? top : 0
            if isHeaded {
                place(box.children, x: box.x + side, y: box.y + top, width: box.width - 2 * side, height: box.height - top - side)
            } else {
                place(box.children, x: box.x, y: box.y, width: box.width, height: box.height)
            }
        }

        /// Lays the boxes with a value among `children` out in the rectangle, the largest first.
        mutating func place(_ children: [Int], x: Double, y: Double, width: Double, height: Double) {
            let shown = children.filter { index in boxes[index].value > 0 }.sorted { first, second in
                boxes[first].value != boxes[second].value ? boxes[first].value > boxes[second].value : first < second
            }
            var total = 0.0
            for index in shown { total += boxes[index].value }
            guard !shown.isEmpty, total.isFinite else { return }
            let width = max(0, width)
            let height = max(0, height)
            let gap = insets.gap
            if width > 0, height > 0 { squarify(shown, total: total, x: x - gap / 2, y: y - gap / 2, width: width + gap, height: height + gap) }
            for index in shown {
                var box = boxes[index]
                let left = Self.clamped(box.x, x, x + width)
                let top = Self.clamped(box.y, y, y + height)
                box.width = Self.clamped(box.x + box.width, left, x + width) - left
                box.height = Self.clamped(box.y + box.height, top, y + height) - top
                box.x = left
                box.y = top
                boxes[index] = box
                placed.append(index)
            }
        }

        private static func clamped(_ value: Double, _ low: Double, _ high: Double) -> Double {
            value >= low ? min(value, high) : low
        }

        /// Lays `shown` out in the rectangle as one squarified treemap: rows are added along the shorter side, and a row stops
        /// growing when another box would make its boxes less square.
        private mutating func squarify(_ shown: [Int], total: Double, x startX: Double, y startY: Double, width startWidth: Double, height startHeight: Double) {
            var rest = total
            var (x, y, width, height) = (startX, startY, startWidth, startHeight)
            var from = 0
            while from < shown.count {
                let scale = (width * height) / rest
                let side = min(width, height)
                let to = endOfRow(shown, from: from, scale: scale, side: side)
                let sum = shown[from..<to].reduce(0) { total, index in total + boxes[index].value * scale }
                let thickness = sum / side
                var offset = 0.0
                for position in from..<to {
                    let index = shown[position]
                    let length = position == to - 1 ? side - offset : boxes[index].value * scale / thickness
                    let isWide = width >= height
                    place(index, x: isWide ? x : x + offset, y: isWide ? y + offset : y, width: isWide ? thickness : length,
                          height: isWide ? length : thickness)
                    offset += length
                    rest -= boxes[index].value
                }
                if width >= height {
                    x += thickness
                    width -= thickness
                } else {
                    y += thickness
                    height -= thickness
                }
                from = to
            }
        }

        /// Where the row of boxes that starts at `from` ends: boxes are added while the worst ratio of a side to another among the
        /// row's boxes, laid along `side`, does not grow.
        private func endOfRow(_ shown: [Int], from: Int, scale: Double, side: Double) -> Int {
            var sum = boxes[shown[from]].value * scale
            let largest = sum
            var worst = max(side * side * largest / (sum * sum), sum * sum / (side * side * largest))
            var to = from + 1
            while to < shown.count {
                let smallest = boxes[shown[to]].value * scale
                let next = sum + smallest
                let ratio = max(side * side * largest / (next * next), next * next / (side * side * smallest))
                if ratio > worst { break }
                worst = ratio
                sum = next
                to += 1
            }
            return to
        }

        /// Puts the box at the position, rounded to whole points, leaving half the gap off each side unless that would erase it.
        private mutating func place(_ index: Int, x boxX: Double, y boxY: Double, width boxWidth: Double, height boxHeight: Double) {
            let halfGap = insets.gap / 2
            let gapX = TreemapSquarifiedPlacement.rounded(boxX + boxWidth - halfGap) > TreemapSquarifiedPlacement.rounded(boxX + halfGap) ? halfGap : 0
            let gapY = TreemapSquarifiedPlacement.rounded(boxY + boxHeight - halfGap) > TreemapSquarifiedPlacement.rounded(boxY + halfGap) ? halfGap : 0
            boxes[index].x = TreemapSquarifiedPlacement.rounded(boxX + gapX)
            boxes[index].y = TreemapSquarifiedPlacement.rounded(boxY + gapY)
            boxes[index].width = TreemapSquarifiedPlacement.rounded(boxX + boxWidth - gapX) - boxes[index].x
            boxes[index].height = TreemapSquarifiedPlacement.rounded(boxY + boxHeight - gapY) - boxes[index].y
        }

    }

    /// JavaScript's `Math.round`: halves go up.
    static func rounded(_ value: Double) -> Double {
        (value + 0.5).rounded(.down)
    }
}
