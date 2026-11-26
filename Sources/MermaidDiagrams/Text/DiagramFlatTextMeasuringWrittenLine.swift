/**
 * File: DiagramFlatTextMeasuringWrittenLine.swift
 * -----------------------------------------------
 * Layer: Core
 * Description: Measures a text that a layout draws as written, one line with no markup read (`DiagramLabel(text)`: a
 *              name, a class member, a cardinality), as its block measures it: a line of printable ASCII from the
 *              face's advances, any other text through its label.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics

extension DiagramFlatTextMeasuring {
    /// `bytes[range]` measured as `DiagramTextBlock(label: DiagramLabel(text))` measures the text they spell, its lines
    /// in `bytes`. Such a label is one line as written, read without markup: a block measures it as one line, its width
    /// the face's advances added from its first byte (`DiagramFontAdvances.width(of:from:to:)`) when its bytes are
    /// printable ASCII, unless it is wider than the room and holds a space to wrap at. That line is measured here the
    /// same way, whatever markup its bytes would read as elsewhere; any other text through its label, its lines copied
    /// into the derived bytes.
    static func measure<Measurer>(writtenLine bytes: UnsafeBufferPointer<UInt8>, _ range: MermaidTextRange, measurer: DiagramFlatMeasurer<Measurer>,
                                  maximumWidth: CGFloat, into lines: inout DiagramMeasuredLines) -> DiagramMeasuredText {
        precondition(range.start >= 0 && range.start <= range.end && Int(range.end) <= bytes.count, "text range outside its source")
        if let measured = measuredAsOneWrittenLine(bytes, range, measurer: measurer, maximumWidth: maximumWidth, into: &lines) { return measured }
        let text = String(decoding: UnsafeBufferPointer(rebasing: bytes[range.lowerBound..<range.upperBound]), as: UTF8.self)
        return measure(DiagramLabel(text), measurer: measurer, maximumWidth: maximumWidth, into: &lines)
    }

    /// `text` measured as `DiagramTextBlock(label: DiagramLabel(text))` measures it, its lines copied into the derived
    /// bytes, since the String's bytes do not outlive the measuring.
    static func measure<Measurer>(writtenLine text: String, measurer: DiagramFlatMeasurer<Measurer>, maximumWidth: CGFloat,
                                  into lines: inout DiagramMeasuredLines) -> DiagramMeasuredText {
        var text = text
        return text.withUTF8 { bytes in
            let range = MermaidTextRange(start: 0, end: bytes.count)
            guard let measured = measuredAsOneWrittenLine(bytes, range, measurer: measurer, maximumWidth: maximumWidth, into: &lines) else {
                return measure(DiagramLabel(String(decoding: bytes, as: UTF8.self)), measurer: measurer, maximumWidth: maximumWidth, into: &lines)
            }
            lines.deriveLines(of: measured, source: bytes)
            return measured
        }
    }

    /// The text of printable ASCII measured as the one line its block is, or nil, with no line added, for any other.
    private static func measuredAsOneWrittenLine<Measurer>(_ bytes: UnsafeBufferPointer<UInt8>, _ range: MermaidTextRange,
                                                           measurer: DiagramFlatMeasurer<Measurer>, maximumWidth: CGFloat,
                                                           into lines: inout DiagramMeasuredLines) -> DiagramMeasuredText? {
        guard range.count > 0, let advances = measurer.advances, let base = bytes.baseAddress,
              let width = advances.width(of: base, from: Int(range.start), to: Int(range.end)) else { return nil }
        if width > maximumWidth {
            // Wider than the room: a block wraps it at its spaces, which this does not.
            for index in Int(range.start)..<Int(range.end) where base[index] == UInt8(ascii: " ") { return nil }
        }
        let firstLine = lines.count
        lines.appendLine(start: Int(range.start), end: Int(range.end), width: width)
        return DiagramMeasuredText(firstLine: Int32(firstLine), lineCount: 1, width: width, height: measurer.singleLineHeight,
                                   lineHeight: measurer.singleLineHeight, fontSize: measurer.fontSize)
    }
}
