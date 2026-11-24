/**
 * File: DiagramTextBlock.swift
 * ----------------------------
 * Layer: Core
 * Description: Lines of a diagram's text measured in a font and placed around a center, wrapped at a width as Pele's
 *              layoutLabel wraps them, a text of more than one line set 1.3 times its size apart.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.3
 * Date: 23/11/2026
 */

import CoreGraphics

/// Lines of text placed in a diagram: each line's width in the font it was measured in, and where the block's center is.
/// Lines are drawn centered on the block's center, one `lineHeight` apart: the measurer's line height (1.5 times the size)
/// for a single line, 1.3 times the size, rounded, for a text of more than one (Pele's `WRAPPED_LINE_HEIGHT`).
public struct DiagramTextBlock: Equatable, Sendable {
    public let lines: [String]
    public let lineWidths: [CGFloat]
    public let fontSize: CGFloat
    public let lineHeight: CGFloat
    public internal(set) var center: CGPoint
    /// Each line's pieces in their emphasis, one after the other from the line's start, or nil when every line is in the
    /// text's own font. A line's runs hold its characters, and their widths add up to its width.
    public internal(set) var lineRuns: [[DiagramTextRun]]? = nil

    public var size: CGSize {
        CGSize(width: lineWidths.max() ?? 0, height: CGFloat(lines.count) * lineHeight)
    }

    /// Measures `label` in `measurer`'s font, each span in its emphasis, as Pele's `layoutLabel` measures it, and
    /// wraps a line wider than `maximumWidth` between its pieces (`DiagramTextWrapping`). A word wider than that stays
    /// whole on its own line. An empty label has no lines.
    init(label: DiagramLabel, measurer: some DiagramTextMeasuring, maximumWidth: CGFloat) {
        if TextPrototypeRecorder.isRecording { TextPrototypeRecorder.recordBlock(label: label, measurer: measurer, maximumWidth: maximumWidth) }
        var measured = DiagramMeasuredLines(keepsRuns: label.spans != nil)
        if !label.isEmpty {
            measured.reserveCapacity(label.lines.count)
            var measuring = DiagramStyledMeasuring(measurer)
            for index in label.lines.indices {
                measured.add(label, line: index, measuring: &measuring, maximumWidth: maximumWidth)
            }
        }
        self.lines = measured.lines
        self.lineWidths = measured.widths
        self.fontSize = measurer.fontSize
        self.lineHeight = Self.lineHeight(lineCount: measured.lines.count, measurer: measurer)
        self.center = .zero
        self.lineRuns = measured.hasEmphasis ? measured.runs : nil
    }

    /// Pele's distance between the lines of a text of more than one line, as a multiple of the size
    /// (text/label.ts `WRAPPED_LINE_HEIGHT`), which makes the lines read as one block.
    static let severalLinesHeightRatio: CGFloat = 1.3

    /// The distance between lines of a text of `lineCount` lines, as Pele's `layoutLabel` sets it: the measurer's own for
    /// one line or none, 1.3 times the size, rounded, for more.
    static func lineHeight(lineCount: Int, measurer: some DiagramTextMeasuring) -> CGFloat {
        lineCount > 1 ? (measurer.fontSize * severalLinesHeightRatio).rounded() : measurer.lineHeight
    }

    /// The runs of line `index`: its own, or the line as one run in the text's own font.
    func runs(ofLine index: Int) -> [DiagramTextRun] {
        if let lineRuns { return lineRuns[index] }
        return lines[index].isEmpty ? [] : [DiagramTextRun(text: lines[index], style: [], width: lineWidths[index])]
    }
}

/// The lines of a block as they are measured and wrapped, with their runs.
struct DiagramMeasuredLines {
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
                return line.isEmpty ? add([], width: width) : add(DiagramMeasuredSpan(text: line, style: [], width: width), width: width)
            }
            return wrap([DiagramMeasuredSpan(text: line, style: [], width: width)], measuring: &measuring, maximumWidth: maximumWidth)
        }
        let spans = label.spans(ofLine: index).map { span in
            DiagramMeasuredSpan(text: span.text, style: span.style, width: measuring.width(of: span.text, style: span.style))
        }
        let width = spans.reduce(0) { total, span in total + span.width }
        guard width > maximumWidth else { return add(spans, width: width) }
        wrap(spans, measuring: &measuring, maximumWidth: maximumWidth)
    }

    /// Wraps `spans`, the lines going straight into these lines: they are handed to the wrapping and taken back, so
    /// that their arrays stay uniquely held and grow in place.
    private mutating func wrap<Measurer>(_ spans: [DiagramMeasuredSpan], measuring: inout DiagramStyledMeasuring<Measurer>, maximumWidth: CGFloat) {
        var handed = DiagramMeasuredLines(keepsRuns: keepsRuns)
        swap(&handed, &self)
        var wrapping = DiagramTextWrapping(measuring: measuring, lines: consume handed, maximumWidth: maximumWidth)
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

    mutating func add(_ spans: [DiagramMeasuredSpan], width: CGFloat) {
        lines.append(spans.count == 1 ? spans[0].text : spans.map(\.text).joined())
        widths.append(width)
        guard keepsRuns else { return }
        runs.append(spans.map(\.run))
        if spans.contains(where: { span in !span.style.isEmpty }) { hasEmphasis = true }
    }

    /// A line of one span, `add([span], width:)` without the array.
    mutating func add(_ span: DiagramMeasuredSpan, width: CGFloat) {
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

extension DiagramTextBlock {
    func translated(by offset: CGVector) -> DiagramTextBlock {
        var moved = self
        moved.center = center.translated(by: offset)
        return moved
    }

    /// The block's rectangle around its center.
    var frame: CGRect {
        CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    }
}
