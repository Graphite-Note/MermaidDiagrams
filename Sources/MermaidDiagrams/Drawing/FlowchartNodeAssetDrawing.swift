/**
 * File: FlowchartNodeAssetDrawing.swift
 * -------------------------------------
 * Layer: Core
 * Description: The frame drawn for a flowchart node shown as an icon: a square, a circle or a rounded square around
 *              where the icon goes, as Pele draws an icon node's form.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import CoreGraphics

/// The outline Pele draws for a node shown as an icon or a picture (flowchart/render.ts): an icon's form, filled and
/// stroked as a shape is, around a square of the box's height (`h:`, else 48); nothing for an icon without a form, nor
/// for a picture. The icon itself is the host's drawing in Pele and is not drawn without one; the package has none.
enum FlowchartNodeAssetDrawing {
    /// Pele's corner radius of a rounded icon frame.
    static let roundedCornerRadius: CGFloat = 8

    static func frame(of asset: FlowchartNodeAsset, in node: FlowchartLayoutNode) -> DiagramScenePath? {
        guard case .icon = asset.kind else { return nil }
        let box = asset.box(in: node.frame, hasLabel: !node.text.lines.isEmpty)
        switch asset.form {
        case .none: return nil
        case .square: return DiagramScenePath(rect: box)
        case .circle: return DiagramScenePath(ellipseIn: box)
        case .rounded:
            let radius = min(roundedCornerRadius, box.width / 2, box.height / 2)
            return DiagramScenePath(roundedRect: box, cornerWidth: radius, cornerHeight: radius)
        }
    }
}
