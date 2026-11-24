/**
 * File: DiagramFlatTextWrapping.swift
 * -----------------------------------
 * Layer: Core
 * Description: Wraps a trimmed line of printable ASCII at its spaces in a face whose advances sum exactly, reading each
 *              byte once: the lines and widths, to the bit, that DiagramTextMeasuringScratch.wrapExactly gives the line
 *              as one span without emphasis.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics

enum DiagramFlatTextWrapping {
    /// The most bytes a line wrapped here may have, as for `wrapExactly`: fewer than 2^22 advances below 1,024 points of
    /// at most 20 fraction bits sum exactly in a Double.
    static let longestWrappedByteCount = DiagramTextMeasuringScratch.longestExactlyWrappedByteCount

    /// Appends the lines of `bytes[start..<end]`, a line trimmed of white space whose bytes are all printable ASCII,
    /// wrapped where it passes `maximumWidth`; `advances` sum exactly (`DiagramFontAdvances.isExactlySummable`) and the
    /// line is shorter than `longestWrappedByteCount`.
    ///
    /// As `wrapExactly` places them, the pieces are each word with the spaces after it; a piece starts a new line when
    /// the line holds some width and that width with the piece's word passes the room; a line ends without its trailing
    /// spaces. Every width is an exact sum of advances, so the word's and the spaces' sums run as two chains of additions
    /// beside the line's and give the same bits as any other order.
    static func wrap(_ bytes: UnsafePointer<UInt8>, from start: Int, to end: Int, advances: UnsafePointer<CGFloat>, maximumWidth: CGFloat,
                     into lines: inout DiagramMeasuredLines) {
        let space = UInt8(ascii: " ")
        var lineStart = start
        var lineWidth: CGFloat = 0
        var lastWordEnd = start
        var lastSpacesWidth: CGFloat = 0
        var position = start
        while position < end {
            let wordStart = position
            var wordWidth: CGFloat = 0
            while position < end, bytes[position] != space {
                wordWidth += advances[Int(bytes[position])]
                position += 1
            }
            let wordEnd = position
            var spacesWidth: CGFloat = 0
            while position < end, bytes[position] == space {
                spacesWidth += advances[Int(space)]
                position += 1
            }
            if lineWidth > 0, !(lineWidth + wordWidth <= maximumWidth) {
                lines.appendLine(start: lineStart, end: lastWordEnd, width: lineWidth - lastSpacesWidth)
                lineStart = wordStart
                lineWidth = 0
            }
            lineWidth += wordWidth + spacesWidth
            lastWordEnd = wordEnd
            lastSpacesWidth = spacesWidth
        }
        lines.appendLine(start: lineStart, end: lastWordEnd, width: lineWidth - lastSpacesWidth)
    }
}
