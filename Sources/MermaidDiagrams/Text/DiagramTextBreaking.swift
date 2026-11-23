/**
 * File: DiagramTextBreaking.swift
 * -------------------------------
 * Layer: Core
 * Description: Text that may not grow past a width: lines broken between characters, literal text that keeps every
 *              character, and a block's lines placed from their left or right end, as Pele writes text by its start.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 23/11/2026
 */

import CoreGraphics

extension DiagramTextBlock {
    /// A block of lines already measured.
    init(lines: [String], lineWidths: [CGFloat], fontSize: CGFloat, lineHeight: CGFloat, center: CGPoint = .zero) {
        self.lines = lines
        self.lineWidths = lineWidths
        self.fontSize = fontSize
        self.lineHeight = lineHeight
        self.center = center
    }

    /// `label` wrapped at spaces to `maximumWidth`, and each line still wider broken between characters, as Pele's kanban
    /// fits a card's text: a card cannot grow sideways to hold a long word. The lines keep the distance of the wrapped
    /// text, as Pele's `fitLabel` and `breakLabel` keep its label's: 1.3 sizes when it wrapped to several lines, 1.5 when a
    /// single line is broken.
    init(label: DiagramLabel, measurer: some DiagramTextMeasuring, fittingWidth maximumWidth: CGFloat) {
        self.init(label: label, measurer: measurer, wrappingWidth: maximumWidth, breakingWidth: maximumWidth)
    }

    /// `label` wrapped at spaces to `wrappingWidth`, and each line still wider than `breakingWidth` broken between
    /// characters, as Pele's `layoutLabel` then `breakLabel` set a text (a sequence diagram's in a tight layout).
    init(label: DiagramLabel, measurer: some DiagramTextMeasuring, wrappingWidth: CGFloat, breakingWidth maximumWidth: CGFloat) {
        let wrapped = DiagramTextBlock(label: label, measurer: measurer, maximumWidth: wrappingWidth)
        guard wrapped.lineWidths.contains(where: { width in width > maximumWidth }) else {
            self = wrapped
            return
        }
        var measuring = DiagramStyledMeasuring(measurer)
        var measured = DiagramMeasuredLines(keepsRuns: wrapped.lineRuns != nil)
        for index in wrapped.lines.indices {
            let spans = wrapped.runs(ofLine: index).map { run in DiagramMeasuredSpan(text: run.text, style: run.style, width: run.width) }
            guard wrapped.lineWidths[index] > maximumWidth else {
                measured.add(spans, width: wrapped.lineWidths[index])
                continue
            }
            Self.breakBetweenCharacters(spans, into: &measured, measuring: &measuring, maximumWidth: maximumWidth)
        }
        self.init(lines: measured.lines, lineWidths: measured.widths, fontSize: measurer.fontSize, lineHeight: wrapped.lineHeight)
        lineRuns = measured.hasEmphasis ? measured.runs : nil
    }

