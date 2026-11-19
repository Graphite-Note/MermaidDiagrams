/**
 * File: EventModelText.swift
 * --------------------------
 * Layer: Core
 * Description: The text of an event model as Pele sets it: labels wrapped at words, data and notes cut into lines of a
 *              number of characters or of a width, and lines that start at a left edge.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// How an event model's text is cut into lines and placed, as Pele's `hardWrap`, `literalLabel`, `breakLabel` and
/// `leftLabelSvg` do.
enum EventModelText {
    /// The text's entity codes decoded, split at its line breaks, each line longer than `columns` characters cut into
    /// pieces of `columns` characters.
    static func hardWrapped(_ text: String, columns: Int) -> [String] {
        DiagramLabelDecoder.decodingEntities(text).split(separator: "\n", omittingEmptySubsequences: false).flatMap { line -> [String] in
            let scalars = Array(line.unicodeScalars)
            guard scalars.count > columns else { return [String(line)] }
            return stride(from: 0, to: scalars.count, by: columns).map { start in string(of: scalars[start..<min(scalars.count, start + columns)]) }
        }
    }

    /// The text as a label is drawn (`<br>` and line breaks end lines, tags are dropped, entity codes decoded), wrapped
    /// at spaces where wider than `maximumWidth`; nil when it has nothing to draw.
    static func label(_ text: String?, measurer: some DiagramTextMeasuring, maximumWidth: CGFloat) -> DiagramTextBlock? {
        guard let text else { return nil }
        let block = DiagramTextBlock(label: DiagramLabelDecoder.label(from: text, form: .plain), measurer: measurer, maximumWidth: maximumWidth)
        return block.lines.isEmpty ? nil : block
    }

    /// One block of `lines` as they are, wrapped nowhere.
    static func block(_ lines: [String], measurer: some DiagramTextMeasuring) -> DiagramTextBlock {
        DiagramTextBlock(label: DiagramLabel(lines: lines), measurer: measurer, maximumWidth: .greatestFiniteMagnitude)
    }

    /// `block` with its center at `center`.
    static func placed(_ block: DiagramTextBlock, center: CGPoint) -> DiagramTextBlock {
        var placed = block
        placed.center = center
        return placed
    }

    /// Each non-empty row as a block of its own that starts at `left`, the middle of the first at `firstMiddle`, each
    /// next one `step` lower.
    static func rows(_ rows: [String], measurer: some DiagramTextMeasuring, left: CGFloat, firstMiddle: CGFloat, step: CGFloat) -> [DiagramTextBlock] {
        rows.enumerated().compactMap { index, row in
            guard !row.isEmpty else { return nil }
            let line = block([row], measurer: measurer)
            return placed(line, center: CGPoint(x: left + line.size.width / 2, y: firstMiddle + CGFloat(index) * step))
        }
    }

    /// The lines of literal text that keep every character but the spaces a line breaks at: each line of the text cut
    /// where it is wider than `room`, at its last space before that when there is one, else between two characters.
    static func literalLines(_ text: String, measurer: some DiagramTextMeasuring, room: CGFloat) -> [String] {
        guard !text.isEmpty else { return [] }
        var lines: [String] = []
        for written in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let scalars = Array(written.unicodeScalars)
            if scalars.isEmpty { lines.append("") }
            var start = 0
            while start < scalars.count {
                var length = fittingLength(scalars, from: start, measurer: measurer, room: room)
                let wraps = start + length < scalars.count
                if wraps, !EventModelDiagramBuilder.isWhitespace(scalars[start + length]),
                   let space = (1..<max(1, length)).reversed().first(where: { offset in EventModelDiagramBuilder.isWhitespace(scalars[start + offset]) }) {
                    length = space + 1
                }
                let line = string(of: scalars[start..<(start + length)])
                let trimmed = wraps ? string(of: scalars[start..<(start + length)].reversed().drop(while: EventModelDiagramBuilder.isWhitespace).reversed()) : line
                lines.append(trimmed.isEmpty ? line : trimmed)
                start += length
                while wraps, start < scalars.count, EventModelDiagramBuilder.isWhitespace(scalars[start]) { start += 1 }
            }
        }
        return lines
    }

    /// `block` with each line wider than `room` broken between characters, as many as fit on each line, at least one.
    static func broken(_ block: DiagramTextBlock, measurer: some DiagramTextMeasuring, room: CGFloat) -> DiagramTextBlock {
        guard block.size.width > room else { return block }
        var lines: [String] = []
        for (line, width) in zip(block.lines, block.lineWidths) {
            guard width > room else {
                lines.append(line)
                continue
            }
            var current = ""
            for scalar in line.unicodeScalars {
                let candidate = current + String(scalar)
                if !current.isEmpty, measurer.width(of: candidate) > room {
                    lines.append(current)
                    current = String(scalar)
                } else {
                    current = candidate
                }
            }
            lines.append(current)
        }
        return Self.block(lines, measurer: measurer)
    }

    /// The most characters from `start`, at least one, whose width is within `room`: found by doubling, then halving.
    private static func fittingLength(_ scalars: [Unicode.Scalar], from start: Int, measurer: some DiagramTextMeasuring, room: CGFloat) -> Int {
        let remaining = scalars.count - start
        func fits(_ length: Int) -> Bool {
            measurer.width(of: string(of: scalars[start..<(start + length)])) <= room
        }
        var high = 1
        while high < remaining, fits(high) { high = min(remaining, high * 2) }
        var low = 1
        while low < high {
            let middle = (low + high + 1) / 2
            if fits(middle) { low = middle } else { high = middle - 1 }
        }
        return low
    }

    static func string<Scalars: Sequence<Unicode.Scalar>>(of scalars: Scalars) -> String {
        var text = ""
        text.unicodeScalars.append(contentsOf: scalars)
        return text
    }
}
