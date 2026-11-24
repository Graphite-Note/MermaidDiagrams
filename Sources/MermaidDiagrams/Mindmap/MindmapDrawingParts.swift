/**
 * File: MindmapDrawingParts.swift
 * -------------------------------
 * Layer: Core
 * Description: A laid-out mindmap's geometry grouped by how it is painted: each branch's links and nodes, the root,
 *              the text, the title.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import CoreGraphics

/// A laid-out mindmap's geometry grouped by how it is painted, so that drawing it in any colors is a few fills and
/// strokes per branch, by Core Graphics (`MindmapRenderer`) or by a view's own shapes. Back to front, as Pele draws:
/// each branch's links and then its nodes, the root over the links that leave it, the text, the title.
public struct MindmapDrawingParts {
    /// The links and node outlines of the branches that share one number (`MindmapNode.branchIndex`), painted in
    /// that number's series color.
    public struct Branch {
        public let branchIndex: Int
        /// The links into the branch's nodes, stroked `linkLineWidth` wide in the branch's color.
        public var links: CGPath { linksScenePath.coreGraphicsPath }
        let linksScenePath: DiagramScenePath
        /// The outlines of the branch's nodes, filled with the branch's color at `nodeFillOpacity` and stroked
        /// `outlineLineWidth` wide in it. A node drawn as text alone has none.
        public var nodeOutlines: CGPath { nodeOutlinesScenePath.coreGraphicsPath }
        let nodeOutlinesScenePath: DiagramScenePath
    }

    /// The branches with something to paint, by number.
    public let branches: [Branch]
    /// The root's outline, filled in the surface color and stroked in the border color.
    public var rootOutline: CGPath { rootOutlineScenePath.coreGraphicsPath }
    let rootOutlineScenePath: DiagramScenePath
    /// Every node's text, in the foreground color.
    public let nodeTexts: [DiagramTextBlock]
    /// The title, drawn bold, or nil.
    public let title: DiagramTextBlock?

    public static let linkLineWidth: CGFloat = 1.5
    public static let outlineLineWidth: CGFloat = 1
    /// How much of the branch color a node's fill takes, over the background: Pele's tint.
    public static let nodeFillOpacity: CGFloat = 0.22

    public init(layout: MindmapLayout) {
        var links = (0..<MindmapNode.branchCount).map { _ in DiagramScenePath() }
        var outlines = (0..<MindmapNode.branchCount).map { _ in DiagramScenePath() }
        var rootOutline = DiagramScenePath()
        for edge in layout.edges {
            links[edge.branchIndex % MindmapNode.branchCount].addEdgePath(edge.path)
        }
        for node in layout.nodes {
            guard let outline = MindmapShapeDrawing.outline(of: node.outline, in: node.frame) else { continue }
            if let branchIndex = node.branchIndex {
                outlines[branchIndex % MindmapNode.branchCount].addPath(outline)
            } else {
                rootOutline.addPath(outline)
            }
        }
        branches = (0..<MindmapNode.branchCount).compactMap { branchIndex in
            links[branchIndex].isEmpty && outlines[branchIndex].isEmpty ? nil
                : Branch(branchIndex: branchIndex, linksScenePath: links[branchIndex], nodeOutlinesScenePath: outlines[branchIndex])
        }
        self.rootOutlineScenePath = rootOutline
        nodeTexts = layout.nodes.flatMap { node in node.isTextLeftAligned ? node.text.leftAlignedLines() : [node.text] }
        title = layout.title
    }
}
