/**
 * File: IshikawaOutlinePlacement.swift
 * ------------------------------------
 * Layer: Core
 * Description: Lays an Ishikawa diagram out down the page for a narrow column, as Pele's vertical causes: the effect,
 *              the categories and the causes as an indented list, each joined to its parent by an elbow.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

import CoreGraphics

/// The diagram down the page: entries in the order written, each 12 points below the last and set in a step per depth
/// (at most 20 points, less when the width needs it); the effect and the categories bold in outlined boxes, the causes at
/// seven eighths of the size; text broken between characters where a word is wider than its room; from under each
/// entry's parent, halfway into its step, a line down and across to it.
enum IshikawaOutlinePlacement {
    static let entryGap: CGFloat = 12

    static func layout<Measurer: DiagramTextMeasuring>(_ diagram: IshikawaDiagram, measurers: DiagramTextMeasurerSet<Measurer>, font: DiagramFont,
                                                       maximumWidth: CGFloat) -> IshikawaLayout {
        let padding = IshikawaLayoutEngine.padding
        let room = max(140, maximumWidth - 2 * padding)
        let title = diagram.title.map { title in DiagramTextBlock(label: DiagramLabel(title), measurer: measurers.bold, maximumWidth: max(80, maximumWidth - 2 * padding)) }
        let order = depthFirstOrder(diagram)
        let deepest = order.map(\.depth).max() ?? 0
        let indent = min(20, max(2, (room - 120) / CGFloat(max(1, deepest))))
        let titleHeight = title.map { title in title.lineCount == 0 ? 0 : title.size.height + IshikawaLayoutEngine.titleGap } ?? 0
        var top = padding + titleHeight
        var width = title?.size.width ?? 0
        var entries: [IshikawaLayoutOutlineEntry] = []
        var connectors: [DiagramPath] = []
        for (nodeIndex, depth, parentEntry) in order {
            let left = padding + CGFloat(depth) * indent
            let textRoom = max(60, room - CGFloat(depth) * indent - 20)
            var text = DiagramTextBlock(label: DiagramLabelDecoder.label(from: diagram.nodes[nodeIndex].text, form: .plain),
                                        measurer: depth < 2 ? measurers.bold : measurers.small, fittingWidth: textRoom)
            let frame = CGRect(x: left, y: top, width: text.size.width + 20, height: text.size.height + 12)
            text.center = CGPoint(x: frame.midX, y: frame.midY)
            entries.append(IshikawaLayoutOutlineEntry(depth: depth, frame: frame, text: text))
            top += frame.height + entryGap
            width = max(width, left - padding + frame.width)
            if let parentEntry {
                let parent = entries[parentEntry].frame
                let across = parent.minX + indent / 2
                connectors.append(DiagramPath(start: CGPoint(x: across, y: parent.maxY),
                                              segments: [.line(to: CGPoint(x: across, y: frame.midY)), .line(to: CGPoint(x: frame.minX, y: frame.midY))]))
            }
        }
        let size = CGSize(width: (width + 2 * padding).rounded(.up),
                          height: (max(padding + (title?.size.height ?? 0), top - entryGap) + padding).rounded(.up))
        var placedTitle = title
        placedTitle?.center = CGPoint(x: size.width / 2, y: padding + (title?.size.height ?? 0) / 2)
        return IshikawaLayout(size: size, font: font, title: placedTitle, spine: nil, spineArrow: nil, categories: [], head: nil,
                              outlineEntries: entries, outlineConnectors: connectors)
    }

    /// The nodes in the order written, each with its depth and its parent's place in that order, walked with a stack of
    /// its own so that the outline may be as deep as the text goes.
    private static func depthFirstOrder(_ diagram: IshikawaDiagram) -> [(nodeIndex: Int, depth: Int, parentEntry: Int?)] {
        var order: [(nodeIndex: Int, depth: Int, parentEntry: Int?)] = []
        var pending: [(nodeIndex: Int, depth: Int, parentEntry: Int?)] = diagram.nodes.isEmpty ? [] : [(0, 0, nil)]
        while let entry = pending.popLast() {
            let entryIndex = order.count
            order.append(entry)
            for child in diagram.nodes[entry.nodeIndex].childIndices.reversed() { pending.append((child, entry.depth + 1, entryIndex)) }
        }
        return order
    }
}
