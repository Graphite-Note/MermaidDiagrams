/**
 * File: PacketDiagramLayoutEngine.swift
 * -------------------------------------
 * Layer: Core
 * Description: Lays a packet diagram out with Pele's measurements, and again with fewer, narrower bits to a row for a
 *              container too narrow for it, as Pele turns one to fit.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 24/11/2026
 */

import CoreGraphics

/// Lays a packet diagram out in Pele's style: a grid of `bitsPerRow` bits of `bitWidth` points (32 and 32) in rows of
/// `rowHeight` (32), the gap `paddingX` (5) taken from each field's width and `paddingY` (5) between rows, a row's bit
/// numbers in 10-point text above it, labels at seven eighths of the size shrunk down to half of it and then cut, the
/// title in bold 12 points under the rows, and 8 points of page around them.
public enum PacketDiagramLayoutEngine {
    /// Around the whole diagram.
    static let padding: CGFloat = 8
    /// Between the rows and the title.
    static let titleGap: CGFloat = 12
    /// Between a bit number's baseline and the top of its row.
    static let bitNumberRise: CGFloat = 4
    /// What a label leaves of its field's width: the room on either side of it.
    static let labelMargin: CGFloat = 6
    /// The corners of the boxes, Pele's `--pele-radius`.
    static let cornerRadius: CGFloat = 4
    static let wrappingWidth: CGFloat = 4_000
    private static let labelScale: CGFloat = 0.875
    private static let bitNumberScale: CGFloat = 0.625
    private static let smallestLabelScale: CGFloat = 0.5

    public static func layout(_ diagram: PacketDiagram, typography: DiagramTypography) -> PacketDiagramLayout {
        layout(diagram, typography: typography, availableWidth: nil)
    }

    /// The diagram for a container `availableWidth` wide (nil for none), as Pele's `turnToFit` draws it: as written,
    /// and with fewer bits to a row (`PacketTurnedGrid`) when that does not fit a container under 640 points and is
    /// narrower.
    public static func layout(_ diagram: PacketDiagram, typography: DiagramTypography, availableWidth: CGFloat?) -> PacketDiagramLayout {
        DiagramWidthFitting.turnToFit(availableWidth: availableWidth, width: { (layout: PacketDiagramLayout) in layout.size.width }) { isTurned in
            layout(diagram, text: typography.nodeText, boldText: typography.boldNodeText, labelText: typography.edgeText, font: typography.font,
                   isTurned: isTurned, availableWidth: availableWidth)
        }
    }

    static func layout<Measurer: DiagramTextMeasuring>(_ diagram: PacketDiagram, text: Measurer, boldText: Measurer, font: DiagramFont) -> PacketDiagramLayout {
        layout(diagram, text: text, boldText: boldText, labelText: text, font: font, isTurned: false, availableWidth: nil)
    }

