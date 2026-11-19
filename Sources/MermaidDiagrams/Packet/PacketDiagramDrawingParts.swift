/**
 * File: PacketDiagramDrawingParts.swift
 * -------------------------------------
 * Layer: Core
 * Description: A laid-out packet diagram's geometry grouped by how it is painted.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// A laid-out packet diagram's geometry grouped by how it is painted, so that drawing it in any colors is a fill, a stroke
/// and some text, by Core Graphics (`PacketDiagramRenderer`) or by a view's own shapes. Back to front, as Pele draws:
/// the fields' boxes, their labels, the bit numbers, the title.
public struct PacketDiagramDrawingParts {
    /// The fields' boxes with rounded corners, filled in the surface color and outlined in the border color.
    public let fieldBoxes: CGPath
    /// The fields' labels, drawn in the text color.
    public let fieldLabels: [DiagramTextBlock]
    /// The bit numbers, drawn in the muted color.
    public let bitNumbers: [DiagramTextBlock]
    /// The title, drawn bold, or nil.
    public let title: DiagramTextBlock?

    public static let lineWidth: CGFloat = 1

    public init(layout: PacketDiagramLayout) {
        let boxes = CGMutablePath()
        for field in layout.fields {
            let radius = min(PacketDiagramLayoutEngine.cornerRadius, field.frame.width / 2, field.frame.height / 2)
            boxes.addRoundedRect(in: field.frame, cornerWidth: radius, cornerHeight: radius)
        }
        fieldBoxes = boxes
        fieldLabels = layout.fields.compactMap(\.label)
        bitNumbers = layout.bitNumbers
        title = layout.title
    }
}
