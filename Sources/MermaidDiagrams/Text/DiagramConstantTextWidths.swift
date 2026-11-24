/**
 * File: DiagramConstantTextWidths.swift
 * -------------------------------------
 * Layer: Core
 * Description: The widths of a closed set of texts a type draws again and again (a C4 shape's kind, a use case's
 *              «include», a requirement's stereotype), measured once per face for the whole process instead of each
 *              time they are drawn, most of them past ASCII and so laid out by Core Text.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
import Foundation

/// A closed set of texts, each one line that Pele reads as written: trimmed, unmarked, with no line break. Declared once
/// (a `static let`), it keeps the widths of its texts per registered face, measured the first time a layout asks for
/// them; a layout takes them once (`widths(for:)`) and reads them without a lock.
final class DiagramConstantTexts: @unchecked Sendable {
    /// The texts' UTF-8 bytes, one after the other, and where each ends.
    let bytes: [UInt8]
    let ends: [Int]
    private let lock = NSLock()
    private var widthsByFace: [Int32: [CGFloat]] = [:]

    init(_ texts: [String]) {
        var bytes: [UInt8] = []
        var ends: [Int] = []
        for text in texts {
            let utf8 = Array(text.utf8)
            precondition(!utf8.isEmpty && DiagramLabelLineBreaks.isUnmarked(utf8, isLiteral: false)
                && !DiagramFlatTextMeasuring.isWhitespace(utf8[0]) && !DiagramFlatTextMeasuring.isWhitespace(utf8[utf8.count - 1]),
                         "a constant text is one trimmed line without markup")
            bytes += utf8
            ends.append(bytes.count)
        }
        self.bytes = bytes
        self.ends = ends
    }

    var count: Int { ends.count }

    /// The range of text `index`'s bytes.
    func range(of index: Int) -> Range<Int> {
        (index == 0 ? 0 : ends[index - 1])..<ends[index]
    }

    /// The texts' widths in `measurer`'s font: kept per face for Core Text's measurer in the registry, measured anew for
    /// any other.
    func widths<Measurer: DiagramTextMeasuring>(for measurer: Measurer) -> DiagramConstantTextWidths {
        guard let coreText = measurer as? CoreTextDiagramTextMeasurer, coreText.face.index.isRegistered else {
            return DiagramConstantTextWidths(texts: self, widths: measured { bytes in DiagramTextMeasuringWidths.width(of: bytes, measurer: measurer) })
        }
        let face = coreText.face
        lock.lock()
        let known = widthsByFace[face.index.rawValue]
        lock.unlock()
        if let known { return DiagramConstantTextWidths(texts: self, widths: known) }
        // Measured outside the lock: two threads measuring the same face measure the same widths.
        let widths = measured { bytes in face.width(ofUTF8: bytes) }
        lock.lock()
        widthsByFace[face.index.rawValue] = widths
        lock.unlock()
        return DiagramConstantTextWidths(texts: self, widths: widths)
    }

    private func measured(_ width: (UnsafeBufferPointer<UInt8>) -> CGFloat) -> [CGFloat] {
        bytes.withUnsafeBufferPointer { bytes in
            (0..<count).map { index in width(UnsafeBufferPointer(rebasing: bytes[range(of: index)])) }
        }
    }
}

/// The widths of a set of constant texts in one font, which a layout takes once and reads as it lays out.
struct DiagramConstantTextWidths: Sendable {
    let texts: DiagramConstantTexts
    let widths: [CGFloat]

    /// The width of text `index` on one line.
    func width(of index: Int) -> CGFloat {
        precondition(index >= 0 && index < widths.count, "constant text index out of range")
        return widths[index]
    }

    /// Text `index` measured as `DiagramFlatTextMeasuring.measure` measures it, its line copied into the derived bytes:
    /// its kept width when it fits `maximumWidth` or holds no space to wrap at, else measured and wrapped.
    func measure<Measurer>(_ index: Int, measurer: DiagramFlatMeasurer<Measurer>, maximumWidth: CGFloat, into lines: inout DiagramMeasuredLines)
        -> DiagramMeasuredText {
        let width = width(of: index)
        let range = texts.range(of: index)
        return texts.bytes.withUnsafeBufferPointer { bytes in
            let text = UnsafeBufferPointer(rebasing: bytes[range])
            guard !(width > maximumWidth) || !text.contains(UInt8(ascii: " ")) else {
                let measured = DiagramFlatTextMeasuring.measuredOnFullPath(bytes, MermaidTextRange(start: range.lowerBound, end: range.upperBound),
                                                                            form: .plain, measurer: measurer, maximumWidth: maximumWidth, into: &lines)
                return measured
            }
            let firstLine = lines.count
            lines.appendDerivedLine(text, width: width, runs: [])
            return DiagramMeasuredText(firstLine: Int32(firstLine), lineCount: 1, width: width, height: measurer.singleLineHeight,
                                       lineHeight: measurer.singleLineHeight, fontSize: measurer.fontSize)
        }
    }
}
