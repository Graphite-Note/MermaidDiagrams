/**
 * File: PacketDiagramLayoutEngine.swift
 * -------------------------------------
 * Layer: Core
 * Description: Lays a packet diagram out with Pele's measurements.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
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
        layout(diagram, text: typography.nodeText, boldText: typography.boldNodeText, font: typography.font)
    }

    static func layout<Measurer: DiagramTextMeasuring>(_ diagram: PacketDiagram, text: Measurer, boldText: Measurer, font: DiagramFont) -> PacketDiagramLayout {
        let options = diagram.options
        let size = text.fontSize
        let bitNumberSize = (size * bitNumberScale).rounded()
        let rows = PacketFieldRows.rows(of: diagram.fields, bitsPerRow: options.bitsPerRow)
        let numbersHeight = options.showsBitNumbers ? bitNumberSize + bitNumberRise : 0
        let rowPitch = numbersHeight + options.rowHeight + options.verticalPadding
        let gap = min(options.horizontalPadding, options.bitWidth - 1)
        let rowsHeight = rows.isEmpty ? 0 : CGFloat(rows.count) * rowPitch - options.verticalPadding
        let rowsWidth = rows.isEmpty ? 0 : CGFloat(options.bitsPerRow) * options.bitWidth - gap
        let title = diagram.title.map { title in
            DiagramTextBlock(label: DiagramLabelDecoder.label(from: title, form: .plain), measurer: boldText, maximumWidth: wrappingWidth)
        }.flatMap { block in block.lines.isEmpty ? nil : block }
        let titleHeight = title.map { title in title.size.height + (rowsHeight > 0 ? titleGap : 0) } ?? 0
        let left = padding + max(0, ((title?.size.width ?? 0) - rowsWidth) / 2)
        let grid = Grid(left: left, rowPitch: rowPitch, numbersHeight: numbersHeight, gap: gap, bitNumberSize: bitNumberSize)
        let (boxes, bitNumbers) = fieldBoxes(of: diagram, rows: rows, grid: grid, text: text)
        let pageSize = CGSize(width: (max(rowsWidth, title?.size.width ?? 0) + 2 * padding).rounded(.up),
                              height: (rowsHeight + titleHeight + 2 * padding).rounded(.up))
        var placedTitle = title
        placedTitle?.center = CGPoint(x: pageSize.width / 2, y: pageSize.height - padding - (title?.size.height ?? 0) / 2)
        return PacketDiagramLayout(size: pageSize, font: font, fields: boxes, bitNumbers: bitNumbers, title: placedTitle)
    }

    /// Where the grid of rows starts and how it is spaced.
    private struct Grid {
        let left: CGFloat
        let rowPitch: CGFloat
        let numbersHeight: CGFloat
        /// Taken from each box's width.
        let gap: CGFloat
        let bitNumberSize: CGFloat
    }

    /// The box of each piece of a field, with its fitted label, and the bit numbers above the boxes.
    private static func fieldBoxes<Measurer: DiagramTextMeasuring>(of diagram: PacketDiagram, rows: [[PacketFieldPiece]], grid: Grid,
                                                                    text: Measurer) -> ([PacketLayoutField], [DiagramTextBlock]) {
        let options = diagram.options
        let size = text.fontSize
        var fitter = LabelFitter(labels: diagram.fields.map { field in
            DiagramLabelDecoder.decodingEntities(field.label).trimmingCharacters(in: .whitespacesAndNewlines)
        }, measurer: text, size: (size * labelScale).rounded(), smallestSize: (size * smallestLabelScale).rounded())
        var boxes: [PacketLayoutField] = []
        var bitNumbers: [DiagramTextBlock] = []
        var bitNumberMeasurers = DiagramTextMeasurerSizes(text)
        for (rowIndex, row) in rows.enumerated() {
            let top = padding + CGFloat(rowIndex) * grid.rowPitch + grid.numbersHeight
            for piece in row {
                let bitCount = piece.lastBit - piece.firstBit + 1
                let column = piece.firstBit % options.bitsPerRow
                let x = grid.left + CGFloat(options.isDescending ? options.bitsPerRow - column - bitCount : column) * options.bitWidth
                let width = CGFloat(bitCount) * options.bitWidth - grid.gap
                let frame = CGRect(x: x, y: top, width: width, height: options.rowHeight)
                boxes.append(PacketLayoutField(frame: frame, firstBit: piece.firstBit, lastBit: piece.lastBit,
                                               label: fitter.block(of: piece.fieldIndex, width: width - labelMargin, in: frame)))
                if options.showsBitNumbers {
                    bitNumbers += Self.bitNumbers(piece, frame: frame, isDescending: options.isDescending, size: grid.bitNumberSize,
                                                  measurers: &bitNumberMeasurers)
                }
            }
        }
        return (boxes, bitNumbers)
    }

    /// The numbers above a box: the bit alone, centered, for a one-bit box; else the box's first bit at its left end and its
    /// last at its right (the other way round when the bits count from the right).
    private static func bitNumbers<Measurer: DiagramTextMeasuring>(_ piece: PacketFieldPiece, frame: CGRect, isDescending: Bool, size: CGFloat,
                                                                   measurers: inout DiagramTextMeasurerSizes<Measurer>) -> [DiagramTextBlock] {
        let centerY = frame.minY - bitNumberRise - size * DiagramTextDrawing.baselineShiftRatio
        func number(_ bit: Int, centerX: (CGFloat) -> CGFloat) -> DiagramTextBlock {
            var block = measurers.block(of: String(bit), fontSize: size)
            block.center = CGPoint(x: centerX(block.size.width), y: centerY)
            return block
        }
        if piece.firstBit == piece.lastBit { return [number(piece.firstBit) { _ in frame.midX }] }
        return [number(isDescending ? piece.lastBit : piece.firstBit) { width in frame.minX + width / 2 },
                number(isDescending ? piece.firstBit : piece.lastBit) { width in frame.maxX - width / 2 }]
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
