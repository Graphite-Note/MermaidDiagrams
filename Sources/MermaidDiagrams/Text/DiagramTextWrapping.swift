/**
 * File: DiagramTextWrapping.swift
 * -------------------------------
 * Layer: Core
 * Description: A line of spans wrapped at a width as Pele's wrap wraps it: between pieces, each line's trailing spaces
 *              dropped, a soft hyphen shown as a hyphen where a line breaks after it; worked on the line's UTF-8 bytes
 *              in its text storage, each line's runs written as byte ranges, no String made.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 24/11/2026
 */

import CoreGraphics

/// A span of the line being filled: its bytes, its emphasis, its width, and whether every byte is printable ASCII.
struct DiagramWrappedSpan {
    var start: Int
    var end: Int
    let style: DiagramTextStyle
    var width: CGFloat
    var isPrintableASCII: Bool
}

/// Pele's `wrap` (text/label.ts): the spans of a line laid into lines no wider than `maximumWidth` where they can be,
/// breaking only between pieces (`DiagramTextPieces`). A piece that does not fit after what the line holds starts a
/// new line, its leading spaces dropped; a line's trailing spaces are dropped when it is ended; a piece wider than the
/// width stays whole on its own line. Where a line ends after a soft hyphen that a word was broken at, the hyphen shows.
///
/// The line's spans are ranges of `bytes`, which follow one another, and the spans of the line being filled are ranges
/// of them, so that pieces are joined and trimmed by moving ends; each line made is written into the scratch as runs.
/// Where the measurer adds up the advances of printable ASCII (`DiagramFontAdvances`), a span of it that a piece of it
/// joins has its width continued over the piece's bytes, which is the width of the joined text to the bit; other text is
/// measured joined, from its bytes.
struct DiagramTextLineWrapping<Measurer: DiagramTextMeasuring> {
    var measuring: DiagramStyledByteMeasuring<Measurer>
    let maximumWidth: CGFloat
    /// The bytes the spans are ranges of: the text storage's, from its start.
    let bytes: UnsafeBufferPointer<UInt8>
    private var madeLineCount = 0
    private var width: CGFloat = 0

    init(measuring: DiagramStyledByteMeasuring<Measurer>, maximumWidth: CGFloat, bytes: UnsafeBufferPointer<UInt8>) {
        self.measuring = measuring
        self.maximumWidth = maximumWidth
        self.bytes = bytes
    }

    /// A span of the line being wrapped: its emphasis and the advances its measurer adds up, if it does.
    private struct SpanFont {
        let style: DiagramTextStyle
        let advances: DiagramFontAdvances?
    }

    /// Lays the line whose spans are `scratch.lineSpans` into lines of the scratch; every span of a line is wrapped
    /// together, the last one ending the line.
    mutating func wrapLine(into scratch: inout DiagramTextMeasuringScratch) {
        madeLineCount = 0
        width = 0
        scratch.filled.removeAll()
        let spanCount = scratch.lineSpans.count
        for index in 0..<spanCount {
            let span = scratch.lineSpans[index]
            let font = SpanFont(style: span.style, advances: measuring.advances(of: span.style))
            wrap(Int(span.start)..<Int(span.end), font: font, isLastOfLine: index == spanCount - 1, into: &scratch)
        }
        if !scratch.filled.isEmpty || madeLineCount == 0 { commit(into: &scratch) }
    }

    private mutating func wrap(_ span: Range<Int>, font: SpanFont, isLastOfLine: Bool, into scratch: inout DiagramTextMeasuringScratch) {
        let text = bytes[span]
        guard !text.allSatisfy({ byte in byte < 0x80 }) else {
            var start = span.lowerBound
            while start < span.upperBound {
                let end = DiagramTextPieces.endOfASCIIPiece(in: text, from: start)
                place(start..<end, font: font, softHyphenWidths: nil, index: 0, into: &scratch)
                start = end
            }
            return
        }
        var pieces = scratch.pieces
        scratch.pieces = []
        pieces.removeAll(keepingCapacity: true)
        DiagramTextPieces.appendPieces(ofScalarsIn: text, to: &pieces)
        var softHyphenWidths: DiagramSoftHyphenWidths?
        if DiagramWrappedTextBytes.containsSoftHyphen(text) {
            let endsWithHyphen = pieces.map { piece in DiagramWrappedTextBytes.endsWithSoftHyphen(bytes[piece]) }
            // A soft hyphen is not white space: a piece that ends with one has nothing to trim.
            let own = zip(pieces, endsWithHyphen).map { piece, endsWithHyphen in
                width(of: piece.lowerBound..<(endsWithHyphen ? piece.upperBound - 2 : DiagramWrappedTextBytes.endTrimmed(bytes[piece])), font: font)
            }
            softHyphenWidths = DiagramSoftHyphenWidths(own: own, endsWithHyphen: endsWithHyphen, isLastOfLine: isLastOfLine)
        }
        for (index, piece) in pieces.enumerated() {
            place(piece, font: font, softHyphenWidths: softHyphenWidths, index: index, into: &scratch)
        }
        scratch.pieces = pieces
    }

