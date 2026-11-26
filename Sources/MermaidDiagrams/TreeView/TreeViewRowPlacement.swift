/**
 * File: TreeViewRowPlacement.swift
 * --------------------------------
 * Layer: Core
 * Description: Where each of a tree view's rows goes: its step in, its height, its name and description measured from
 *              the diagram's text, and the guide lines from each folder to its entries, as flat records.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 26/11/2026
 */

import CoreGraphics

/// A tree view's rows measured and stacked, before they are moved inside the page's padding and below its title. The
/// rows are the entries in the order written, which is the order a walk down the tree from the top meets them.
struct TreeViewRowPlacement<Measurer: DiagramTextMeasuring> {
    struct Row {
        /// Where the row's icon starts and where its name starts, from the tree's left.
        var left: CGFloat
        var nameLeft: CGFloat
        var top: CGFloat
        var height: CGFloat
        /// The middle of the row's first line, where its icon is centered.
        var middle: CGFloat
        var name: DiagramMeasuredText
        var description: DiagramMeasuredText
    }

    private(set) var rows: [Row] = []
    private(set) var lines = DiagramMeasuredLines()
    private(set) var width: CGFloat = 0
    private(set) var height: CGFloat = 0
    private(set) var hasHighlight = false
    /// The right end of the widest name, from the tree's left.
    private var namesRight: CGFloat = 0
    private let step: CGFloat
    private let paddingAcross: CGFloat
    private let paddingDown: CGFloat
    private let tightWidth: CGFloat?
    private let measurers: DiagramTextMeasurerSet<Measurer>

    init(_ diagram: TreeViewDiagram, measurers: DiagramTextMeasurerSet<Measurer>, tightWidth: CGFloat?) {
        let options = diagram.options
        self.measurers = measurers
        self.tightWidth = tightWidth
        paddingAcross = CGFloat(options.paddingAcross)
        paddingDown = CGFloat(options.paddingDown)
        let looseStep = CGFloat(options.rowIndent) + paddingAcross
        step = tightWidth.map { width in min(looseStep, max(2, (width - 120) / CGFloat(max(1, diagram.deepestDepth)))) } ?? looseStep
        let records = diagram.records
        rows.reserveCapacity(records.count)
        lines.reserveCapacity(lines: 2 * records.count, derivedBytes: 0)
        // Each group of siblings, the top's at 0 and an entry's children after its index, leaves room for an icon when
        // one of them shows an icon.
        var siblingsShowIcon = [Bool](repeating: false, count: records.count + 1)
        for record in records where record.glyph != nil { siblingsShowIcon[Int(record.parentIndex) + 1] = true }
        diagram.text.withUnsafeBufferPointer { text in
            for record in records { addRow(of: record, leavesIconRoom: siblingsShowIcon[Int(record.parentIndex) + 1], text: text) }
        }
        width = namesRight
        let descriptionsLeft = namesRight + TreeViewLayoutEngine.descriptionGap
        for (row, record) in zip(rows, records) where record.hasDescription {
            width = max(width, (tightWidth != nil ? row.nameLeft : descriptionsLeft) + row.description.width)
        }
    }

    /// An entry's row below the rows so far: set in its step, its name after its icon's room when its siblings leave one,
    /// one row high, or in a tight layout as high as its name and its description under it.
    private mutating func addRow(of record: TreeViewEntryRecord, leavesIconRoom: Bool, text: UnsafeBufferPointer<UInt8>) {
        let iconSide = measurers.regular.fontSize
        let rowHeight = measurers.regular.lineHeight + 2 * paddingDown
        let left = CGFloat(record.depth) * step
        let nameLeft = left + (leavesIconRoom ? iconSide + TreeViewLayoutEngine.iconGap : 0)
        let room = tightWidth.map { width in
            max(40, width - 2 * TreeViewLayoutEngine.padding - 2 * TreeViewLayoutEngine.highlightOverhang - nameLeft)
        }
        let name = measured(record.name, of: text, measurer: record.isFolder ? measurers.bold : measurers.regular, room: room)
        let description = record.hasDescription ? measured(record.description, of: text, measurer: measurers.regular, room: room)
            : DiagramMeasuredText(firstLine: Int32(lines.count), lineCount: 0, width: 0, height: 0, lineHeight: 0, fontSize: 0)
        let isTight = tightWidth != nil
        let rowHeightHere = isTight ? max(rowHeight, name.height + description.height + 2 * paddingDown) : rowHeight
        let middle = height + (isTight ? paddingDown + max(iconSide, name.height) / 2 : rowHeightHere / 2)
        rows.append(Row(left: left, nameLeft: nameLeft, top: height, height: rowHeightHere, middle: middle, name: name, description: description))
        namesRight = max(namesRight, nameLeft + name.width)
        hasHighlight = hasHighlight || record.isHighlighted
        height += rowHeightHere
    }

