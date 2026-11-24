/**
 * File: ReferenceDiagramTextWrapping.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: Release 0.7.0's measuring and wrapping of a label into Strings, kept as it was written, the oracle the
 *              measuring on bytes into a text storage is checked against to the bit: lines, widths, runs and line heights.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// A piece of a line being measured: its text, its emphasis and its width in it.
struct ReferenceMeasuredSpan {
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
/// the advances of printable ASCII (`DiagramFontAdvances`), a span of it that a piece of it joins has its width
/// continued over the piece's bytes, which is the width of the joined text to the bit; other text is measured joined.
struct ReferenceTextWrapping<Measurer: DiagramTextMeasuring> {
    private var measuring: DiagramStyledMeasuring<Measurer>
    private let maximumWidth: CGFloat
    /// The lines made so far, after the lines handed in.
    private var lines: ReferenceMeasuredLines
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
        let advances: DiagramFontAdvances?
    }

    /// Wraps into `lines`, after the lines they hold.
    init(measuring: DiagramStyledMeasuring<Measurer>, lines: ReferenceMeasuredLines, maximumWidth: CGFloat) {
        self.measuring = measuring
        self.lines = lines
        self.maximumWidth = maximumWidth
    }

    /// The measurer, with the fonts it made for emphasis, to measure the next line with.
    var finishedMeasuring: DiagramStyledMeasuring<Measurer> { measuring }

    /// The lines handed in, then the lines made.
    var finishedLines: ReferenceMeasuredLines { lines }

    /// Lays `line` into lines; every span of a line is wrapped together, the last one ending the line.
    mutating func wrap(_ line: [ReferenceMeasuredSpan]) {
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
        var softHyphenWidths: ReferenceSoftHyphenWidths?
        if ReferenceWrappedTextBytes.containsSoftHyphen(text) {
            let endsWithHyphen = pieces.map { piece in ReferenceWrappedTextBytes.endsWithSoftHyphen(bytes[piece]) }
            // A soft hyphen is not white space: a piece that ends with one has nothing to trim.
            let own = zip(pieces, endsWithHyphen).map { piece, endsWithHyphen in
                width(of: piece.lowerBound..<(endsWithHyphen ? piece.upperBound - 2 : ReferenceWrappedTextBytes.endTrimmed(bytes[piece])), in: bytes, font: font)
            }
            softHyphenWidths = ReferenceSoftHyphenWidths(own: own, endsWithHyphen: endsWithHyphen, isLastOfLine: isLastOfLine)
        }
        for (index, piece) in pieces.enumerated() {
            place(piece, of: bytes, font: font, softHyphenWidths: softHyphenWidths, index: index)
        }
    }

    /// Places piece `index` of its span on the line, or on a new line where it does not fit.
    private mutating func place(_ written: Range<Int>, of bytes: UnsafeBufferPointer<UInt8>, font: SpanFont, softHyphenWidths: ReferenceSoftHyphenWidths?,
                                index: Int) {
        var piece = written
        let isPrintableASCII = bytes[piece].allSatisfy(DiagramFontAdvances.isPrintable)
        let pieceWidth = softHyphenWidths?.own[index]
            ?? width(of: piece.lowerBound..<ReferenceWrappedTextBytes.endTrimmed(bytes[piece]), in: bytes, font: font, isPrintableASCII: isPrintableASCII)
        if width > 0, !fits(piece, of: bytes, index: index, pieceWidth: pieceWidth, style: font.style, softHyphenWidths: softHyphenWidths) {
            // Breaking at a space leaves a soft hyphen before it hidden.
            let start = JavaScriptWhitespace.endOfRun(in: bytes[piece], from: piece.lowerBound)
            commit(bytes, showingHyphen: start == piece.lowerBound)
            piece = start..<piece.upperBound
        }
        append(piece, of: bytes, isPrintableASCII: isPrintableASCII, pieceWidth: pieceWidth, font: font)
    }

    private mutating func fits(_ piece: Range<Int>, of bytes: UnsafeBufferPointer<UInt8>, index: Int, pieceWidth: CGFloat, style: DiagramTextStyle,
                               softHyphenWidths: ReferenceSoftHyphenWidths?) -> Bool {
        guard let softHyphenWidths, ReferenceWrappedTextBytes.endsWithSoftHyphen(bytes[piece]) else { return width + pieceWidth <= maximumWidth }
        return width + measuring.width(of: ReferenceWrappedTextBytes.hyphenShown(bytes[piece]), style: style) <= maximumWidth
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
        var spans: [ReferenceMeasuredSpan] = []
        spans.reserveCapacity(current.count)
        for span in current.dropLast() {
            spans.append(ReferenceMeasuredSpan(text: Self.text(bytes, span.start..<span.end), style: span.style, width: span.width))
        }
        spans.append(lastSpan)
        lines.add(spans, width: width)
    }

    /// The line's last span as it ends the line: its trailing spaces dropped, or a soft hyphen it ends with shown as `-`,
    /// and measured again when that changed it.
    private mutating func committed(_ last: WrappedSpan, of bytes: UnsafeBufferPointer<UInt8>, showingHyphen: Bool) -> ReferenceMeasuredSpan {
        let written = bytes[last.start..<last.end]
        if showingHyphen, ReferenceWrappedTextBytes.endsWithSoftHyphen(written) {
            // A soft hyphen is not white space, so nothing was trimmed before it.
            let text = ReferenceWrappedTextBytes.hyphenShown(written)
            return ReferenceMeasuredSpan(text: text, style: last.style, width: measuring.width(of: text, style: last.style))
        }
        let trimmedEnd = ReferenceWrappedTextBytes.endTrimmed(written)
        var span = ReferenceMeasuredSpan(text: Self.text(bytes, last.start..<trimmedEnd), style: last.style, width: last.width)
        if trimmedEnd != last.end {
            let advances = last.isPrintableASCII ? measuring.printableASCIIAdvances(of: last.style) : nil
            span.width = width(of: last.start..<trimmedEnd, in: bytes, font: SpanFont(style: last.style, advances: advances), isPrintableASCII: last.isPrintableASCII)
        }
        return span
    }

    /// The width of `range` of `bytes` in the span's font: added up from its advances where every byte is printable ASCII
    /// and the measurer adds them up, else measured as text. Either way it is the measurer's width of that text.
    private mutating func width(of range: Range<Int>, in bytes: UnsafeBufferPointer<UInt8>, font: SpanFont, isPrintableASCII: Bool? = nil) -> CGFloat {
        if let advances = font.advances, isPrintableASCII ?? bytes[range].allSatisfy(DiagramFontAdvances.isPrintable) {
            return advances.width(continuing: 0, over: bytes[range])
        }
        return measuring.width(of: Self.text(bytes, range), style: font.style)
    }

    private static func text(_ bytes: UnsafeBufferPointer<UInt8>, _ range: Range<Int>) -> String {
        String(decoding: UnsafeBufferPointer(rebasing: bytes[range]), as: UTF8.self)
    }
}

/// A line's UTF-8 bytes as wrapping reads them: trailing white space and soft hyphens.
private enum ReferenceWrappedTextBytes {
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
private struct ReferenceSoftHyphenWidths {
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

/// The lines of a block as they are measured and wrapped, with their runs.
struct ReferenceMeasuredLines {
    /// Whether the runs are kept: a label without emphasis has none to keep.
    let keepsRuns: Bool
    var lines: [String] = []
    var widths: [CGFloat] = []
    var runs: [[DiagramTextRun]] = []
    var hasEmphasis = false

    /// Measures line `index` of `label`, wrapping it where it is wider than `maximumWidth` and can break.
    mutating func add<Measurer>(_ label: DiagramLabel, line index: Int, measuring: inout DiagramStyledMeasuring<Measurer>, maximumWidth: CGFloat) {
        guard label.spans != nil else {
            let line = label.lines[index]
            let width = measuring.measurer.width(of: line)
            guard width > maximumWidth, Self.canBreak(line, isReadWithoutMarkup: label.isReadWithoutMarkup) else {
                return line.isEmpty ? add([], width: width) : add(ReferenceMeasuredSpan(text: line, style: [], width: width), width: width)
            }
            return wrap([ReferenceMeasuredSpan(text: line, style: [], width: width)], measuring: &measuring, maximumWidth: maximumWidth)
        }
        let spans = label.spans(ofLine: index).map { span in
            ReferenceMeasuredSpan(text: span.text, style: span.style, width: measuring.width(of: span.text, style: span.style))
        }
        let width = spans.reduce(0) { total, span in total + span.width }
        guard width > maximumWidth else { return add(spans, width: width) }
        wrap(spans, measuring: &measuring, maximumWidth: maximumWidth)
    }

    /// Wraps `spans`, the lines going straight into these lines: they are handed to the wrapping and taken back, so
    /// that their arrays stay uniquely held and grow in place.
    private mutating func wrap<Measurer>(_ spans: [ReferenceMeasuredSpan], measuring: inout DiagramStyledMeasuring<Measurer>, maximumWidth: CGFloat) {
        var handed = ReferenceMeasuredLines(keepsRuns: keepsRuns)
        swap(&handed, &self)
        var wrapping = ReferenceTextWrapping(measuring: measuring, lines: consume handed, maximumWidth: maximumWidth)
        wrapping.wrap(spans)
        measuring = wrapping.finishedMeasuring
        self = wrapping.finishedLines
    }

    /// Room for `lineCount` more lines.
    mutating func reserveCapacity(_ lineCount: Int) {
        lines.reserveCapacity(lines.count + lineCount)
        widths.reserveCapacity(widths.count + lineCount)
        if keepsRuns { runs.reserveCapacity(runs.count + lineCount) }
    }

    mutating func add(_ spans: [ReferenceMeasuredSpan], width: CGFloat) {
        lines.append(spans.count == 1 ? spans[0].text : spans.map(\.text).joined())
        widths.append(width)
        guard keepsRuns else { return }
        runs.append(spans.map(\.run))
        if spans.contains(where: { span in !span.style.isEmpty }) { hasEmphasis = true }
    }

    /// A line of one span, `add([span], width:)` without the array.
    mutating func add(_ span: ReferenceMeasuredSpan, width: CGFloat) {
        lines.append(span.text)
        widths.append(width)
        guard keepsRuns else { return }
        runs.append([span.run])
        if !span.style.isEmpty { hasEmphasis = true }
    }

    /// Whether wrapping can break `line`, as Pele's layoutLabel decides: a line read without markup only at a plain space
    /// (`text.includes(' ')`), a Chinese or Japanese character or a break hint; a line read for its markup at any white space.
    /// An ASCII line, which holds no Chinese or Japanese character and no hint, is answered from its bytes.
    private static func canBreak(_ line: String, isReadWithoutMarkup: Bool) -> Bool {
        let answerOfASCII = line.utf8.withContiguousStorageIfAvailable { bytes -> Bool? in
            // JavaScript's white space among ASCII bytes is the space and tab to carriage return.
            var isASCII = true
            for byte in bytes {
                if byte >= 0x80 {
                    isASCII = false
                } else if byte == UInt8(ascii: " ") || (!isReadWithoutMarkup && (0x09...0x0D).contains(byte)) {
                    return true
                }
            }
            return isASCII ? false : nil
        }
        if let answer = answerOfASCII ?? nil { return answer }
        return line.unicodeScalars.contains { scalar in
            (isReadWithoutMarkup ? scalar == " " : JavaScriptStringTrimming.isWhitespace(scalar)) || DiagramTextPieces.isCJK(scalar)
                || DiagramTextPieces.isHint(scalar)
        }
    }
}

/// A block as release 0.7.0 measured it: its lines, their widths, their runs when one has emphasis, and its line height.
struct ReferenceTextBlock: Equatable {
    var lines: [String]
    var lineWidths: [CGFloat]
    var lineRuns: [[DiagramTextRun]]?
    var lineHeight: CGFloat

    /// 0.7.0's `DiagramTextBlock(label:measurer:maximumWidth:)`.
    init(label: DiagramLabel, measurer: some DiagramTextMeasuring, maximumWidth: CGFloat) {
        var measured = ReferenceMeasuredLines(keepsRuns: label.spans != nil)
        if !label.isEmpty {
            measured.reserveCapacity(label.lines.count)
            var measuring = DiagramStyledMeasuring(measurer)
            for index in label.lines.indices {
                measured.add(label, line: index, measuring: &measuring, maximumWidth: maximumWidth)
            }
        }
        lines = measured.lines
        lineWidths = measured.widths
        lineHeight = DiagramTextBlock.lineHeight(lineCount: measured.lines.count, measurer: measurer)
        lineRuns = measured.hasEmphasis ? measured.runs : nil
    }

    /// 0.7.0's `DiagramTextBlock(label:measurer:wrappingWidth:breakingWidth:)`.
    init(label: DiagramLabel, measurer: some DiagramTextMeasuring, wrappingWidth: CGFloat, breakingWidth maximumWidth: CGFloat) {
        let wrapped = ReferenceTextBlock(label: label, measurer: measurer, maximumWidth: wrappingWidth)
        guard wrapped.lineWidths.contains(where: { width in width > maximumWidth }) else {
            self = wrapped
            return
        }
        var measuring = DiagramStyledMeasuring(measurer)
        var measured = ReferenceMeasuredLines(keepsRuns: wrapped.lineRuns != nil)
        for index in wrapped.lines.indices {
            let spans = wrapped.runs(ofLine: index).map { run in ReferenceMeasuredSpan(text: run.text, style: run.style, width: run.width) }
            guard wrapped.lineWidths[index] > maximumWidth else {
                measured.add(spans, width: wrapped.lineWidths[index])
                continue
            }
            Self.breakBetweenCharacters(spans, into: &measured, measuring: &measuring, maximumWidth: maximumWidth)
        }
        lines = measured.lines
        lineWidths = measured.widths
        lineHeight = wrapped.lineHeight
        lineRuns = measured.hasEmphasis ? measured.runs : nil
    }

    func runs(ofLine index: Int) -> [DiagramTextRun] {
        if let lineRuns { return lineRuns[index] }
        return lines[index].isEmpty ? [] : [DiagramTextRun(text: lines[index], style: [], width: lineWidths[index])]
    }

    /// A line's spans broken between characters where the line passes `maximumWidth`, each piece of a span measured in
    /// its emphasis, as Pele's `fitLabel` and `breakLabel` break a span.
    static func breakBetweenCharacters<Measurer>(_ spans: [ReferenceMeasuredSpan], into measured: inout ReferenceMeasuredLines,
                                                          measuring: inout DiagramStyledMeasuring<Measurer>, maximumWidth: CGFloat) {
        var current: [ReferenceMeasuredSpan] = []
        var width: CGFloat = 0
        for span in spans {
            for character in span.text {
                var last = current.last.flatMap { last in last.style == span.style ? last : nil }
                var added = measuring.width(of: (last?.text ?? "") + String(character), style: span.style) - (last?.width ?? 0)
                if !current.isEmpty, width + added > maximumWidth {
                    measured.add(current, width: width)
                    current = []
                    width = 0
                    last = nil
                    added = measuring.width(of: String(character), style: span.style)
                }
                if var joined = last {
                    joined.text.append(character)
                    joined.width += added
                    current[current.count - 1] = joined
                } else {
                    current.append(ReferenceMeasuredSpan(text: String(character), style: span.style, width: added))
                }
                width += added
            }
        }
        measured.add(current, width: width)
    }

}
