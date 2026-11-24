/**
 * File: DiagramFlatTextMeasuring.swift
 * ------------------------------------
 * Layer: Core (prototype of the slow-types redesign, not for merging as is)
 * Description: Measures a label of printable ASCII without markup straight from its bytes, as DiagramLabelDecoder,
 *              DiagramTextBlock and DiagramTextWrapping measure it, its lines kept as byte ranges in a reused list
 *              instead of strings and arrays of their own; any other label is left to the full path.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics

/// The lines of measured labels, in one list reused from label to label: each line a range of its label's bytes and
/// its width.
struct DiagramFlatTextLines {
    var starts: [Int32] = []
    var ends: [Int32] = []
    var widths: [CGFloat] = []

    var count: Int { starts.count }

    mutating func removeAll() {
        starts.removeAll(keepingCapacity: true)
        ends.removeAll(keepingCapacity: true)
        widths.removeAll(keepingCapacity: true)
    }

    mutating func append(start: Int, end: Int, width: CGFloat) {
        starts.append(Int32(truncatingIfNeeded: start))
        ends.append(Int32(truncatingIfNeeded: end))
        widths.append(width)
    }
}

/// A label measured into `DiagramFlatTextLines`: its first line there, how many lines, its size and line height.
struct DiagramFlatTextSize: Equatable {
    var firstLine: Int32
    var lineCount: Int32
    var width: CGFloat
    var height: CGFloat
    var lineHeight: CGFloat
}

/// The fast path of a label's measuring: printable ASCII that DiagramLabelLineBreaks finds unmarked, which Pele reads
/// as one line, trimmed, wrapped at its spaces past the width.
enum DiagramFlatTextMeasuring {
    static let severalLinesHeightRatio: CGFloat = 1.3

    /// The label measured, its lines appended to `lines`; nil when the label is not on the fast path (markup other than
    /// line breaks, a byte past ASCII, a control character inside a line), which the full path then measures.
    static func measure(_ bytes: UnsafeBufferPointer<UInt8>, advances: UnsafeBufferPointer<CGFloat>, fontSize: CGFloat, singleLineHeight: CGFloat,
                        maximumWidth: CGFloat, isLiteral: Bool, into lines: inout DiagramFlatTextLines) -> DiagramFlatTextSize? {
        let firstLine = lines.count
        var lineStart = 0
        var index = 0
        var hasBreak = false
        while index < bytes.count {
            let byte = bytes[index]
            if byte >= 0x80 { return nil }
            let breakLength = byte == 10 || byte == 92 || byte == 60 ? Self.breakLength(in: bytes, at: index) : 0
            if breakLength > 0 {
                hasBreak = true
                guard measureLine(bytes, lineStart, index, advances: advances, maximumWidth: maximumWidth, isLiteral: isLiteral, into: &lines) else {
                    return nil
                }
                index += breakLength
                lineStart = index
            } else {
                index += 1
            }
        }
        guard measureLine(bytes, lineStart, bytes.count, advances: advances, maximumWidth: maximumWidth, isLiteral: isLiteral, into: &lines) else {
            return nil
        }
        _ = hasBreak
        let lineCount = lines.count - firstLine
        var widest: CGFloat = 0
        for line in firstLine..<lines.count where lines.widths[line] > widest { widest = lines.widths[line] }
        let lineHeight = lineCount > 1 ? (fontSize * severalLinesHeightRatio).rounded() : singleLineHeight
        return DiagramFlatTextSize(firstLine: Int32(firstLine), lineCount: Int32(lineCount), width: widest, height: CGFloat(lineCount) * lineHeight,
                                   lineHeight: lineHeight)
    }

    /// The length of Pele's `RE_BREAK` at `index` (`<br\s*\/?>` in any case, a written `\n` or `\N`, a line feed), or
    /// zero for none.
    @inline(__always)
    private static func breakLength(in bytes: UnsafeBufferPointer<UInt8>, at index: Int) -> Int {
        switch bytes[index] {
        case 10: return 1
        case 92: return index + 1 < bytes.count && (bytes[index + 1] == 110 || bytes[index + 1] == 78) ? 2 : 0
        default:
            guard index + 3 < bytes.count, bytes[index + 1] | 0x20 == 98, bytes[index + 2] | 0x20 == 114 else { return 0 }
            var end = index + 3
            while end < bytes.count, isWhitespace(bytes[end]) { end += 1 }
            if end < bytes.count, bytes[end] == 47 { end += 1 }
            guard end < bytes.count, bytes[end] == 62 else { return 0 }
            return end + 1 - index
        }
    }

    /// One line between breaks, trimmed, measured and wrapped; false when it holds markup or a control character.
    private static func measureLine(_ bytes: UnsafeBufferPointer<UInt8>, _ writtenStart: Int, _ writtenEnd: Int, advances: UnsafeBufferPointer<CGFloat>,
                                    maximumWidth: CGFloat, isLiteral: Bool, into lines: inout DiagramFlatTextLines) -> Bool {
        var start = writtenStart
        var end = writtenEnd
        while start < end, isWhitespace(bytes[start]) { start += 1 }
        while end > start, isWhitespace(bytes[end - 1]) { end -= 1 }
        var hasSpace = false
        var hasMarkupByte = false
        var width: CGFloat = 0
        let base = bytes.baseAddress!
        let table = advances.baseAddress!
        for index in start..<end {
            let byte = base[index]
            guard byte >= 32, byte <= 126 else { return false }
            if byte == 32 { hasSpace = true }
            // `#`, `&`, `*`, `:`, `\\`, `_` and `<`: only then is the line read for its markup.
            if byte < 64 ? (lowMarkupBytes &>> UInt64(byte)) & 1 != 0 : (byte == 92 || byte == 95) { hasMarkupByte = true }
            width += table[Int(byte) &- 32]
        }
        if hasMarkupByte, !DiagramLabelLineBreaks.isUnmarked(bytes[start..<end], isLiteral: isLiteral) { return false }
        if !(width > maximumWidth) || !hasSpace {
            lines.append(start: start, end: end, width: width)
            return true
        }
        var wrapping = Wrapping(bytes: bytes, advances: advances, maximumWidth: maximumWidth)
        wrapping.wrap(start..<end, into: &lines)
        return true
    }

    private static let lowMarkupBytes: UInt64 = [UInt8(ascii: "#"), UInt8(ascii: "&"), UInt8(ascii: "*"), UInt8(ascii: ":"), UInt8(ascii: "<")]
        .reduce(0) { mask, byte in mask | 1 &<< UInt64(byte) }

    @inline(__always)
    static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 32 || (byte >= 9 && byte <= 13)
    }

    /// DiagramTextWrapping's steps for one span of printable ASCII, the additions in its order so that every width is
    /// the same to the last bit.
    private struct Wrapping {
        let bytes: UnsafeBufferPointer<UInt8>
        let advances: UnsafeBufferPointer<CGFloat>
        let maximumWidth: CGFloat
        var currentStart = -1
        var currentEnd = -1
        var currentWidth: CGFloat = 0
        var lineWidth: CGFloat = 0
        var madeLineCount = 0

        init(bytes: UnsafeBufferPointer<UInt8>, advances: UnsafeBufferPointer<CGFloat>, maximumWidth: CGFloat) {
            self.bytes = bytes
            self.advances = advances
            self.maximumWidth = maximumWidth
        }

        mutating func wrap(_ range: Range<Int>, into lines: inout DiagramFlatTextLines) {
            var start = range.lowerBound
            while start < range.upperBound {
                var end = start
                while end < range.upperBound, isWhitespace(bytes[end]) { end += 1 }
                while end < range.upperBound, !isWhitespace(bytes[end]) { end += 1 }
                while end < range.upperBound, isWhitespace(bytes[end]) { end += 1 }
                place(start, end, into: &lines)
                start = end
            }
            if currentStart >= 0 || madeLineCount == 0 { commit(into: &lines) }
        }

        private func width(continuing width: CGFloat, _ start: Int, _ end: Int) -> CGFloat {
            var total = width
            var index = start
            while index < end {
                total += advances[Int(bytes[index]) - 32]
                index += 1
            }
            return total
        }

        private func trimmedEnd(_ start: Int, _ end: Int) -> Int {
            var trimmed = end
            while trimmed > start, isWhitespace(bytes[trimmed - 1]) { trimmed -= 1 }
            return trimmed
        }

        private mutating func place(_ writtenStart: Int, _ end: Int, into lines: inout DiagramFlatTextLines) {
            var start = writtenStart
            let pieceWidth = width(continuing: 0, start, trimmedEnd(start, end))
            if lineWidth > 0, !(lineWidth + pieceWidth <= maximumWidth) {
                var runEnd = start
                while runEnd < end, isWhitespace(bytes[runEnd]) { runEnd += 1 }
                commit(into: &lines)
                start = runEnd
            }
            append(start, end, pieceWidth: pieceWidth)
        }

        private mutating func append(_ start: Int, _ end: Int, pieceWidth: CGFloat) {
            if currentStart >= 0 {
                currentEnd = end
                if pieceWidth > 0 || (end > start && isWhitespace(bytes[end - 1])) {
                    let before = currentWidth
                    currentWidth = width(continuing: currentWidth, start, end)
                    lineWidth += currentWidth - before
                }
                return
            }
            let full = width(continuing: 0, start, end)
            currentStart = start
            currentEnd = end
            currentWidth = full
            lineWidth += full
        }

        private mutating func commit(into lines: inout DiagramFlatTextLines) {
            defer {
                madeLineCount += 1
                currentStart = -1
                currentEnd = -1
                currentWidth = 0
                lineWidth = 0
            }
            guard currentStart >= 0 else { return lines.append(start: 0, end: 0, width: lineWidth) }
            let trimmed = trimmedEnd(currentStart, currentEnd)
            var lastWidth = currentWidth
            if trimmed != currentEnd { lastWidth = width(continuing: 0, currentStart, trimmed) }
            lineWidth += lastWidth - currentWidth
            lines.append(start: currentStart, end: trimmed, width: lineWidth)
        }
    }
}
