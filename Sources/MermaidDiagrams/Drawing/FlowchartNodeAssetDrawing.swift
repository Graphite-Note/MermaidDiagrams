/**
 * File: FlowchartNodeAssetDrawing.swift
 * -------------------------------------
 * Layer: Core
 * Description: The frame drawn for a flowchart node shown as an icon: a square, a circle or a rounded square around
 *              where the icon goes, as Pele draws an icon node's form.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 26/11/2026
 */

import CoreGraphics

/// The outline Pele draws for a node shown as an icon or a picture (flowchart/render.ts): an icon's form, filled and
/// stroked as a shape is, around a square of the box's height (`h:`, else 48); nothing for an icon without a form, nor
/// for a picture. The icon itself is the host's drawing in Pele and is not drawn without one; the package has none.
enum FlowchartNodeAssetDrawing {
    /// Pele's corner radius of a rounded icon frame.
    static let roundedCornerRadius: CGFloat = 8

    static func frame(of asset: FlowchartNodeAsset, in node: FlowchartLayoutNode) -> CGPath? {
        frame(of: asset, in: node, making: DiagramCoreGraphicsPaths())?.path
    }

    /// The frame made by `maker`: a Core Graphics path or a lane.
    static func frame<Maker: DiagramPathMaking>(of asset: FlowchartNodeAsset, in node: FlowchartLayoutNode, making maker: Maker) -> Maker.Path? {
        frame(of: asset, in: node.frame, hasLabel: node.text.lineCount > 0, making: maker)
    }

    /// The frame of a node whose shape's box is `nodeFrame`, with a text or without.
    static func frame<Maker: DiagramPathMaking>(of asset: FlowchartNodeAsset, in nodeFrame: CGRect, hasLabel: Bool, making maker: Maker) -> Maker.Path? {
        guard case .icon = asset.kind else { return nil }
        let box = asset.box(in: nodeFrame, hasLabel: hasLabel)
        switch asset.form {
        case .none: return nil
        case .square: return maker.rectangle(box)
        case .circle: return maker.ellipse(in: box)
        case .rounded:
            let radius = min(roundedCornerRadius, box.width / 2, box.height / 2)
            return maker.roundedRectangle(box, cornerWidth: radius, cornerHeight: radius)
        }
    }
}
