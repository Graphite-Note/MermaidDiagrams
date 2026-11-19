/**
 * File: PacketDiagramLayout.swift
 * -------------------------------
 * Layer: Core
 * Description: A laid-out packet diagram: its rows of fields on a grid of bits, the bit numbers above them, the title.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// A packet diagram laid out on a page whose origin is the top left corner and whose y runs down, in points: the fields
/// as boxes on a grid of bits, row below row, the first and last bit of each above it, and the title under the rows.
public struct PacketDiagramLayout: Equatable, Sendable {
    public let size: CGSize
    /// The font the text was measured in: the title at its size, the labels and bit numbers at their own sizes.
    public let font: DiagramFont
    /// The fields' boxes, row by row, a field that crosses a row's end in one box per row.
    public let fields: [PacketLayoutField]
    /// The bit numbers written above the boxes, in the order the boxes are: a one-bit field has one, another field
    /// its first and its last.
    public let bitNumbers: [DiagramTextBlock]
    /// The title under the rows, or nil.
    public let title: DiagramTextBlock?
}

/// One box of a packet diagram: the part of a field in one row.
public struct PacketLayoutField: Equatable, Sendable {
    public let frame: CGRect
    /// The bits the box covers.
    public let firstBit: Int
    public let lastBit: Int
    /// The label, shrunk or cut to fit the box; nil when not even one character fits, or the box is lower than the
    /// smallest label's size.
    public let label: DiagramTextBlock?
}