    /// Places piece `index` of its span on the line, or on a new line where it does not fit.
    private mutating func place(_ written: Range<Int>, font: SpanFont, softHyphenWidths: DiagramSoftHyphenWidths?, index: Int,
                                into scratch: inout DiagramTextMeasuringScratch) {
        var piece = written
        let isPrintableASCII = bytes[piece].allSatisfy(DiagramFontAdvances.isPrintable)
        let pieceWidth = softHyphenWidths?.own[index]
            ?? width(of: piece.lowerBound..<DiagramWrappedTextBytes.endTrimmed(bytes[piece]), font: font, isPrintableASCII: isPrintableASCII)
        if width > 0, !fits(piece, index: index, pieceWidth: pieceWidth, style: font.style, softHyphenWidths: softHyphenWidths, scratch: &scratch) {
            // Breaking at a space leaves a soft hyphen before it hidden.
            let start = JavaScriptWhitespace.endOfRun(in: bytes[piece], from: piece.lowerBound)
            commit(showingHyphen: start == piece.lowerBound, into: &scratch)
            piece = start..<piece.upperBound
        }
        append(piece, isPrintableASCII: isPrintableASCII, pieceWidth: pieceWidth, font: font, into: &scratch)
    }

    private mutating func fits(_ piece: Range<Int>, index: Int, pieceWidth: CGFloat, style: DiagramTextStyle,
                               softHyphenWidths: DiagramSoftHyphenWidths?, scratch: inout DiagramTextMeasuringScratch) -> Bool {
        guard let softHyphenWidths, DiagramWrappedTextBytes.endsWithSoftHyphen(bytes[piece]) else { return width + pieceWidth <= maximumWidth }
        scratch.probe.removeAll()
        scratch.probe.append(contentsOf: UnsafeBufferPointer(rebasing: bytes[piece].dropLast(2)))
        scratch.probe.append(UInt8(ascii: "-"))
        return width + measuring.width(of: scratch.probe.buffer, style: style) <= maximumWidth
            || width + softHyphenWidths.rest[index] <= maximumWidth
    }

    private mutating func append(_ piece: Range<Int>, isPrintableASCII: Bool, pieceWidth: CGFloat, font: SpanFont,
                                 into scratch: inout DiagramTextMeasuringScratch) {
        if let last = scratch.filled.last, last.style == font.style {
            var joined = last
            // The pieces of a line follow one another in its bytes, so the span takes the piece by moving its end.
            joined.end = piece.upperBound
            // Measured again only when the piece adds width, so that zero-width pieces take no time.
            if pieceWidth > 0 || JavaScriptWhitespace.lengthOfLast(in: bytes[piece]) > 0 {
                let before = joined.width
                if joined.isPrintableASCII, isPrintableASCII, let advances = font.advances {
                    joined.width = advances.width(continuing: joined.width, over: bytes[piece])
                } else {
                    joined.width = width(of: joined.start..<joined.end, font: font, isPrintableASCII: joined.isPrintableASCII && isPrintableASCII)
                }
                width += joined.width - before
            }
            joined.isPrintableASCII = joined.isPrintableASCII && isPrintableASCII
            scratch.filled[scratch.filled.count - 1] = joined
            return
        }
        let pieceFullWidth = width(of: piece, font: font, isPrintableASCII: isPrintableASCII)
        scratch.filled.append(DiagramWrappedSpan(start: piece.lowerBound, end: piece.upperBound, style: font.style, width: pieceFullWidth,
                                                 isPrintableASCII: isPrintableASCII))
        width += pieceFullWidth
    }

    /// Ends the line: its last span's trailing spaces dropped and, when `showingHyphen`, a soft hyphen it ends with
    /// shown as `-`; each span written as a run.
    private mutating func commit(showingHyphen: Bool = false, into scratch: inout DiagramTextMeasuringScratch) {
        defer {
            madeLineCount += 1
            scratch.filled.removeAll()
            width = 0
        }
        guard let last = scratch.filled.last else { return scratch.addEmptyLine(width: width) }
        let lastRun = committed(last, showingHyphen: showingHyphen, into: &scratch)
        width += lastRun.width - last.width
        let firstRun = Int32(scratch.runs.count)
        for index in 0..<(scratch.filled.count - 1) {
            let span = scratch.filled[index]
            scratch.runs.append(DiagramTextRunRecord(start: Int32(span.start), end: Int32(span.end), width: span.width, style: span.style))
            if !span.style.isEmpty { scratch.hasEmphasis = true }
        }
        scratch.runs.append(lastRun)
        if !lastRun.style.isEmpty { scratch.hasEmphasis = true }
        scratch.lines.append(DiagramTextMeasuringScratch.Line(firstRun: firstRun, runCount: Int32(scratch.filled.count), width: width))
    }

