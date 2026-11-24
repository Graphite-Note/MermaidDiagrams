/**
 * File: DiagramTextExactWrapping.swift
 * ------------------------------------
 * Layer: Core
 * Description: Wraps a line of printable ASCII in faces whose advances sum exactly reading each byte once: a piece's
 *              width from its spaces and its word, a trimmed span's from taking its trailing spaces off; the same lines
 *              and widths, to the bit, as the wrapping that measures joined text again.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics

extension DiagramTextMeasuringScratch {
    /// The most bytes a line wrapped exactly may have: fewer than 2^22 advances below 1,024 points of at most 20 fraction
    /// bits sum exactly in a Double.
    static let longestExactlyWrappedByteCount = 1 << 21

    /// Whether the spans of `lineSpans` are wrapped exactly: every byte printable ASCII and every span's face exactly
    /// summable (`DiagramFontAdvances.isExactlySummable`), so that every width the wrapping adds, continues or takes
    /// apart is the exact sum of its bytes' advances, whatever the order.
    mutating func wrapsExactly<Measurer>(_ bytes: UnsafePointer<UInt8>, measuring: inout DiagramStyledByteMeasuring<Measurer>) -> Bool {
        var byteCount = 0
        for index in 0..<lineSpans.count {
            let span = lineSpans[index]
            guard let advances = measuring.advances(of: span.style), advances.isExactlySummable else { return false }
            for position in Int(span.start)..<Int(span.end) where !DiagramFontAdvances.isPrintable(bytes[position]) { return false }
            byteCount += Int(span.end - span.start)
        }
        return byteCount < Self.longestExactlyWrappedByteCount
    }

    /// `DiagramTextLineWrapping.wrapLine` for spans that `wrapsExactly`. Each piece (the spaces before a word, the word
    /// and the spaces after it) is read once into the advances of its parts: its width without its trailing spaces is
    /// its spaces and its word (none for a piece of spaces alone), its width placed after a break leaves its leading
    /// spaces out, and a span joined by a piece takes the piece's width; the line's last span loses its trailing spaces'.
    mutating func wrapExactly<Measurer>(_ bytes: UnsafePointer<UInt8>, measuring: inout DiagramStyledByteMeasuring<Measurer>, maximumWidth: CGFloat) {
        var width: CGFloat = 0
        var madeLineCount = 0
        filled.removeAll()
        for spanIndex in 0..<lineSpans.count {
            let span = lineSpans[spanIndex]
            let table = measuring.advances(of: span.style)!.byByte
            var start = Int(span.start)
            let end = Int(span.end)
            while start < end {
                let piece = ExactPiece(bytes, from: start, to: end, advances: table)
                var pieceStart = start
                var placedWidth = piece.leading + piece.word + piece.trailing
                if width > 0, !(width + (piece.hasWord ? piece.leading + piece.word : 0) <= maximumWidth) {
                    commitExactly(bytes, measuring: &measuring, width: &width)
                    madeLineCount += 1
                    pieceStart = piece.afterLeading
                    placedWidth = piece.word + piece.trailing
                }
                if let last = filled.last, last.style == span.style {
                    filled[filled.count - 1].end = piece.end
                    filled[filled.count - 1].width = last.width + placedWidth
                } else {
                    filled.append(DiagramWrappedSpan(start: pieceStart, end: piece.end, style: span.style, width: placedWidth, isPrintableASCII: true))
                }
                width += placedWidth
                start = piece.end
            }
        }
        if !filled.isEmpty || madeLineCount == 0 { commitExactly(bytes, measuring: &measuring, width: &width) }
    }

    /// A piece of printable ASCII read once: the spaces before its word, its word and the spaces after it, each part's
    /// advances added up, and where its word starts and it ends.
    private struct ExactPiece {
        var leading: CGFloat = 0
        var word: CGFloat = 0
        var trailing: CGFloat = 0
        let afterLeading: Int
        let end: Int
        let hasWord: Bool

        init(_ bytes: UnsafePointer<UInt8>, from start: Int, to spanEnd: Int, advances table: UnsafePointer<CGFloat>) {
            var position = start
            while position < spanEnd, bytes[position] == UInt8(ascii: " ") {
                leading += table[Int(bytes[position])]
                position += 1
            }
            afterLeading = position
            while position < spanEnd, bytes[position] != UInt8(ascii: " ") {
                word += table[Int(bytes[position])]
                position += 1
            }
            hasWord = position > afterLeading
            while position < spanEnd, bytes[position] == UInt8(ascii: " ") {
                trailing += table[Int(bytes[position])]
                position += 1
            }
            end = position
        }
    }

    /// Ends the line being filled: its last span's trailing spaces and their advances taken off; each span written as a run.
    private mutating func commitExactly<Measurer>(_ bytes: UnsafePointer<UInt8>, measuring: inout DiagramStyledByteMeasuring<Measurer>, width: inout CGFloat) {
        defer {
            filled.removeAll()
            width = 0
        }
        guard let last = filled.last else { return addEmptyLine(width: width) }
        let table = measuring.advances(of: last.style)!.byByte
        var trimmedEnd = last.end
        var trailing: CGFloat = 0
        while trimmedEnd > last.start, bytes[trimmedEnd - 1] == UInt8(ascii: " ") {
            trimmedEnd -= 1
            trailing += table[Int(bytes[trimmedEnd])]
        }
        width -= trailing
        let firstRun = Int32(runs.count)
        for index in 0..<filled.count {
            let span = filled[index]
            let isLast = index == filled.count - 1
            runs.append(DiagramTextRunRecord(start: Int32(span.start), end: Int32(isLast ? trimmedEnd : span.end), width: isLast ? span.width - trailing : span.width,
                                             style: span.style))
            if !span.style.isEmpty { hasEmphasis = true }
        }
        lines.append(Line(firstRun: firstRun, runCount: Int32(filled.count), width: width))
    }
}
