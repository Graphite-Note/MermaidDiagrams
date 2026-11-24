/**
 * File: FlatTextRecords.swift
 * ---------------------------
 * Layer: Prototype
 * Description: A label and its measured lines as small records of byte ranges into one buffer, and the advance
 *              tables of a measurer's eight emphases, made once and never freed.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics

/// A line of a decoded label: its bytes, and its spans when the label has emphasis.
struct FlatLabelLine {
    var start: Int32
    var end: Int32
    var firstSpan: Int32
    var spanCount: Int32
}

/// A span of a decoded line: its bytes and its emphasis.
struct FlatLabelSpan {
    var start: Int32
    var end: Int32
    var style: DiagramTextStyle
}

/// A decoded label: its lines, whether they carry spans, how Pele reads it, and whether every byte is printable ASCII.
struct FlatLabel {
    var firstLine: Int32
    var lineCount: Int32
    var hasSpans: Bool
    var isReadWithoutMarkup: Bool
    var isPrintableASCII: Bool
}

/// A measured run: its bytes, its width and its emphasis.
struct FlatMeasuredRun {
    var start: Int32
    var end: Int32
    var width: CGFloat
    var style: DiagramTextStyle
}

/// A measured line: its runs and its width.
struct FlatMeasuredLine {
    var firstRun: Int32
    var runCount: Int32
    var width: CGFloat
}

/// A measured block: its lines, its size, line height and whether a run has emphasis.
struct FlatTextBlock {
    var firstLine: Int32
    var lineCount: Int32
    var fontSize: CGFloat
    var lineHeight: CGFloat
    var hasEmphasis: Bool
}

/// The advances of a measurer's font in each of the eight emphases, indexed by byte (256 entries each, zero outside
/// printable ASCII), in one buffer made once and never freed: copying the value retains nothing.
struct FlatFontStyles {
    let advances: UnsafePointer<CGFloat>
    let fontSize: CGFloat
    let lineHeight: CGFloat
    /// The present measurers of the eight emphases, for text beyond printable ASCII not yet measured.
    let measurers: UnsafePointer<CoreTextDiagramTextMeasurer>
    /// The first of the eight faces' identifiers.
    let firstFace: Int32
    nonisolated(unsafe) private static var madeFaceCount: Int32 = 0
    /// Whether every advance is a binary fraction of at most 20 bits below 1,024 points, so that any sum of fewer than
    /// 2^23 of them is exact: added in any order, a width is then the one the present measurer adds up, to the bit.
    let isExactlySummable: Bool

    init(measurer: CoreTextDiagramTextMeasurer) {
        let measurers = UnsafeMutablePointer<CoreTextDiagramTextMeasurer>.allocate(capacity: 8)
        for raw in UInt8(0)..<8 {
            let style = DiagramTextStyle(rawValue: raw)
            (measurers + Int(raw)).initialize(to: style.isEmpty ? measurer : measurer.adding(style))
        }
        self.measurers = UnsafePointer(measurers)
        firstFace = Self.madeFaceCount
        Self.madeFaceCount += 8
        let buffer = UnsafeMutablePointer<CGFloat>.allocate(capacity: 8 * 256)
        buffer.initialize(repeating: 0, count: 8 * 256)
        for raw in UInt8(0)..<8 {
            let style = DiagramTextStyle(rawValue: raw)
            let variant = style.isEmpty ? measurer : measurer.adding(style)
            let table = variant.printableASCIIAdvances.advances
            for index in table.indices { buffer[Int(raw) * 256 + 32 + index] = table[index] }
        }
        advances = UnsafePointer(buffer)
        var isExact = true
        for index in 0..<(8 * 256) {
            let scaled = buffer[index] * 1_048_576
            if scaled.rounded() != scaled || buffer[index] >= 1_024 || buffer[index] < 0 { isExact = false }
        }
        isExactlySummable = isExact
        fontSize = measurer.fontSize
        lineHeight = measurer.lineHeight
    }

    /// The width of `bytes[start..<end]` in `style`: its advances added up from the first byte where every byte is
    /// printable ASCII, as the present measurer adds them, else its Core Text line's width.
    @inline(__always)
    func width(_ bytes: UnsafeBufferPointer<UInt8>, _ start: Int, _ end: Int, _ style: DiagramTextStyle) -> CGFloat {
        let table = self.table(style)
        var width: CGFloat = 0
        var index = start
        while index < end {
            let byte = bytes[index]
            guard byte >= 32, byte <= 126 else {
                return FlatLineWidthCache.shared.width(bytes, start, end, face: firstFace + Int32(style.rawValue), measurer: measurers + Int(style.rawValue))
            }
            width += table[Int(byte)]
            index += 1
        }
        return width
    }

    @inline(__always)
    func table(_ style: DiagramTextStyle) -> UnsafePointer<CGFloat> {
        advances + Int(style.rawValue) * 256
    }
}
