/**
 * File: FlowchartMeasuredRecords.swift
 * ------------------------------------
 * Layer: Core
 * Description: A flowchart's measured node as one flat record (its text placed without a storage reference, its shape's
 *              size and its text's offset), and the views that read a measurement's records as lists of blocks, sizes
 *              and offsets for a reader that indexes them so.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics

/// A node measured: its text, placed in the measurement's storages with no center yet, its shape's size, and how far
/// below the shape's center its text's center is.
struct FlowchartMeasuredNode: Sendable {
    let text: DiagramPlacedText
    let shapeSize: CGSize
    let textOffset: CGFloat
}

/// The measured nodes' texts as blocks, each made when it is read.
struct FlowchartMeasuredNodeTexts: RandomAccessCollection {
    let records: [FlowchartMeasuredNode]
    let storages: DiagramPlacedTextStorages

    var startIndex: Int { 0 }
    var endIndex: Int { records.count }

    subscript(node: Int) -> DiagramTextBlock { storages.block(records[node].text) }
}

/// The measured nodes' shapes' sizes.
struct FlowchartMeasuredShapeSizes: RandomAccessCollection {
    let records: [FlowchartMeasuredNode]

    var startIndex: Int { 0 }
    var endIndex: Int { records.count }

    subscript(node: Int) -> CGSize { records[node].shapeSize }
}

/// How far below each measured node's shape's center its text's center is.
struct FlowchartMeasuredTextOffsets: RandomAccessCollection {
    let records: [FlowchartMeasuredNode]

    var startIndex: Int { 0 }
    var endIndex: Int { records.count }

    subscript(node: Int) -> CGFloat { records[node].textOffset }
}

/// The measured edges' texts as blocks, or nil for an edge without text, each made when it is read.
struct FlowchartMeasuredEdgeTexts: RandomAccessCollection {
    let records: [DiagramPlacedText?]
    let storages: DiagramPlacedTextStorages

    var startIndex: Int { 0 }
    var endIndex: Int { records.count }

    subscript(edgeIndex: Int) -> DiagramTextBlock? { records[edgeIndex].map { text in storages.block(text) } }
}
