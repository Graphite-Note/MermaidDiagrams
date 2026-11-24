/**
 * File: DiagramTextWrapping.swift
 * -------------------------------
 * Layer: Core
 * Description: A line of spans wrapped at a width as Pele's wrap wraps it: between pieces, each line's trailing spaces
 *              dropped, a soft hyphen shown as a hyphen where a line breaks after it; worked on the line's UTF-8 bytes,
 *              each line's text made once.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import CoreGraphics

/// A piece of a line being measured: its text, its emphasis and its width in it.
struct DiagramMeasuredSpan {
    var text: String
    let style: DiagramTextStyle
    var width: CGFloat

    var run: DiagramTextRun { DiagramTextRun(text: text, style: style, width: width) }
}

/// Pele's `wrap` (text/label.ts): the spans of a line laid into lines no wider than `maximumWidth` where they can be,
/// breaking only between pieces (`DiagramTextPieces`). A piece that does not fit after what the line holds starts a
/// new line, its leading spaces dropped; a line's trailing spaces are dropped when it is ended; a piece wider than the
/// width stays whole on its own line. Where a line ends after a soft hyphen that a word was broken at, the hyphen shows.
///
/// The line's spans are read as one run of UTF-8 bytes, and the spans of the line being filled are ranges of it, so that
/// pieces are joined and trimmed by moving ends; a line's texts are made when it is ended. Where the measurer adds up
/// the advances of printable ASCII (`DiagramPrintableASCIIAdvances`), a span of it that a piece of it joins has its width
/// continued over the piece's bytes, which is the width of the joined text to the bit; other text is measured joined.
struct DiagramTextWrapping<Measurer: DiagramTextMeasuring> {
    private var measuring: DiagramStyledMeasuring<Measurer>
    private let maximumWidth: CGFloat
    /// The lines made so far, after the lines handed in.
    private var lines: DiagramMeasuredLines
    private var madeLineCount = 0
    private var current: [WrappedSpan] = []
    private var width: CGFloat = 0

    /// A span of the line being filled: its bytes, its emphasis, its width, and whether every byte is printable ASCII.
    private struct WrappedSpan {
        var start: Int
        var end: Int
        let style: DiagramTextStyle
        var width: CGFloat
        var isPrintableASCII: Bool
    }

    /// A span of the line being wrapped: its emphasis and the advances its measurer adds up, if it does.
    private struct SpanFont {
        let style: DiagramTextStyle
        let advances: DiagramPrintableASCIIAdvances?
    }

    /// Wraps into `lines`, after the lines they hold.
    init(measuring: DiagramStyledMeasuring<Measurer>, lines: DiagramMeasuredLines, maximumWidth: CGFloat) {
        self.measuring = measuring
        self.lines = lines
        self.maximumWidth = maximumWidth
    }

    /// The measurer, with the fonts it made for emphasis, to measure the next line with.
    var finishedMeasuring: DiagramStyledMeasuring<Measurer> { measuring }

    /// The lines handed in, then the lines made.
    var finishedLines: DiagramMeasuredLines { lines }

    /// Lays `line` into lines; every span of a line is wrapped together, the last one ending the line.
    mutating func wrap(_ line: [DiagramMeasuredSpan]) {
        var text = line.count == 1 ? line[0].text : line.map(\.text).joined()
        let totalWidth = line.reduce(0) { total, span in total + span.width }
        if maximumWidth > 0, totalWidth.isFinite, case let estimate = (totalWidth / maximumWidth).rounded(.up) + 1, estimate < CGFloat(text.utf8.count) {
            lines.reserveCapacity(Int(estimate))
        }
        text.withUTF8 { bytes in
            var start = 0
            for (index, span) in line.enumerated() {
                let end = start + span.text.utf8.count
                let font = SpanFont(style: span.style, advances: measuring.printableASCIIAdvances(of: span.style))
                wrap(bytes, span: start..<end, font: font, isLastOfLine: index == line.count - 1)
                start = end
            }
            if !current.isEmpty || madeLineCount == 0 { commit(bytes) }
        }
    }

    private mutating func wrap(_ bytes: UnsafeBufferPointer<UInt8>, span: Range<Int>, font: SpanFont, isLastOfLine: Bool) {
        let text = bytes[span]
        guard !text.allSatisfy({ byte in byte < 0x80 }) else {
            var start = span.lowerBound
            while start < span.upperBound {
                let end = DiagramTextPieces.endOfASCIIPiece(in: text, from: start)
                place(start..<end, of: bytes, font: font, softHyphenWidths: nil, index: 0)
                start = end
            }
            return
        }
        var pieces: [Range<Int>] = []
        DiagramTextPieces.appendPieces(ofScalarsIn: text, to: &pieces)
        var softHyphenWidths: SoftHyphenWidths?
        if WrappedTextBytes.containsSoftHyphen(text) {
            let endsWithHyphen = pieces.map { piece in WrappedTextBytes.endsWithSoftHyphen(bytes[piece]) }
            // A soft hyphen is not white space: a piece that ends with one has nothing to trim.
            let own = zip(pieces, endsWithHyphen).map { piece, endsWithHyphen in
                width(of: piece.lowerBound..<(endsWithHyphen ? piece.upperBound - 2 : WrappedTextBytes.endTrimmed(bytes[piece])), in: bytes, font: font)
            }
            softHyphenWidths = SoftHyphenWidths(own: own, endsWithHyphen: endsWithHyphen, isLastOfLine: isLastOfLine)
        }
        for (index, piece) in pieces.enumerated() {
            place(piece, of: bytes, font: font, softHyphenWidths: softHyphenWidths, index: index)
        }
    }

    /// Places piece `index` of its span on the line, or on a new line where it does not fit.
    private mutating func place(_ written: Range<Int>, of bytes: UnsafeBufferPointer<UInt8>, font: SpanFont, softHyphenWidths: SoftHyphenWidths?,
                                index: Int) {
        var piece = written
        let isPrintableASCII = bytes[piece].allSatisfy(DiagramPrintableASCIIAdvances.isPrintable)
        let pieceWidth = softHyphenWidths?.own[index]
            ?? width(of: piece.lowerBound..<WrappedTextBytes.endTrimmed(bytes[piece]), in: bytes, font: font, isPrintableASCII: isPrintableASCII)
        if width > 0, !fits(piece, of: bytes, index: index, pieceWidth: pieceWidth, style: font.style, softHyphenWidths: softHyphenWidths) {
            // Breaking at a space leaves a soft hyphen before it hidden.
            let start = JavaScriptWhitespace.endOfRun(in: bytes[piece], from: piece.lowerBound)
            commit(bytes, showingHyphen: start == piece.lowerBound)
            piece = start..<piece.upperBound
        }
        append(piece, of: bytes, isPrintableASCII: isPrintableASCII, pieceWidth: pieceWidth, font: font)
    }

    private mutating func fits(_ piece: Range<Int>, of bytes: UnsafeBufferPointer<UInt8>, index: Int, pieceWidth: CGFloat, style: DiagramTextStyle,
                               softHyphenWidths: SoftHyphenWidths?) -> Bool {
        guard let softHyphenWidths, WrappedTextBytes.endsWithSoftHyphen(bytes[piece]) else { return width + pieceWidth <= maximumWidth }
        return width + measuring.width(of: WrappedTextBytes.hyphenShown(bytes[piece]), style: style) <= maximumWidth
            || width + softHyphenWidths.rest[index] <= maximumWidth
    }

    private mutating func append(_ piece: Range<Int>, of bytes: UnsafeBufferPointer<UInt8>, isPrintableASCII: Bool, pieceWidth: CGFloat, font: SpanFont) {
        if let lastIndex = current.indices.last, current[lastIndex].style == font.style {
            var last = current[lastIndex]
            // The pieces of a line follow one another in its bytes, so the span takes the piece by moving its end.
            last.end = piece.upperBound
            // Measured again only when the piece adds width, so that zero-width pieces take no time.
            if pieceWidth > 0 || JavaScriptWhitespace.lengthOfLast(in: bytes[piece]) > 0 {
                let before = last.width
                if last.isPrintableASCII, isPrintableASCII, let advances = font.advances {
                    last.width = advances.width(continuing: last.width, over: bytes[piece])
                } else {
                    last.width = width(of: last.start..<last.end, in: bytes, font: font, isPrintableASCII: last.isPrintableASCII && isPrintableASCII)
                }
                width += last.width - before
            }
            last.isPrintableASCII = last.isPrintableASCII && isPrintableASCII
            current[lastIndex] = last
            return
        }
        let pieceFullWidth = width(of: piece, in: bytes, font: font, isPrintableASCII: isPrintableASCII)
        current.append(WrappedSpan(start: piece.lowerBound, end: piece.upperBound, style: font.style, width: pieceFullWidth, isPrintableASCII: isPrintableASCII))
        width += pieceFullWidth
    }

    /// Ends the line: its last span's trailing spaces dropped and, when `showingHyphen`, a soft hyphen it ends with
    /// shown as `-`; each span's text made from its bytes.
    private mutating func commit(_ bytes: UnsafeBufferPointer<UInt8>, showingHyphen: Bool = false) {
        defer {
            madeLineCount += 1
            current.removeAll(keepingCapacity: true)
            width = 0
        }
        guard let last = current.last else { return lines.add([], width: width) }
        let lastSpan = committed(last, of: bytes, showingHyphen: showingHyphen)
        width += lastSpan.width - last.width
        guard current.count > 1 else { return lines.add(lastSpan, width: width) }
        var spans: [DiagramMeasuredSpan] = []
        spans.reserveCapacity(current.count)
        for span in current.dropLast() {
            spans.append(DiagramMeasuredSpan(text: Self.text(bytes, span.start..<span.end), style: span.style, width: span.width))
        }
        spans.append(lastSpan)
        lines.add(spans, width: width)
    }

    /// The line's last span as it ends the line: its trailing spaces dropped, or a soft hyphen it ends with shown as `-`,
    /// and measured again when that changed it.
    private mutating func committed(_ last: WrappedSpan, of bytes: UnsafeBufferPointer<UInt8>, showingHyphen: Bool) -> DiagramMeasuredSpan {
        let written = bytes[last.start..<last.end]
        if showingHyphen, WrappedTextBytes.endsWithSoftHyphen(written) {
            // A soft hyphen is not white space, so nothing was trimmed before it.
            let text = WrappedTextBytes.hyphenShown(written)
            return DiagramMeasuredSpan(text: text, style: last.style, width: measuring.width(of: text, style: last.style))
        }
        let trimmedEnd = WrappedTextBytes.endTrimmed(written)
        var span = DiagramMeasuredSpan(text: Self.text(bytes, last.start..<trimmedEnd), style: last.style, width: last.width)
        if trimmedEnd != last.end {
            let advances = last.isPrintableASCII ? measuring.printableASCIIAdvances(of: last.style) : nil
            span.width = width(of: last.start..<trimmedEnd, in: bytes, font: SpanFont(style: last.style, advances: advances), isPrintableASCII: last.isPrintableASCII)
        }
        return span
    }

    /// The width of `range` of `bytes` in the span's font: added up from its advances where every byte is printable ASCII
    /// and the measurer adds them up, else measured as text. Either way it is the measurer's width of that text.
    private mutating func width(of range: Range<Int>, in bytes: UnsafeBufferPointer<UInt8>, font: SpanFont, isPrintableASCII: Bool? = nil) -> CGFloat {
        if let advances = font.advances, isPrintableASCII ?? bytes[range].allSatisfy(DiagramPrintableASCIIAdvances.isPrintable) {
            return advances.width(continuing: 0, over: bytes[range])
        }
        return measuring.width(of: Self.text(bytes, range), style: font.style)
    }

    private static func text(_ bytes: UnsafeBufferPointer<UInt8>, _ range: Range<Int>) -> String {
        String(decoding: UnsafeBufferPointer(rebasing: bytes[range]), as: UTF8.self)
    }
}

/// A line's UTF-8 bytes as wrapping reads them: trailing white space and soft hyphens.
private enum WrappedTextBytes {
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

    /// `text`, which ends with a soft hyphen, with the hyphen shown as `-`.
    static func hyphenShown(_ text: Slice<UnsafeBufferPointer<UInt8>>) -> String {
        String(decoding: UnsafeBufferPointer(rebasing: text.dropLast(2)), as: UTF8.self) + "-"
    }
}

/// The widths Pele works out for the pieces of a span with a soft hyphen: each piece without its trailing spaces and
/// its final soft hyphen (`own`), and the width of the rest of its word from each piece on (`rest`), unknown past the
/// span unless the span ends the line.
private struct SoftHyphenWidths {
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
