/**
 * File: DiagramFlatTextMeasuringWorkload.swift
 * --------------------------------------------
 * Layer: Core (benchmark interface)
 * Description: Lets the benchmark time the flat text measuring, which no type calls yet, against the label decoder and
 *              the text block it stands in for, on the same texts and in the same font; seen only by an import of the
 *              Benchmark SPI.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics

/// Texts held as the redesign holds them, ranges of one byte buffer, measured in one font at one width: as blocks from
/// Strings (what the layouts do now) or flat from the bytes (`DiagramFlatTextMeasuring`).
@_spi(Benchmark) public struct DiagramFlatTextMeasuringWorkload {
    private let texts: [String]
    private let source: [UInt8]
    private let ranges: [MermaidTextRange]
    private let measurer: CoreTextDiagramTextMeasurer
    private let maximumWidth: CGFloat
    private var lines = DiagramMeasuredLines()

    public init(texts: [String], font: DiagramFont, isBold: Bool = false, maximumWidth: CGFloat) {
        self.texts = texts
        var source: [UInt8] = []
        var ranges: [MermaidTextRange] = []
        for text in texts {
            let start = source.count
            source += Array(text.utf8)
            ranges.append(MermaidTextRange(start: start, end: source.count))
            source.append(UInt8(ascii: "\n"))
        }
        self.source = source
        self.ranges = ranges
        measurer = CoreTextDiagramTextMeasurer(font: font, isBold: isBold)
        self.maximumWidth = maximumWidth
    }

    public var textCount: Int { texts.count }

    /// Every text decoded into a label and measured into a block; the sum of their widths and line counts.
    public func measureAsBlocks() -> Double {
        var total = 0.0
        for text in texts {
            let block = DiagramTextBlock(label: DiagramLabelDecoder.label(from: text, form: .plain), measurer: measurer, maximumWidth: maximumWidth)
            total += Double(block.size.width) + Double(block.lineCount)
        }
        return total
    }

    /// Every text measured flat into one reused list of lines; the same sum.
    public mutating func measureFlat() -> Double {
        let flatMeasurer = DiagramFlatMeasurer(measurer)
        lines.removeAll()
        var total = 0.0
        source.withUnsafeBufferPointer { bytes in
            for range in ranges {
                let measured = DiagramFlatTextMeasuring.measure(bytes, range, form: .plain, measurer: flatMeasurer, maximumWidth: maximumWidth, into: &lines)
                total += Double(measured.width) + Double(measured.lineCount)
            }
        }
        return total
    }

    /// How many texts the fast path takes, and how many measure unlike their blocks in a line, a width or a size.
    public func check() -> (fastPathCount: Int, differenceCount: Int) {
        let flatMeasurer = DiagramFlatMeasurer(measurer)
        var lines = DiagramMeasuredLines()
        var fastPathCount = 0
        var differenceCount = 0
        source.withUnsafeBufferPointer { bytes in
            for (text, range) in zip(texts, ranges) {
                if DiagramFlatTextMeasuring.measuredOnFastPath(bytes, range, form: .plain, measurer: flatMeasurer, maximumWidth: maximumWidth,
                                                               into: &lines) != nil { fastPathCount += 1 }
                let measured = DiagramFlatTextMeasuring.measure(bytes, range, form: .plain, measurer: flatMeasurer, maximumWidth: maximumWidth, into: &lines)
                let block = DiagramTextBlock(label: DiagramLabelDecoder.label(from: text, form: .plain), measurer: measurer, maximumWidth: maximumWidth)
                let isSame = measured.lineCount == block.lineCount && measured.width.bitPattern == block.size.width.bitPattern
                    && measured.height.bitPattern == block.size.height.bitPattern && measured.lineHeight.bitPattern == block.lineHeight.bitPattern
                    && zip(measured.lineIndices, 0..<block.lineCount).allSatisfy { line, index in
                        lines[line].width.bitPattern == block.lineWidth(at: index).bitPattern
                            && lines.text(ofLine: line, source: bytes) == block.line(at: index)
                    }
                if !isSame { differenceCount += 1 }
            }
        }
        return (fastPathCount, differenceCount)
    }
}

/// A closed set of texts measured in one font each time they are drawn: as blocks from Strings, or from the widths kept
/// once per face (`DiagramConstantTexts`).
@_spi(Benchmark) public struct DiagramConstantTextsWorkload {
    private let texts: [String]
    private let constants: DiagramConstantTexts
    private let measurer: CoreTextDiagramTextMeasurer
    private var lines = DiagramMeasuredLines()

    public init(texts: [String], font: DiagramFont) {
        self.texts = texts
        constants = DiagramConstantTexts(texts)
        measurer = CoreTextDiagramTextMeasurer(font: font)
    }

    /// Every text decoded into a label and measured into a block, `repeats` times; the sum of their widths.
    public func measureAsBlocks(repeats: Int) -> Double {
        var total = 0.0
        for _ in 0..<repeats {
            for text in texts {
                total += Double(DiagramTextBlock(label: DiagramLabelDecoder.label(from: text, form: .plain), measurer: measurer, maximumWidth: .infinity).size.width)
            }
        }
        return total
    }

    /// Every text measured from the kept widths, taken once, `repeats` times; the same sum.
    public mutating func measureConstant(repeats: Int) -> Double {
        let flatMeasurer = DiagramFlatMeasurer(measurer)
        let widths = constants.widths(for: measurer)
        lines.removeAll()
        var total = 0.0
        for _ in 0..<repeats {
            for index in 0..<constants.count {
                total += Double(widths.measure(index, measurer: flatMeasurer, maximumWidth: .infinity, into: &lines).width)
            }
        }
        return total
    }
}