    /// `text[range]` as one line as written, its entities read, or for a tight layout literal lines that fit `room`.
    private mutating func measured(_ range: MermaidTextRange, of text: UnsafeBufferPointer<UInt8>, measurer: Measurer, room: CGFloat?) -> DiagramMeasuredText {
        let bytes = UnsafeBufferPointer(rebasing: text[range.lowerBound..<range.upperBound])
        // Without a semicolon the text holds no entity: it is drawn as written (`DiagramLabelEntities.decoded`).
        guard room != nil || bytes.contains(MermaidByte.semicolon) else {
            let firstLine = Int32(lines.count)
            guard !bytes.isEmpty else { return emptyText(firstLine: firstLine, measurer: measurer) }
            lines.appendLine(start: range.lowerBound, end: range.upperBound, width: Self.width(of: bytes, measurer: measurer))
            return DiagramMeasuredText(firstLine: firstLine, lineCount: 1, width: lines[Int(firstLine)].width, height: measurer.lineHeight,
                                       lineHeight: measurer.lineHeight, fontSize: measurer.fontSize)
        }
        let decoded = DiagramLabelDecoder.decodingEntities(String(decoding: bytes, as: UTF8.self))
        if let room { return DiagramFlatTextMeasuring.copied(DiagramTextBlock(literal: decoded, measurer: measurer, room: room), into: &lines) }
        guard !decoded.isEmpty else { return emptyText(firstLine: Int32(lines.count), measurer: measurer) }
        return DiagramFlatTextMeasuring.copied(DiagramTextBlock(lines: [decoded], lineWidths: [measurer.width(of: decoded)], fontSize: measurer.fontSize,
                                                                lineHeight: measurer.lineHeight), into: &lines)
    }

    /// An empty name: no line, the measurer's size and line height.
    private func emptyText(firstLine: Int32, measurer: Measurer) -> DiagramMeasuredText {
        DiagramMeasuredText(firstLine: firstLine, lineCount: 0, width: 0, height: 0, lineHeight: measurer.lineHeight, fontSize: measurer.fontSize)
    }

    /// The width of `bytes` on one line, as `measurer.width(of:)` gives it for their String.
    private static func width(of bytes: UnsafeBufferPointer<UInt8>, measurer: Measurer) -> CGFloat {
        if let coreText = measurer as? CoreTextDiagramTextMeasurer { return coreText.face.width(ofUTF8: bytes) }
        return measurer.width(of: String(decoding: bytes, as: UTF8.self))
    }

    /// Each folder's guide: from just under its row down to its last entry's middle, turning there with a rounded elbow
    /// to the step's end, and a line across to each other entry.
    func guides(_ diagram: TreeViewDiagram, origin: CGPoint) -> [TreeViewGuideStroke] {
        var strokes: [TreeViewGuideStroke] = []
        strokes.reserveCapacity(rows.count)
        for (row, record) in zip(rows, diagram.records) where record.lastChildIndex >= 0 {
            let across = origin.x + row.left + TreeViewLayoutEngine.guideInset
            let tick = max(across, origin.x + row.left + step - paddingAcross)
            let lastMiddle = origin.y + rows[Int(record.lastChildIndex)].middle
            strokes.append(TreeViewGuideStroke(isElbow: true, across: across, top: origin.y + row.top + row.height - 2, bottom: lastMiddle,
                                               radius: min(TreeViewLayoutEngine.elbowRadius, tick - across), tick: tick))
            guard tick > across else { continue }
            var child = record.firstChildIndex
            while child >= 0, child != record.lastChildIndex {
                strokes.append(TreeViewGuideStroke(isElbow: false, across: across, top: 0, bottom: origin.y + rows[Int(child)].middle, radius: 0, tick: tick))
                child = diagram.records[Int(child)].nextSiblingIndex
            }
        }
        return strokes
    }

    func placedRows(_ diagram: TreeViewDiagram, origin: CGPoint, pageWidth: CGFloat) -> [TreeViewPlacedRow] {
        let descriptionsLeft = namesRight + TreeViewLayoutEngine.descriptionGap
        let isTight = tightWidth != nil
        return zip(rows, diagram.records).enumerated().map { index, pair in
            let (row, record) = pair
            let iconSide = row.name.fontSize
            let highlightLeft = origin.x + row.left - TreeViewLayoutEngine.highlightOverhang
            let highlight = CGRect(x: highlightLeft, y: origin.y + row.top + 1, width: pageWidth - origin.x + TreeViewLayoutEngine.highlightOverhang - highlightLeft,
                                   height: row.height - 2)
            let nameTop = isTight ? origin.y + row.top + paddingDown : origin.y + row.middle - row.name.lineHeight / 2
            return TreeViewPlacedRow(entryIndex: Int32(index), isFolder: record.isFolder, isHighlighted: record.isHighlighted, glyph: record.glyph,
                                     highlight: highlight,
                                     glyphFrame: CGRect(x: origin.x + row.left, y: origin.y + row.middle - iconSide / 2, width: iconSide, height: iconSide),
                                     name: row.name, nameLeft: origin.x + row.nameLeft, nameTop: nameTop, description: row.description,
                                     descriptionLeft: isTight ? origin.x + row.nameLeft : origin.x + descriptionsLeft,
                                     descriptionTop: isTight ? nameTop + row.name.height : origin.y + row.middle - row.description.lineHeight / 2)
        }
    }
}
