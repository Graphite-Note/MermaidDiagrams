/**
 * File: MindmapMeasurement.swift
 * ------------------------------
 * Layer: Core
 * Description: A mindmap's text measured and its nodes sized: what the layout needs before it places anything.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// A mindmap's text measured and its nodes sized: what the layout needs before it places anything.
struct MindmapMeasurement {
    let texts: [DiagramTextBlock]
    let outlines: [MindmapNodeOutline]
    let sizes: [CGSize]

    /// Measures each node's text, wrapped at `wrappingWidth`, and sizes its outline around it. A text is at least
    /// one line high, so that an empty one keeps its node's height. In an outline running down in a column `outlineRoom`
    /// points wide, the text of a node deeper in the tree wraps sooner (`MindmapOutlinePlacement.textWidth`), and a root
    /// that is not a box is a stadium, which stands under no wider than the trunk's start.
    init(diagram: MindmapDiagram, measurer: some DiagramTextMeasuring, wrappingWidth: CGFloat, outlineRoom: CGFloat? = nil) {
        var texts: [DiagramTextBlock] = []
        var outlines: [MindmapNodeOutline] = []
        var sizes: [CGSize] = []
        texts.reserveCapacity(diagram.nodes.count)
        outlines.reserveCapacity(diagram.nodes.count)
        sizes.reserveCapacity(diagram.nodes.count)
        var depths = Array(repeating: 0, count: diagram.nodes.count)
        for (index, node) in diagram.nodes.enumerated() {
            if let parent = node.parentIndex { depths[index] = depths[parent] + 1 }
            let maximumWidth = outlineRoom.map { room in
                MindmapOutlinePlacement.textWidth(depth: depths[index], room: room, wrappingWidth: wrappingWidth, padding: MindmapNodeOutline.textPadding)
            } ?? wrappingWidth
            let text = DiagramTextBlock(label: node.label, measurer: measurer, maximumWidth: maximumWidth)
            var outline = MindmapNodeOutline(shape: node.shape, isRoot: index == 0, hasChildren: !node.childIndices.isEmpty)
            if outlineRoom != nil, index == 0, outline != .rectangle, outline != .roundedRectangle { outline = .stadium }
            texts.append(text)
            outlines.append(outline)
            sizes.append(outline.size(around: CGSize(width: text.size.width, height: max(text.size.height, measurer.lineHeight))))
        }
        self.texts = texts
        self.outlines = outlines
        self.sizes = sizes
    }
}