    /// The line's last span as it ends the line: its trailing spaces dropped, or a soft hyphen it ends with shown as `-`
    /// (written as synthetic text), and measured again when that changed it.
    private mutating func committed(_ last: DiagramWrappedSpan, showingHyphen: Bool, into scratch: inout DiagramTextMeasuringScratch)
        -> DiagramTextRunRecord {
        let written = bytes[last.start..<last.end]
        if showingHyphen, DiagramWrappedTextBytes.endsWithSoftHyphen(written) {
            // A soft hyphen is not white space, so nothing was trimmed before it.
            let shown = scratch.appendSynthetic(UnsafeBufferPointer(rebasing: written.dropLast(2)), suffix: UInt8(ascii: "-"))
            let shownWidth = measuring.width(of: scratch.bytes(shown.start, shown.end, source: bytes.baseAddress!), style: last.style)
            return DiagramTextRunRecord(start: shown.start, end: shown.end, width: shownWidth, style: last.style)
        }
        let trimmedEnd = DiagramWrappedTextBytes.endTrimmed(written)
        var run = DiagramTextRunRecord(start: Int32(last.start), end: Int32(trimmedEnd), width: last.width, style: last.style)
        if trimmedEnd != last.end {
            let advances = last.isPrintableASCII ? measuring.advances(of: last.style) : nil
            run.width = width(of: last.start..<trimmedEnd, font: SpanFont(style: last.style, advances: advances), isPrintableASCII: last.isPrintableASCII)
        }
        return run
    }

    /// The width of `range` of the bytes in the span's font: added up from its advances where every byte is printable
    /// ASCII and the measurer adds them up, else measured as text. Either way it is the measurer's width of that text.
    private mutating func width(of range: Range<Int>, font: SpanFont, isPrintableASCII: Bool? = nil) -> CGFloat {
        if let advances = font.advances, isPrintableASCII ?? bytes[range].allSatisfy(DiagramFontAdvances.isPrintable) {
            return advances.width(continuing: 0, over: bytes[range])
        }
        return measuring.width(of: UnsafeBufferPointer(rebasing: bytes[range]), style: font.style)
    }
}

/// A line's UTF-8 bytes as wrapping reads them: trailing white space and soft hyphens.
enum DiagramWrappedTextBytes {
    /// The end of `text` without its trailing JavaScript white space, a character beyond ASCII taken whole.
    static func endTrimmed(_ text: Slice<UnsafeBufferPointer<UInt8>>) -> Int {
        var end = text.endIndex
        while case let length = JavaScriptWhitespace.lengthOfLast(in: text[text.startIndex..<end]), length > 0 { end -= length }
        return end
    }

    /// The UTF-8 of the soft hyphen, U+00AD.
    static let softHyphenBytes: (UInt8, UInt8) = (0xC2, 0xAD)

    static func containsSoftHyphen(_ text: Slice<UnsafeBufferPointer<UInt8>>) -> Bool {
        var position = text.startIndex
        while position + 1 < text.endIndex {
            if text[position] == softHyphenBytes.0, text[position + 1] == softHyphenBytes.1 { return true }
            position += 1
        }
        return false
    }

    static func endsWithSoftHyphen(_ text: Slice<UnsafeBufferPointer<UInt8>>) -> Bool {
        text.count >= 2 && text[text.endIndex - 2] == softHyphenBytes.0 && text[text.endIndex - 1] == softHyphenBytes.1
    }
}

/// The widths Pele works out for the pieces of a span with a soft hyphen: each piece without its trailing spaces and
/// its final soft hyphen (`own`), and the width of the rest of its word from each piece on (`rest`), unknown past the
/// span unless the span ends the line.
struct DiagramSoftHyphenWidths {
    let own: [CGFloat]
    let rest: [CGFloat]

    init(own: [CGFloat], endsWithHyphen: [Bool], isLastOfLine: Bool) {
        var rest = [CGFloat](repeating: 0, count: own.count + 1)
        for index in own.indices.reversed() {
            if !endsWithHyphen[index] {
                rest[index] = own[index]
            } else if index == own.count - 1 {
                rest[index] = isLastOfLine ? own[index] : .infinity
            } else {
                rest[index] = own[index] + rest[index + 1]
            }
        }
        self.own = own
        self.rest = rest
    }
}
