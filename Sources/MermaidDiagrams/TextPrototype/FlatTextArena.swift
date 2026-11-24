/**
 * File: FlatTextArena.swift
 * -------------------------
 * Layer: Prototype
 * Description: Measures and wraps decoded labels held as byte ranges, as DiagramTextBlock and DiagramTextWrapping do,
 *              into measured line and run records, with no String and no allocation once its lists have grown.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics

/// One buffer of label bytes, the decoded labels' records, and the measured lines and runs made from them.
struct FlatTextArena {
    var bytes: [UInt8] = []
    var labelLines: [FlatLabelLine] = []
    var labelSpans: [FlatLabelSpan] = []
    var lines: [FlatMeasuredLine] = []
    var runs: [FlatMeasuredRun] = []
    /// The spans of the line being wrapped, and of the line being filled.
    private var lineSpans: [FlatMeasuredRun] = []
    private var current: [FlatMeasuredRun] = []
    private var width: CGFloat = 0
    private var madeLineCount = 0
    private var hasEmphasis = false
    /// Whether the label holds text beyond printable ASCII that must be wrapped, which the prototype leaves to the present path.
    private var isBeyondPrototype = false

    mutating func removeMeasured() {
        lines.removeAll(keepingCapacity: true)
        runs.removeAll(keepingCapacity: true)
    }

    /// `label` measured in `fonts` and wrapped at `maximumWidth`; nil when it holds a byte beyond printable ASCII,
    /// which the prototype leaves to the present path.
    mutating func measure(_ label: FlatLabel, fonts: FlatFontStyles, maximumWidth: CGFloat) -> FlatTextBlock? {
        let firstLine = Int32(lines.count)
        if label.lineCount == 1, !label.hasSpans, label.isPrintableASCII, fonts.isExactlySummable {
            // Most labels: one line of printable ASCII in the text's own font.
            let line = labelLines.withUnsafeBufferPointer { lines in lines[Int(label.firstLine)] }
            let fits: CGFloat? = bytes.withUnsafeBufferPointer { bytes in
                let start = Int(line.start), end = Int(line.end)
                guard start != end else { return 0 }
                let width = Self.exactWidth(bytes, start, end, fonts.table([]))
                return width <= maximumWidth || !Self.canBreak(bytes, start, end, isReadWithoutMarkup: label.isReadWithoutMarkup) ? width : nil
            }
            if let width = fits {
                guard line.start != line.end else {
                    return FlatTextBlock(firstLine: firstLine, lineCount: 0, fontSize: fonts.fontSize, lineHeight: fonts.lineHeight, hasEmphasis: false)
                }
                runs.append(FlatMeasuredRun(start: line.start, end: line.end, width: width, style: []))
                lines.append(FlatMeasuredLine(firstRun: Int32(runs.count - 1), runCount: 1, width: width))
                return FlatTextBlock(firstLine: firstLine, lineCount: 1, fontSize: fonts.fontSize, lineHeight: fonts.lineHeight, hasEmphasis: false)
            }
        }
        let firstRun = runs.count
        isBeyondPrototype = false
        hasEmphasis = false
        let labelBytes = bytes
        labelBytes.withUnsafeBufferPointer { bytes in
            let lineStart = Int(label.firstLine)
            let lineEnd = lineStart + Int(label.lineCount)
            var isEmpty = true
            for index in lineStart..<lineEnd where labelLines[index].start != labelLines[index].end { isEmpty = false }
            guard !isEmpty else { return }
            for index in lineStart..<lineEnd {
                measureLine(labelLines[index], of: label, bytes: bytes, fonts: fonts, maximumWidth: maximumWidth)
            }
        }
        if isBeyondPrototype {
            lines.removeSubrange(Int(firstLine)...)
            runs.removeSubrange(firstRun...)
            return nil
        }
        let lineCount = Int32(lines.count) - firstLine
        let lineHeight = lineCount > 1 ? (fonts.fontSize * DiagramTextBlock.severalLinesHeightRatio).rounded() : fonts.lineHeight
        return FlatTextBlock(firstLine: firstLine, lineCount: lineCount, fontSize: fonts.fontSize, lineHeight: lineHeight,
                             hasEmphasis: hasEmphasis)
    }

    private mutating func measureLine(_ line: FlatLabelLine, of label: FlatLabel, bytes: UnsafeBufferPointer<UInt8>, fonts: FlatFontStyles,
                                      maximumWidth: CGFloat) {
        let start = Int(line.start), end = Int(line.end)
        lineSpans.removeAll(keepingCapacity: true)
        if !label.hasSpans {
            let width = !label.isPrintableASCII ? fonts.width(bytes, start, end, [])
                : fonts.isExactlySummable ? Self.exactWidth(bytes, start, end, fonts.table([])) : Self.width(bytes, start, end, fonts.table([]))
            lineSpans.append(FlatMeasuredRun(start: line.start, end: line.end, width: width, style: []))
            guard width > maximumWidth, !label.isPrintableASCII || Self.canBreak(bytes, start, end, isReadWithoutMarkup: label.isReadWithoutMarkup) else {
                return addLine(fromLineSpans: start == end, width: width)
            }
            guard label.isPrintableASCII else {
                isBeyondPrototype = true
                return
            }
            return wrap(bytes, fonts: fonts, maximumWidth: maximumWidth)
        }
        var total: CGFloat = 0
        for spanIndex in Int(line.firstSpan)..<Int(line.firstSpan + line.spanCount) {
            let span = labelSpans[spanIndex]
            let width = label.isPrintableASCII ? Self.width(bytes, Int(span.start), Int(span.end), fonts.table(span.style))
                : fonts.width(bytes, Int(span.start), Int(span.end), span.style)
            lineSpans.append(FlatMeasuredRun(start: span.start, end: span.end, width: width, style: span.style))
            total += width
        }
        guard total > maximumWidth else { return addLine(fromLineSpans: false, width: total) }
        guard label.isPrintableASCII else {
            isBeyondPrototype = true
            return
        }
        wrap(bytes, fonts: fonts, maximumWidth: maximumWidth)
    }

    /// The line's spans as one measured line, or an empty line.
    private mutating func addLine(fromLineSpans isEmpty: Bool, width: CGFloat) {
        let firstRun = Int32(runs.count)
        if !isEmpty {
            for span in lineSpans {
                runs.append(span)
                if !span.style.isEmpty { hasEmphasis = true }
            }
        }
        lines.append(FlatMeasuredLine(firstRun: firstRun, runCount: Int32(runs.count) - firstRun, width: width))
    }

    private mutating func wrap(_ bytes: UnsafeBufferPointer<UInt8>, fonts: FlatFontStyles, maximumWidth: CGFloat) {
        if fonts.isExactlySummable { return wrapExactly(bytes, fonts: fonts, maximumWidth: maximumWidth) }
        width = 0
        madeLineCount = 0
        current.removeAll(keepingCapacity: true)
        for spanIndex in lineSpans.indices {
            let span = lineSpans[spanIndex]
            let table = fonts.table(span.style)
            var start = Int(span.start)
            let end = Int(span.end)
            while start < end {
                let pieceEnd = Self.endOfASCIIPiece(bytes, from: start, end: end)
                place(start, pieceEnd, style: span.style, table: table, bytes: bytes, fonts: fonts, maximumWidth: maximumWidth)
                start = pieceEnd
            }
        }
        if !current.isEmpty || madeLineCount == 0 { commit(bytes, fonts: fonts) }
    }

    /// `wrap` for a font whose advances sum exactly: each byte's advance read once, a piece's width found from its
    /// parts, a trimmed span's width by taking its trailing spaces' off. Every width is the exact sum of its bytes'
    /// advances, as the present wrapping's are, so the lines and widths are the same to the bit.
    private mutating func wrapExactly(_ bytes: UnsafeBufferPointer<UInt8>, fonts: FlatFontStyles, maximumWidth: CGFloat) {
        width = 0
        madeLineCount = 0
        current.removeAll(keepingCapacity: true)
        for spanIndex in lineSpans.indices {
            let span = lineSpans[spanIndex]
            let table = fonts.table(span.style)
            var start = Int(span.start)
            let end = Int(span.end)
            while start < end {
                var position = start
                var leading: CGFloat = 0
                while position < end, Self.isASCIIWhitespace(bytes[position]) {
                    leading += table[Int(bytes[position])]
                    position += 1
                }
                let afterLeading = position
                var word: CGFloat = 0
                while position < end, !Self.isASCIIWhitespace(bytes[position]) {
                    word += table[Int(bytes[position])]
                    position += 1
                }
                var trailing: CGFloat = 0
                while position < end, Self.isASCIIWhitespace(bytes[position]) {
                    trailing += table[Int(bytes[position])]
                    position += 1
                }
                let pieceWidth = leading + word
                var pieceStart = start
                var placedWidth = pieceWidth + trailing
                if width > 0, !(width + pieceWidth <= maximumWidth) {
                    commitExactly(bytes, fonts: fonts)
                    pieceStart = afterLeading
                    placedWidth = word + trailing
                }
                if let lastIndex = current.indices.last, current[lastIndex].style == span.style {
                    current[lastIndex].end = Int32(position)
                    current[lastIndex].width += placedWidth
                    width += placedWidth
                } else {
                    current.append(FlatMeasuredRun(start: Int32(pieceStart), end: Int32(position), width: placedWidth, style: span.style))
                    width += placedWidth
                }
                start = position
            }
        }
        if !current.isEmpty || madeLineCount == 0 { commitExactly(bytes, fonts: fonts) }
    }

    private mutating func commitExactly(_ bytes: UnsafeBufferPointer<UInt8>, fonts: FlatFontStyles) {
        defer {
            madeLineCount += 1
            current.removeAll(keepingCapacity: true)
            width = 0
        }
        let firstRun = Int32(runs.count)
        guard let last = current.last else {
            lines.append(FlatMeasuredLine(firstRun: firstRun, runCount: 0, width: width))
            return
        }
        let table = fonts.table(last.style)
        var trimmedEnd = Int(last.end)
        var trailing: CGFloat = 0
        while trimmedEnd > Int(last.start), Self.isASCIIWhitespace(bytes[trimmedEnd - 1]) {
            trimmedEnd -= 1
            trailing += table[Int(bytes[trimmedEnd])]
        }
        let lastWidth = last.width - trailing
        width -= trailing
        for index in current.indices.dropLast() {
            runs.append(current[index])
            if !current[index].style.isEmpty { hasEmphasis = true }
        }
        runs.append(FlatMeasuredRun(start: last.start, end: Int32(trimmedEnd), width: lastWidth, style: last.style))
        if !last.style.isEmpty { hasEmphasis = true }
        lines.append(FlatMeasuredLine(firstRun: firstRun, runCount: Int32(runs.count) - firstRun, width: width))
    }

    private mutating func place(_ writtenStart: Int, _ end: Int, style: DiagramTextStyle, table: UnsafePointer<CGFloat>,
                                bytes: UnsafeBufferPointer<UInt8>, fonts: FlatFontStyles, maximumWidth: CGFloat) {
        var start = writtenStart
        let pieceWidth = Self.width(bytes, start, Self.endTrimmed(bytes, start, end), table)
        if width > 0, !(width + pieceWidth <= maximumWidth) {
            var afterSpaces = start
            while afterSpaces < end, Self.isASCIIWhitespace(bytes[afterSpaces]) { afterSpaces += 1 }
            commit(bytes, fonts: fonts)
            start = afterSpaces
        }
        if let lastIndex = current.indices.last, current[lastIndex].style == style {
            current[lastIndex].end = Int32(end)
            if pieceWidth > 0 || (end > start && Self.isASCIIWhitespace(bytes[end - 1])) {
                let before = current[lastIndex].width
                var continued = before
                var index = start
                while index < end {
                    continued += table[Int(bytes[index])]
                    index += 1
                }
                current[lastIndex].width = continued
                width += continued - before
            }
            return
        }
        let fullWidth = Self.width(bytes, start, end, table)
        current.append(FlatMeasuredRun(start: Int32(start), end: Int32(end), width: fullWidth, style: style))
        width += fullWidth
    }

    private mutating func commit(_ bytes: UnsafeBufferPointer<UInt8>, fonts: FlatFontStyles) {
        defer {
            madeLineCount += 1
            current.removeAll(keepingCapacity: true)
            width = 0
        }
        let firstRun = Int32(runs.count)
        guard let last = current.last else {
            lines.append(FlatMeasuredLine(firstRun: firstRun, runCount: 0, width: width))
            return
        }
        let trimmedEnd = Self.endTrimmed(bytes, Int(last.start), Int(last.end))
        var lastWidth = last.width
        if trimmedEnd != Int(last.end) { lastWidth = Self.width(bytes, Int(last.start), trimmedEnd, fonts.table(last.style)) }
        width += lastWidth - last.width
        for index in current.indices.dropLast() {
            runs.append(current[index])
            if !current[index].style.isEmpty { hasEmphasis = true }
        }
        runs.append(FlatMeasuredRun(start: last.start, end: Int32(trimmedEnd), width: lastWidth, style: last.style))
        if !last.style.isEmpty { hasEmphasis = true }
        lines.append(FlatMeasuredLine(firstRun: firstRun, runCount: Int32(runs.count) - firstRun, width: width))
    }

    @inline(__always)
    static func width(_ bytes: UnsafeBufferPointer<UInt8>, _ start: Int, _ end: Int, _ table: UnsafePointer<CGFloat>) -> CGFloat {
        var width: CGFloat = 0
        var index = start
        while index < end {
            width += table[Int(bytes[index])]
            index += 1
        }
        return width
    }

    /// The sum of the advances of `bytes[start..<end]` in four running sums: the same bits as adding them in order, since
    /// the font's advances are exactly summable (`FlatFontStyles.isExactlySummable`).
    @inline(__always)
    static func exactWidth(_ bytes: UnsafeBufferPointer<UInt8>, _ start: Int, _ end: Int, _ table: UnsafePointer<CGFloat>) -> CGFloat {
        var first: CGFloat = 0, second: CGFloat = 0, third: CGFloat = 0, fourth: CGFloat = 0
        var index = start
        while index + 4 <= end {
            first += table[Int(bytes[index])]
            second += table[Int(bytes[index + 1])]
            third += table[Int(bytes[index + 2])]
            fourth += table[Int(bytes[index + 3])]
            index += 4
        }
        while index < end {
            first += table[Int(bytes[index])]
            index += 1
        }
        return (first + second) + (third + fourth)
    }

    @inline(__always)
    static func isASCIIWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || (byte >= 0x09 && byte <= 0x0D)
    }

    @inline(__always)
    static func endTrimmed(_ bytes: UnsafeBufferPointer<UInt8>, _ start: Int, _ end: Int) -> Int {
        var trimmed = end
        while trimmed > start, isASCIIWhitespace(bytes[trimmed - 1]) { trimmed -= 1 }
        return trimmed
    }

    @inline(__always)
    static func endOfASCIIPiece(_ bytes: UnsafeBufferPointer<UInt8>, from start: Int, end: Int) -> Int {
        var index = start
        while index < end, isASCIIWhitespace(bytes[index]) { index += 1 }
        while index < end, !isASCIIWhitespace(bytes[index]) { index += 1 }
        while index < end, isASCIIWhitespace(bytes[index]) { index += 1 }
        return index
    }

    static func canBreak(_ bytes: UnsafeBufferPointer<UInt8>, _ start: Int, _ end: Int, isReadWithoutMarkup: Bool) -> Bool {
        for index in start..<end {
            let byte = bytes[index]
            if byte == 0x20 || (!isReadWithoutMarkup && byte >= 0x09 && byte <= 0x0D) { return true }
        }
        return false
    }
}