    /// The diagram as written, or turned (Pele's `down`) with `PacketTurnedGrid`'s rows for a container `availableWidth`
    /// wide: each field's label then wrapped into its box (`labelText`, seven eighths of the size) and each row
    /// as high as its tallest label, and the title wrapped to the container.
    static func layout<Measurer: DiagramTextMeasuring>(_ diagram: PacketDiagram, text: Measurer, boldText: Measurer, labelText: Measurer, font: DiagramFont,
                                                       isTurned: Bool, availableWidth: CGFloat?) -> PacketDiagramLayout {
        let options = diagram.options
        let size = text.fontSize
        let bitNumberSize = (size * bitNumberScale).rounded()
        let grid = isTurned ? PacketTurnedGrid(diagram, availableWidth: availableWidth, padding: padding)
            : PacketTurnedGrid(bitsPerRow: options.bitsPerRow, bitWidth: options.bitWidth)
        let rows = PacketFieldRows.rows(of: diagram.fields, bitsPerRow: grid.bitsPerRow)
        let labels = !isTurned ? nil : turnedLabels(of: diagram, rows: rows, grid: grid, measurer: labelText)
        let numbersHeight = options.showsBitNumbers ? bitNumberSize + bitNumberRise : 0
        let rowHeights = rows.indices.map { index in
            max(options.rowHeight, (labels?[index].map { label in (label?.size.height ?? 0) + turnedLabelRoom }.max()) ?? 0)
        }
        var tops: [CGFloat] = []
        var rowsHeight: CGFloat = 0
        for height in rowHeights {
            tops.append(rowsHeight)
            rowsHeight += numbersHeight + height + options.verticalPadding
        }
        if !rows.isEmpty { rowsHeight -= options.verticalPadding }
        let gap = min(options.horizontalPadding, grid.bitWidth - 1)
        let rowsWidth = rows.isEmpty ? 0 : CGFloat(grid.bitsPerRow) * grid.bitWidth - gap
        let titleWidth = isTurned ? DiagramWidthFitting.titleRoom(availableWidth: availableWidth) : wrappingWidth
        let title = diagram.title.map { title in
            DiagramTextBlock(label: DiagramLabelDecoder.label(from: title, form: .plain), measurer: boldText, maximumWidth: titleWidth)
        }.flatMap { block in block.lineCount == 0 ? nil : block }
        let titleHeight = title.map { title in title.size.height + (rowsHeight > 0 ? titleGap : 0) } ?? 0
        let left = padding + max(0, ((title?.size.width ?? 0) - rowsWidth) / 2)
        let placement = Grid(left: left, bitsPerRow: grid.bitsPerRow, bitWidth: grid.bitWidth, rowTops: tops, rowHeights: rowHeights,
                             numbersHeight: numbersHeight, gap: gap, bitNumberSize: bitNumberSize)
        let (boxes, bitNumbers) = fieldBoxes(of: diagram, rows: rows, grid: placement, turnedLabels: labels, text: text)
        let pageSize = CGSize(width: (max(rowsWidth, title?.size.width ?? 0) + 2 * padding).rounded(.up),
                              height: (rowsHeight + titleHeight + 2 * padding).rounded(.up))
        var placedTitle = title
        placedTitle?.center = CGPoint(x: pageSize.width / 2, y: pageSize.height - padding - (title?.size.height ?? 0) / 2)
        return PacketDiagramLayout(size: pageSize, font: font, fields: boxes, bitNumbers: bitNumbers, title: placedTitle)
    }

    /// What a turned row leaves above and below its tallest label.
    static let turnedLabelRoom: CGFloat = 10

    /// Each piece's label in a turned grid, row by row, as Pele's `literalLabel` sets a field's text: every character
    /// kept, wrapped at spaces or between characters to its box less the gap and the margin; nil for an empty label.
    private static func turnedLabels<Measurer: DiagramTextMeasuring>(of diagram: PacketDiagram, rows: [[PacketFieldPiece]], grid: PacketTurnedGrid,
                                                                      measurer: Measurer) -> [[DiagramTextBlock?]] {
        let gap = min(diagram.options.horizontalPadding, grid.bitWidth - 1)
        let texts = diagram.fields.map { field in DiagramLabelDecoder.decodingEntities(field.label).trimmingCharacters(in: .whitespacesAndNewlines) }
        return rows.map { row in
            row.map { piece in
                let room = max(1, CGFloat(piece.lastBit - piece.firstBit + 1) * grid.bitWidth - gap - labelMargin)
                let block = DiagramTextBlock(literal: texts[piece.fieldIndex], measurer: measurer, room: room)
                return block.lineCount == 0 ? nil : block
            }
        }
    }

    /// Where the grid of rows starts and how it is spaced.
    private struct Grid {
        let left: CGFloat
        let bitsPerRow: Int
        let bitWidth: CGFloat
        /// Each row's top below the page's padding, above its bit numbers, and its boxes' height.
        let rowTops: [CGFloat]
        let rowHeights: [CGFloat]
        let numbersHeight: CGFloat
        /// Taken from each box's width.
        let gap: CGFloat
        let bitNumberSize: CGFloat
    }

