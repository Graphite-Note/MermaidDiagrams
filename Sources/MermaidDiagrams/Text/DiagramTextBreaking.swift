/**
 * File: DiagramTextBreaking.swift
 * -------------------------------
 * Layer: Core
 * Description: Text that may not grow past a width: lines broken between characters, literal text that keeps every
 *              character, and a block's lines placed from their left or right end, as Pele writes text by its start.
 *
 * Authors: Bahey Shalash
 * Version: 0.5
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
        let wrapped = DiagramTextBlock(label: label, measurer: measurer, maximumWidth: maximumWidth)
        var lines: [String] = []
        var widths: [CGFloat] = []
        for (line, width) in zip(wrapped.lines, wrapped.lineWidths) {
            guard width > maximumWidth else {
                lines.append(line)
                widths.append(width)
                continue
            }
            var current = ""
            var currentWidth: CGFloat = 0
            for character in line {
                let candidate = current + String(character)
                let candidateWidth = measurer.width(of: candidate)
                if !current.isEmpty, candidateWidth > maximumWidth {
                    lines.append(current)
                    widths.append(currentWidth)
                    current = String(character)
                    currentWidth = measurer.width(of: current)
                } else {
                    current = candidate
                    currentWidth = candidateWidth
                }
            }
            lines.append(current)
            widths.append(currentWidth)
        }
        self.init(lines: lines, lineWidths: widths, fontSize: measurer.fontSize, lineHeight: wrapped.lineHeight)
    }

    /// Text that keeps every character but the spaces a line breaks at, as Pele's literal labels (a file's name) do:
    /// each written line broken where it passes `room`, at the last space before that when there is one, else between
    /// characters. Empty text has no lines.
    init(literal text: String, measurer: some DiagramTextMeasuring, room: CGFloat) {
        var lines: [String] = []
        if !text.isEmpty {
            for written in text.split(separator: "\n", omittingEmptySubsequences: false) {
                lines += Self.literalLines(Array(written), measurer: measurer, room: room)
            }
        }
        self.init(lines: lines, lineWidths: lines.map { line in measurer.width(of: line) }, fontSize: measurer.fontSize,
                  lineHeight: measurer.lineHeight)
    }

    private static func literalLines(_ characters: [Character], measurer: some DiagramTextMeasuring, room: CGFloat) -> [String] {
        guard !characters.isEmpty else { return [""] }
        var lines: [String] = []
        var start = 0
        while start < characters.count {
            // The most characters that fit, found by doubling and then halving, so that a long line is measured a few
            // dozen times rather than once per character.
            let remaining = characters.count - start
            func fits(_ length: Int) -> Bool { measurer.width(of: String(characters[start..<(start + length)])) <= room }
            var upper = 1
            while upper < remaining, fits(upper) { upper = min(remaining, upper * 2) }
            var taken = 1
            while taken < upper {
                let middle = (taken + upper + 1) / 2
                if fits(middle) { taken = middle } else { upper = middle - 1 }
            }
            let wraps = start + taken < characters.count
            if wraps, !characters[start + taken].isWhitespace,
               let lastSpace = (1..<taken).last(where: { offset in characters[start + offset].isWhitespace }) {
                taken = lastSpace + 1
            }
            let line = String(characters[start..<(start + taken)])
            let trimmed = String(line.reversed().drop { character in character.isWhitespace }.reversed())
            lines.append(wraps && !trimmed.isEmpty ? trimmed : line)
            start += taken
            while wraps, start < characters.count, characters[start].isWhitespace { start += 1 }
        }
        return lines
    }

    /// Each line as a block of its own, its left end at `left` (or its right end at `right`), the first line's box
    /// starting at `top`: text Pele writes from its start or its end rather than its middle.
    func placedLines(left: CGFloat? = nil, right: CGFloat? = nil, top: CGFloat) -> [DiagramTextBlock] {
        lines.indices.map { index in
            let width = lineWidths[index]
            let middleAcross = left.map { left in left + width / 2 } ?? (right ?? 0) - width / 2
            return DiagramTextBlock(lines: [lines[index]], lineWidths: [width], fontSize: fontSize, lineHeight: lineHeight,
                                    center: CGPoint(x: middleAcross, y: top + (CGFloat(index) + 0.5) * lineHeight))
        }
    }
}
