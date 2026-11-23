/**
 * File: DiagramTextWrapping.swift
 * -------------------------------
 * Layer: Core
 * Description: A line of spans wrapped at a width as Pele's wrap wraps it: between pieces, each line's trailing spaces
 *              dropped, a soft hyphen shown as a hyphen where a line breaks after it.
 *
 * Authors: Bahey Shalash
 * Version: 0.5
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
struct DiagramTextWrapping<Measurer: DiagramTextMeasuring> {
    private var measuring: DiagramStyledMeasuring<Measurer>
    private let maximumWidth: CGFloat
    private(set) var lines: [(spans: [DiagramMeasuredSpan], width: CGFloat)] = []
    private var current: [DiagramMeasuredSpan] = []
    private var width: CGFloat = 0

    init(measuring: DiagramStyledMeasuring<Measurer>, maximumWidth: CGFloat) {
        self.measuring = measuring
        self.maximumWidth = maximumWidth
    }

    /// The measurer, with the fonts it made for emphasis, to measure the next line with.
    var finishedMeasuring: DiagramStyledMeasuring<Measurer> { measuring }

    /// Lays `line` into lines; every span of a line is wrapped together, the last one ending the line.
    mutating func wrap(_ line: [DiagramMeasuredSpan]) {
        for (index, span) in line.enumerated() {
            wrap(span, isLastOfLine: index == line.count - 1)
        }
        if !current.isEmpty || lines.isEmpty { commit() }
    }

    private mutating func wrap(_ span: DiagramMeasuredSpan, isLastOfLine: Bool) {
        let pieces = DiagramTextPieces.pieces(of: span.text)
        let softHyphenWidths = span.text.unicodeScalars.contains(DiagramTextPieces.softHyphen)
            ? SoftHyphenWidths(pieces: pieces, style: span.style, isLastOfLine: isLastOfLine, measuring: &measuring) : nil
        for (index, written) in pieces.enumerated() {
            var piece = written
            let pieceWidth = softHyphenWidths?.own[index] ?? measuring.width(of: JavaScriptStringTrimming.trimmedEnd(piece), style: span.style)
            if width > 0, !fits(piece, index: index, pieceWidth: pieceWidth, style: span.style, softHyphenWidths: softHyphenWidths) {
                // Breaking at a space leaves a soft hyphen before it hidden.
                commit(showingHyphen: JavaScriptStringTrimming.trimmedStart(piece) == piece)
                piece = JavaScriptStringTrimming.trimmedStart(piece)
            }
            append(piece, pieceWidth: pieceWidth, style: span.style)
        }
    }

    private mutating func fits(_ piece: String, index: Int, pieceWidth: CGFloat, style: DiagramTextStyle, softHyphenWidths: SoftHyphenWidths?) -> Bool {
        guard let softHyphenWidths, piece.unicodeScalars.last == DiagramTextPieces.softHyphen else { return width + pieceWidth <= maximumWidth }
        var shown = piece.unicodeScalars
        shown.removeLast()
        shown.append("-")
        return width + measuring.width(of: String(shown), style: style) <= maximumWidth || width + softHyphenWidths.rest[index] <= maximumWidth
    }

    private mutating func append(_ piece: String, pieceWidth: CGFloat, style: DiagramTextStyle) {
        if var last = current.popLast() {
            if last.style == style {
                last.text += piece
                // Measured again only when the piece adds width, so that zero-width pieces take no time.
                if pieceWidth > 0 || JavaScriptStringTrimming.endsWithWhitespace(piece) {
                    let before = last.width
                    last.width = measuring.width(of: last.text, style: style)
                    width += last.width - before
                }
                current.append(last)
                return
            }
            current.append(last)
        }
        let pieceFullWidth = measuring.width(of: piece, style: style)
        current.append(DiagramMeasuredSpan(text: piece, style: style, width: pieceFullWidth))
        width += pieceFullWidth
    }

    /// Ends the line: its last span's trailing spaces dropped and, when `showingHyphen`, a soft hyphen it ends with
    /// shown as `-`.
    private mutating func commit(showingHyphen: Bool = false) {
        if var last = current.popLast() {
            var trimmed = JavaScriptStringTrimming.trimmedEnd(last.text)
            if showingHyphen, last.text.unicodeScalars.last == DiagramTextPieces.softHyphen {
                var shown = trimmed.unicodeScalars
                shown.removeLast()
                shown.append("-")
                trimmed = String(shown)
            }
            if trimmed != last.text {
                last.text = trimmed
                let trimmedWidth = measuring.width(of: trimmed, style: last.style)
                width += trimmedWidth - last.width
                last.width = trimmedWidth
            }
            current.append(last)
        }
        lines.append((current, width))
        current = []
        width = 0
    }
}

/// The widths Pele works out for the pieces of a span with a soft hyphen: each piece without its trailing spaces and
/// its final soft hyphen (`own`), and the width of the rest of its word from each piece on (`rest`), unknown past the
/// span unless the span ends the line.
private struct SoftHyphenWidths {
    let own: [CGFloat]
    let rest: [CGFloat]

    init<Measurer>(pieces: [String], style: DiagramTextStyle, isLastOfLine: Bool, measuring: inout DiagramStyledMeasuring<Measurer>) {
        var own = [CGFloat](repeating: 0, count: pieces.count)
        var rest = [CGFloat](repeating: 0, count: pieces.count + 1)
        for index in pieces.indices.reversed() {
            let endsWithHyphen = pieces[index].unicodeScalars.last == DiagramTextPieces.softHyphen
            var end = JavaScriptStringTrimming.trimmedEnd(pieces[index]).unicodeScalars
            if endsWithHyphen { end.removeLast() }
            own[index] = measuring.width(of: String(end), style: style)
            if !endsWithHyphen {
                rest[index] = own[index]
            } else if index == pieces.count - 1 {
                rest[index] = isLastOfLine ? own[index] : .infinity
            } else {
                rest[index] = own[index] + rest[index + 1]
            }
        }
        self.own = own
        self.rest = rest
    }
}