    /// A line's spans broken between characters where the line passes `maximumWidth`, each piece of a span measured in
    /// its emphasis, as Pele's `fitLabel` and `breakLabel` break a span.
    private static func breakBetweenCharacters<Measurer>(_ spans: [DiagramMeasuredSpan], into measured: inout DiagramMeasuredLines,
                                                          measuring: inout DiagramStyledMeasuring<Measurer>, maximumWidth: CGFloat) {
        var current: [DiagramMeasuredSpan] = []
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
                    current.append(DiagramMeasuredSpan(text: String(character), style: span.style, width: added))
                }
                width += added
            }
        }
        measured.add(current, width: width)
    }

    /// Text that keeps every character but the spaces a line breaks at, as Pele's literal labels (a file's name) do:
    /// each written line broken where it passes `room`, at the last space before that when there is one, else between
    /// characters. Empty text has no lines.
    init(literal text: String, measurer: some DiagramTextMeasuring, room: CGFloat) {
        var lines: [String] = []
        if !text.isEmpty {
            for written in text.split(separator: "\n", omittingEmptySubsequences: false) {
                lines += Self.literalLines(written, measurer: measurer, room: room)
            }
        }
        self.init(lines: lines, lineWidths: lines.map { line in measurer.width(of: line) }, fontSize: measurer.fontSize,
                  lineHeight: measurer.lineHeight)
    }

    /// One written line's lines. Each probe measures a String made from a slice of `written` between two of its
    /// characters' boundaries, the same text as the characters it holds, so the widths are those of the characters joined.
    private static func literalLines(_ written: Substring, measurer: some DiagramTextMeasuring, room: CGFloat) -> [String] {
        guard !written.isEmpty else { return [""] }
        // Where each character starts, and the end, then whether each is white space: read once, so that no probe walks
        // the characters again. A character is white space by its first scalar, as `Character.isWhitespace` decides, and
        // one that starts with an ASCII byte is decided from that byte.
        let bytes = written.utf8
        var boundaries: [String.Index] = []
        var isWhitespace: [Bool] = []
        boundaries.reserveCapacity(bytes.count + 1)
        isWhitespace.reserveCapacity(bytes.count)
        for index in written.indices {
            boundaries.append(index)
            let firstByte = bytes[index]
            isWhitespace.append(firstByte < 0x80 ? Self.isASCIIWhitespace(firstByte) : written[index].isWhitespace)
        }
        boundaries.append(written.endIndex)
        let characterCount = isWhitespace.count
        func text(_ start: Int, _ end: Int) -> String { String(written[boundaries[start]..<boundaries[end]]) }
        var lines: [String] = []
        var start = 0
        while start < characterCount {
            // The most characters that fit, found by doubling and then halving, so that a long line is measured a few
            // dozen times rather than once per character.
            let remaining = characterCount - start
            func fits(_ length: Int) -> Bool { measurer.width(of: text(start, start + length)) <= room }
            var upper = 1
            while upper < remaining, fits(upper) { upper = min(remaining, upper * 2) }
            var taken = 1
            while taken < upper {
                let middle = (taken + upper + 1) / 2
                if fits(middle) { taken = middle } else { upper = middle - 1 }
            }
            let wraps = start + taken < characterCount
            if wraps, !isWhitespace[start + taken], let lastSpace = (1..<taken).last(where: { offset in isWhitespace[start + offset] }) {
                taken = lastSpace + 1
            }
            var trimmedEnd = start + taken
            while trimmedEnd > start, isWhitespace[trimmedEnd - 1] { trimmedEnd -= 1 }
            lines.append(wraps && trimmedEnd > start ? text(start, trimmedEnd) : text(start, start + taken))
            start += taken
            while wraps, start < characterCount, isWhitespace[start] { start += 1 }
        }
        return lines
    }

    /// Whether an ASCII byte is Unicode white space: a tab, a line feed, a line tabulation, a form feed, a carriage return
    /// or a space.
    private static func isASCIIWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || (0x09...0x0D).contains(byte)
    }

    /// Each line as a block of its own, its left end at `left` (or its right end at `right`), the first line's box
    /// starting at `top`: text Pele writes from its start or its end rather than its middle.
    func placedLines(left: CGFloat? = nil, right: CGFloat? = nil, top: CGFloat) -> [DiagramTextBlock] {
        lines.indices.map { index in
            let width = lineWidths[index]
            let middleAcross = left.map { left in left + width / 2 } ?? (right ?? 0) - width / 2
            var line = DiagramTextBlock(lines: [lines[index]], lineWidths: [width], fontSize: fontSize, lineHeight: lineHeight,
                                        center: CGPoint(x: middleAcross, y: top + (CGFloat(index) + 0.5) * lineHeight))
            line.lineRuns = lineRuns.map { runs in [runs[index]] }
            return line
        }
    }
}