    /// The box of each piece of a field, with its fitted label, and the bit numbers above the boxes.
    private static func fieldBoxes<Measurer: DiagramTextMeasuring>(of diagram: PacketDiagram, rows: [[PacketFieldPiece]], grid: Grid,
                                                                    turnedLabels: [[DiagramTextBlock?]]?,
                                                                    text: Measurer) -> ([PacketLayoutField], [DiagramTextBlock]) {
        let options = diagram.options
        let size = text.fontSize
        var fitter = LabelFitter(labels: diagram.fields.map { field in
            DiagramLabelDecoder.decodingEntities(field.label).trimmingCharacters(in: .whitespacesAndNewlines)
        }, measurer: text, size: (size * labelScale).rounded(), smallestSize: (size * smallestLabelScale).rounded())
        let pieceCount = rows.reduce(0) { count, row in count + row.count }
        var boxes: [PacketLayoutField] = []
        boxes.reserveCapacity(pieceCount)
        var bitNumbers: [DiagramTextBlock] = []
        if options.showsBitNumbers { bitNumbers.reserveCapacity(2 * pieceCount) }
        var bitNumberMeasurers = DiagramTextMeasurerSizes(text)
        for (rowIndex, row) in rows.enumerated() {
            let top = padding + grid.rowTops[rowIndex] + grid.numbersHeight
            for (pieceIndex, piece) in row.enumerated() {
                let bitCount = piece.lastBit - piece.firstBit + 1
                let column = piece.firstBit % grid.bitsPerRow
                let x = grid.left + CGFloat(options.isDescending ? grid.bitsPerRow - column - bitCount : column) * grid.bitWidth
                let width = CGFloat(bitCount) * grid.bitWidth - grid.gap
                let frame = CGRect(x: x, y: top, width: width, height: grid.rowHeights[rowIndex])
                let label = turnedLabels.map { labels in
                    labels[rowIndex][pieceIndex].map { block in EventModelText.placed(block, center: CGPoint(x: frame.midX, y: frame.midY)) }
                } ?? fitter.block(of: piece.fieldIndex, width: width - labelMargin, in: frame)
                boxes.append(PacketLayoutField(frame: frame, firstBit: piece.firstBit, lastBit: piece.lastBit, label: label))
                if options.showsBitNumbers {
                    Self.addBitNumbers(of: piece, frame: frame, isDescending: options.isDescending, size: grid.bitNumberSize,
                                       measurers: &bitNumberMeasurers, to: &bitNumbers)
                }
            }
        }
        return (boxes, bitNumbers)
    }

    /// The numbers above a box: the bit alone, centered, for a one-bit box; else the box's first bit at its left end and its
    /// last at its right (the other way round when the bits count from the right).
    private static func addBitNumbers<Measurer: DiagramTextMeasuring>(of piece: PacketFieldPiece, frame: CGRect, isDescending: Bool, size: CGFloat,
                                                                      measurers: inout DiagramTextMeasurerSizes<Measurer>,
                                                                      to bitNumbers: inout [DiagramTextBlock]) {
        let centerY = frame.minY - bitNumberRise - size * DiagramTextDrawing.baselineShiftRatio
        if piece.firstBit == piece.lastBit {
            var block = measurers.block(of: String(piece.firstBit), fontSize: size)
            block.center = CGPoint(x: frame.midX, y: centerY)
            return bitNumbers.append(block)
        }
        var left = measurers.block(of: String(isDescending ? piece.lastBit : piece.firstBit), fontSize: size)
        left.center = CGPoint(x: frame.minX + left.size.width / 2, y: centerY)
        bitNumbers.append(left)
        var right = measurers.block(of: String(isDescending ? piece.firstBit : piece.lastBit), fontSize: size)
        right.center = CGPoint(x: frame.maxX - right.size.width / 2, y: centerY)
        bitNumbers.append(right)
    }

    /// Fits each field's label once for each width it is fitted at: the pieces of a field that crosses rows share its
    /// label, and most of them its width.
    private struct LabelFitter<Measurer: DiagramTextMeasuring> {
        let labels: [String]
        var measurers: DiagramTextMeasurerSizes<Measurer>
        let size: CGFloat
        let smallestSize: CGFloat
        private var fitted: [FitKey: DiagramFittedText?] = [:]

        private struct FitKey: Hashable {
            let fieldIndex: Int
            let width: CGFloat
        }

        init(labels: [String], measurer: Measurer, size: CGFloat, smallestSize: CGFloat) {
            self.labels = labels
            measurers = DiagramTextMeasurerSizes(measurer)
            self.size = size
            self.smallestSize = smallestSize
            fitted.reserveCapacity(labels.count)
        }

        /// The label of the field in `frame`, centered in it, or nil when there is none to draw: it is empty, not even a
        /// character of it fits `width`, or its size is more than the frame is high.
        mutating func block(of fieldIndex: Int, width: CGFloat, in frame: CGRect) -> DiagramTextBlock? {
            let key = FitKey(fieldIndex: fieldIndex, width: width)
            let fit: DiagramFittedText?
            if let known = fitted[key] {
                fit = known
            } else {
                fit = DiagramTextFitting.fitted(labels[fieldIndex], maximumWidth: width, fontSize: size, minimumFontSize: smallestSize, measurers: &measurers)
                fitted[key] = fit
            }
            guard let fit, fit.fontSize <= frame.height else { return nil }
            var block = fit.block
            block.center = CGPoint(x: frame.midX, y: frame.midY)
            return block
        }
    }
}
