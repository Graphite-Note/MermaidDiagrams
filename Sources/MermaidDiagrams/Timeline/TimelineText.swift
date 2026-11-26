/**
 * File: TimelineText.swift
 * ------------------------
 * Layer: Core
 * Description: A timeline's section, period or event text as a range of its text's bytes: trimmed on its bytes when it
 *              is ASCII, its label made as the reader made it in 0.7.0, and measured from its bytes when it can be.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics
import Foundation

/// A section's, period's or event's text: an ASCII text trimmed of white space (the tab to the carriage return and the
/// space, Foundation's white space and line breaks within ASCII), any other as written, to be trimmed by Foundation
/// when its label is made, as 0.7.0 trimmed every text.
struct TimelineText: Equatable, Sendable {
    var range: MermaidTextRange
    var isASCII: Bool

    /// The text from `start` to `end` of `bytes`, trimmed when it is ASCII.
    static func read(_ bytes: UnsafeBufferPointer<UInt8>, from start: Int, to end: Int) -> TimelineText {
        var combined: UInt8 = 0
        for index in start..<end { combined |= bytes[index] }
        guard combined < 0x80 else { return TimelineText(range: MermaidTextRange(start: start, end: end), isASCII: false) }
        var first = start
        var last = end
        while first < last, isWhiteSpace(bytes[first]) { first += 1 }
        while last > first, isWhiteSpace(bytes[last - 1]) { last -= 1 }
        return TimelineText(range: MermaidTextRange(start: first, end: last), isASCII: true)
    }

    private static func isWhiteSpace(_ byte: UInt8) -> Bool { (byte >= 0x09 && byte <= 0x0D) || byte == 0x20 }

    /// Its label: from its bytes when ASCII, else from its String trimmed by Foundation.
    static func label(_ text: TimelineText, in bytes: UnsafeBufferPointer<UInt8>) -> DiagramLabel {
        let slice = UnsafeBufferPointer(rebasing: bytes[text.range.lowerBound..<text.range.upperBound])
        if text.isASCII { return DiagramLabelDecoder.label(fromUTF8: slice, form: .literal) }
        return DiagramLabelDecoder.label(from: String(decoding: slice, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines), form: .literal)
    }

    /// The text measured and wrapped at `maximumWidth` (`TimelineTextFitting.wrapped`), or with a word too wide cut into
    /// pieces that fit (`fitted`), its lines appended to `lines`: an ASCII text from its bytes, any other from its label.
    static func measured<Measurer>(_ text: TimelineText, in bytes: UnsafeBufferPointer<UInt8>, measurer: DiagramFlatMeasurer<Measurer>,
                                   maximumWidth: CGFloat, cutsWideWords: Bool, into lines: inout DiagramMeasuredLines) -> DiagramMeasuredText {
        if text.isASCII {
            let firstLine = lines.count
            let measured = DiagramFlatTextMeasuring.measure(bytes, text.range, form: .literal, measurer: measurer, maximumWidth: maximumWidth, into: &lines)
            guard cutsWideWords, measured.width > maximumWidth else { return measured }
            lines.removeLines(from: firstLine)
        }
        let label = label(text, in: bytes)
        let block = cutsWideWords ? TimelineTextFitting.fitted(label, measurer: measurer.measurer, maximumWidth: maximumWidth)
            : TimelineTextFitting.wrapped(label, measurer: measurer.measurer, maximumWidth: maximumWidth)
        return DiagramFlatTextMeasuring.copied(block, into: &lines)
    }
}
