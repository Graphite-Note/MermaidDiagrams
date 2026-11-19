/**
 * File: WardleyMapNodePlacement.swift
 * -----------------------------------
 * Layer: Core
 * Description: A Wardley map's anchors and components as Pele's draw() places them: their shapes, inertia bars and
 *              labels, a component's label in the first corner around it no link leaves through.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

import CoreGraphics

extension WardleyMapPlacement {
    /// How far a label stands up and right of its component, and how much farther from a sourced one's ring.
    static var labelLift: CGFloat { 8 }
    static var sourcedLabelLift: CGFloat { 10 }
    /// The farthest a written label offset moves a label, each way.
    static var largestLabelOffset: Double { 5_000 }
    /// An inertia bar's width, and its gap from the node.
    static var inertiaWidth: CGFloat { 4 }
    static var inertiaGap: CGFloat { 10 }

    /// Each node in the map's order: its shape, its inertia bar, its label, and the room around it taken in.
    mutating func placeNodes() {
        let radius = Self.componentRadius
        for (index, node) in map.nodes.enumerated() {
            let center = positions[index]
            let shape: WardleyMapLayoutNode.Shape = node.sourcing == .market || node.kind == .anchor ? .none : node.isPipelineParent ? .square : .circle
            var inertia: CGRect?
            if node.hasInertia {
                let gap = (node.isPipelineParent ? Self.squareSide / 2 : radius) + Self.inertiaGap + (node.sourcing != nil ? radius + 4 : 0)
                inertia = CGRect(x: center.x + gap, y: center.y - radius, width: Self.inertiaWidth, height: 2 * radius)
            }
            let label = placedLabel(of: node, index: index, at: center)
            canvas.grow(center.x - 2 * radius, center.y - 2 * radius, center.x + 2 * radius + 20, center.y + 2 * radius)
            layout.nodes.append(WardleyMapLayoutNode(center: center, shape: shape, sourcing: node.sourcing, inertia: inertia, label: label, isAnchor: node.kind == .anchor))
        }
    }

    /// An anchor's bold name centered on it, 3 points up; a component's label from its written offset, under it in a
    /// pipeline, or else from the first corner around it (up and right, down and right, up and left, down and left) that
    /// no link runs through.
    private mutating func placedLabel(of node: WardleyMapNode, index: Int, at center: CGPoint) -> [DiagramTextBlock] {
        let offsetX = node.labelOffsetX.map { offset in CGFloat(min(max(offset, -Self.largestLabelOffset), Self.largestLabelOffset)) }
        let offsetY = node.labelOffsetY.map { offset in CGFloat(min(max(offset, -Self.largestLabelOffset), Self.largestLabelOffset)) }
        if node.kind == .anchor {
            guard let label = anchorLabels[index] else { return [] }
            return [canvas.centered(label, at: CGPoint(x: center.x + (offsetX ?? 0), y: center.y + (offsetY ?? -3)))]
        }
        guard let label = PlaneMapLabel.block(node.label, measurer: measurers.text, maximumWidth: canvas.textWidth) else { return [] }
        let lift = Self.labelLift + (node.sourcing != nil ? Self.sourcedLabelLift : 0)
        if offsetX != nil || offsetY != nil {
            return canvas.starting(label, x: center.x + (offsetX ?? lift), baseline: center.y + (offsetY ?? -lift))
        }
        if node.isInPipeline {
            return [canvas.centered(label, at: CGPoint(x: center.x, y: center.y + 2 * Self.componentRadius + 4 + label.size.height / 2))]
        }
        let taken = takenQuadrants[index]
        let corner = [1, 2, 4, 8].first { quadrant in taken & quadrant == 0 } ?? 1
        let isRight = corner == 1 || corner == 2
        let isUp = corner == 1 || corner == 4
        return canvas.starting(label, x: isRight ? center.x + lift : center.x - lift - label.size.width,
                               baseline: isUp ? center.y - lift : center.y + lift + measurers.text.fontSize * 0.75)
    }
}
