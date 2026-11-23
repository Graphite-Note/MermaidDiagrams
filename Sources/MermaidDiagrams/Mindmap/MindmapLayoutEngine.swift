/**
 * File: MindmapLayoutEngine.swift
 * -------------------------------
 * Layer: Core
 * Description: Lays a mindmap out in Pele's style, spread to both sides or as an outline running down for a narrow
 *              column.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import CoreGraphics

/// Lays a mindmap out in Pele's style: each node sized around its text, wrapped at 200 points; the root in the middle
/// and its branches spread to its right and left, each subtree stacked in a band, a column further out per level;
/// links as S curves from a parent's side to its child's, in the child's branch color; the title above. For a column too
/// narrow for that, an outline running down instead (`MindmapOutlinePlacement`).
public enum MindmapLayoutEngine {
    /// The widest a line of text is before it wraps.
    static let wrappingWidth: CGFloat = 200
    /// Around the whole diagram.
    static let padding: CGFloat = 8
    /// Between the title and the diagram.
    static let titleGap: CGFloat = 16

    /// `availableWidth`, the width of the column the mindmap is shown in, turns it to run down as an outline when its map
    /// does not fit and the column is under 640 points (`DiagramWidthFitting.turnToFit`), as Pele turns it, if that is
    /// narrower; nil keeps the map spread to both sides.
    public static func layout(_ diagram: MindmapDiagram, typography: DiagramTypography, availableWidth: CGFloat? = nil) -> MindmapLayout {
        layout(diagram, measurer: typography.nodeText, font: typography.font, availableWidth: availableWidth)
    }

    static func layout(_ diagram: MindmapDiagram, measurer: some DiagramTextMeasuring, font: DiagramFont, availableWidth: CGFloat? = nil) -> MindmapLayout {
        DiagramWidthFitting.turnToFit(availableWidth: availableWidth, width: { (layout: MindmapLayout) in layout.size.width }) { runsDown in
            layout(diagram, measurer: measurer, font: font, availableWidth: availableWidth, runsDown: runsDown)
        }
    }

    private static func layout(_ diagram: MindmapDiagram, measurer: some DiagramTextMeasuring, font: DiagramFont, availableWidth: CGFloat?,
                               runsDown: Bool) -> MindmapLayout {
        // An outline has the width the column gives it, less what its level is set in.
        let outlineRoom = runsDown ? DiagramWidthFitting.limit(availableWidth).map { width in width - 2 * padding } ?? .infinity : nil
        let measured = MindmapMeasurement(diagram: diagram, measurer: measurer, wrappingWidth: wrappingWidth, outlineRoom: outlineRoom)
        let title = diagram.title.map { title in
            DiagramTextBlock(label: DiagramLabel(title), measurer: measurer, maximumWidth: DiagramWidthFitting.titleRoom(availableWidth: availableWidth))
        }
        guard runsDown else {
            var bands = MindmapSubtreeBands(diagram: diagram, heights: measured.sizes.map(\.height))
            let placement = MindmapPlacement(diagram: diagram, sizes: measured.sizes, bands: &bands)
            let nodes = diagram.nodes.indices.map { index in placedNode(index, diagram: diagram, measured: measured, placement: placement) }
            let edges = diagram.nodes.indices.dropFirst().compactMap { index in edge(to: index, diagram: diagram, nodes: nodes, placement: placement) }
            return finished(nodes: nodes, edges: edges, title: title, font: font, seriesColors: diagram.seriesColors)
        }
        let placement = MindmapOutlinePlacement(diagram: diagram, sizes: measured.sizes)
        let nodes = diagram.nodes.indices.map { index in
            outlineNode(index, diagram: diagram, measured: measured, centerAcross: placement.centersAcross[index], top: placement.tops[index])
        }
        let edges = MindmapOutlinePlacement.links(diagram: diagram, nodes: nodes).map { link in MindmapLayoutEdge(path: link.path, branchIndex: link.branchIndex) }
        return finished(nodes: nodes, edges: edges, title: title, font: font, seriesColors: diagram.seriesColors)
    }

    /// A node of an outline: its text starts at the left of its box when it is drawn as text alone, as a column of lines
    /// would look ragged centered.
    private static func outlineNode(_ index: Int, diagram: MindmapDiagram, measured: MindmapMeasurement, centerAcross: CGFloat, top: CGFloat) -> MindmapLayoutNode {
        let size = measured.sizes[index]
        let frame = CGRect(x: centerAcross - size.width / 2, y: top, width: size.width, height: size.height)
        var text = measured.texts[index]
        text.center = CGPoint(x: frame.midX, y: frame.midY)
        let outline = measured.outlines[index]
        return MindmapLayoutNode(outline: outline, frame: frame, text: text, branchIndex: diagram.nodes[index].branchIndex,
                                 isTextLeftAligned: outline == .pill || outline == .text)
    }

    private static func placedNode(_ index: Int, diagram: MindmapDiagram, measured: MindmapMeasurement,
                                   placement: MindmapPlacement) -> MindmapLayoutNode {
        let size = measured.sizes[index]
        let frame = CGRect(x: placement.centersAcross[index] - size.width / 2, y: placement.tops[index], width: size.width, height: size.height)
        var text = measured.texts[index]
        text.center = CGPoint(x: frame.midX, y: frame.midY)
        return MindmapLayoutNode(outline: measured.outlines[index], frame: frame, text: text, branchIndex: diagram.nodes[index].branchIndex)
    }

    /// The S curve from the side of `index`'s parent that faces it to the side of `index` that faces the parent,
    /// each end on the outline at the side's middle.
    private static func edge(to index: Int, diagram: MindmapDiagram, nodes: [MindmapLayoutNode], placement: MindmapPlacement) -> MindmapLayoutEdge? {
        guard let parentIndex = diagram.nodes[index].parentIndex, let branchIndex = diagram.nodes[index].branchIndex else { return nil }
        let side = placement.sides[index]
        let parent = nodes[parentIndex]
        let child = nodes[index]
        let start = CGPoint(x: parent.frame.midX + side * (parent.frame.width / 2 - parent.outline.sideInset(size: parent.frame.size)), y: parent.frame.midY)
        let end = CGPoint(x: child.frame.midX - side * (child.frame.width / 2 - child.outline.sideInset(size: child.frame.size)), y: child.frame.midY)
        let middleAcross = (start.x + end.x) / 2
        let path = DiagramPath(start: start, segments: [.curve(to: end, control1: CGPoint(x: middleAcross, y: start.y),
                                                               control2: CGPoint(x: middleAcross, y: end.y))])
        return MindmapLayoutEdge(path: path, branchIndex: branchIndex)
    }

    /// The finished layout: everything moved so that the drawing starts `padding` from the top left, below the title,
    /// and centered under the title when the title is wider.
    private static func finished(nodes: [MindmapLayoutNode], edges: [MindmapLayoutEdge], title: DiagramTextBlock?, font: DiagramFont,
                                 seriesColors: DiagramSeriesColors) -> MindmapLayout {
        let bounds = nodes.reduce(CGRect.null) { bounds, node in bounds.union(node.frame) }
        let titleSize = title?.size ?? .zero
        let innerWidth = max(bounds.width, titleSize.width)
        let titleHeight = title == nil ? 0 : titleSize.height + titleGap
        let offset = CGVector(dx: padding + (innerWidth - bounds.width) / 2 - bounds.minX, dy: padding + titleHeight - bounds.minY)
        let size = CGSize(width: (innerWidth + 2 * padding).rounded(.up), height: (bounds.height + titleHeight + 2 * padding).rounded(.up))
        var placedTitle = title
        placedTitle?.center = CGPoint(x: size.width / 2, y: padding + titleSize.height / 2)
        var layout = MindmapLayout(size: size, font: font, nodes: nodes.map { node in node.translated(by: offset) },
                                   edges: edges.map { edge in edge.translated(by: offset) }, title: placedTitle)
        layout.seriesColors = seriesColors
        return layout
    }
}
