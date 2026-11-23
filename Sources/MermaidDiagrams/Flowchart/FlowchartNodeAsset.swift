/**
 * File: FlowchartNodeAsset.swift
 * ------------------------------
 * Layer: Core
 * Description: A flowchart node drawn as an icon or an image (@{ icon: …, form: …, pos: …, h: … }, @{ img: … }), its
 *              size around its label and where its box and label sit, as Pele's flowchart lays such a node out.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import CoreGraphics

/// What a node written with `icon:` or `img:` among its attributes shows instead of its shape, Pele's icon and image
/// shapes (flowchart/graph.ts `shapeOf`, render.ts): a box the icon or picture fills, its label above it (`pos: t`) or
/// below it, the node as wide as the wider of the two. An image wins over an icon.
public struct FlowchartNodeAsset: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// An icon by name (`fa:user`). Pele draws it only when the host has an icon by that name; it ships none, and
        /// neither does the package, so only its frame is drawn.
        case icon(name: String)
        /// A picture at an address. The package draws no picture (it reads no file and fetches nothing); the node keeps
        /// its room, as Pele's does when its picture does not load.
        case image(address: String)
    }

    /// The frame around an icon (`form:`): none, a square, a circle, or a square with rounded corners.
    public enum Form: Equatable, Sendable {
        case none
        case square
        case circle
        case rounded
    }

    public let kind: Kind
    public let form: Form
    /// Whether the label sits above the box (`pos: t`) rather than below it.
    public let isLabelAbove: Bool
    /// The written width (`w:`) and height (`h:`), when they are a number above zero and at most 4,000.
    public let writtenWidth: CGFloat?
    public let writtenHeight: CGFloat?
    /// Whether a picture keeps its proportions in its box (`constraint: on`).
    public let keepsProportions: Bool

    init(kind: Kind, form: Form = .none, isLabelAbove: Bool = false, writtenWidth: CGFloat? = nil, writtenHeight: CGFloat? = nil,
         keepsProportions: Bool = false) {
        self.kind = kind
        self.form = form
        self.isLabelAbove = isLabelAbove
        self.writtenWidth = writtenWidth.flatMap(Self.validSide)
        self.writtenHeight = writtenHeight.flatMap(Self.validSide)
        self.keepsProportions = keepsProportions
    }

    /// Pele's `assetSize`: a side above zero and at most 4,000, or none.
    private static func validSide(_ side: CGFloat) -> CGFloat? {
        side > 0 && side <= 4_000 ? side : nil
    }

    /// The side Pele gives the box when none is written: 80 for a picture, 48 for an icon.
    private var standardSide: CGFloat {
        if case .image = kind { return 80 }
        return 48
    }

    /// The box the icon or picture fills: as wide as written (else the standard side), as high as written (else the
    /// standard side). An icon's frame is a square of the box's height.
    var boxSize: CGSize {
        CGSize(width: writtenWidth ?? standardSide, height: writtenHeight ?? standardSide)
    }

    /// The node's size around a label of `textSize`, and how far below the node's center the label's center is: the box
    /// and the label (6 points apart) stacked, as wide as the wider of the box and the label with 4 points each side.
    func size(textSize: CGSize) -> (size: CGSize, textOffset: CGFloat) {
        let box = boxSize
        guard textSize.height > 0 else { return (CGSize(width: max(box.width, textSize.width + 8), height: box.height), 0) }
        let size = CGSize(width: max(box.width, textSize.width + 8), height: box.height + textSize.height + 6)
        return (size, isLabelAbove ? -box.height / 2 : box.height / 2)
    }

    /// The icon's frame, or the picture's box, in a node whose bounding box is `frame`: at the node's top when the label
    /// is below it, at its bottom when the label is above, in its middle when there is no label.
    func box(in frame: CGRect, hasLabel: Bool) -> CGRect {
        let box = boxSize
        let side = isImage ? box : CGSize(width: box.height, height: box.height)
        let top = !hasLabel ? frame.midY - side.height / 2 : (isLabelAbove ? frame.maxY - side.height : frame.minY)
        return CGRect(x: frame.midX - side.width / 2, y: top, width: side.width, height: side.height)
    }

    private var isImage: Bool {
        if case .image = kind { return true }
        return false
    }
}

/// The attributes of a node that make it an icon or a picture, as Pele's flowchart database keeps them on the node: each
/// written attribute replaces the one before (`A@{ icon: "fa:user" }` and later `A@{ form: circle }` make a circled icon).
struct FlowchartNodeAssetAttributes: Equatable, Sendable {
    var icon: String?
    var image: String?
    var form: String?
    var position: String?
    var width: Double?
    var height: Double?
    var constraint: String?

    /// The icon or picture the attributes ask for, or nil when they name neither.
    var asset: FlowchartNodeAsset? {
        let kind: FlowchartNodeAsset.Kind
        if let image { kind = .image(address: image) } else if let icon { kind = .icon(name: icon) } else { return nil }
        let shapedForm: FlowchartNodeAsset.Form = switch form {
        case "circle": .circle
        case "square": .square
        case "rounded": .rounded
        default: .none
        }
        return FlowchartNodeAsset(kind: kind, form: shapedForm, isLabelAbove: position == "t", writtenWidth: width.map { CGFloat($0) },
                                  writtenHeight: height.map { CGFloat($0) }, keepsProportions: constraint == "on")
    }
}
