/**
 * File: PacketTextBlocks.swift
 * ----------------------------
 * Layer: Layout
 * Description: The one-line text blocks of a packet's boxes and bit numbers, written straight into the thread's text
 *              storage: the same block a list of one line and one width makes, without making the lists.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import CoreGraphics
import Foundation

enum PacketTextBlocks {
    /// A field's label with its entity codes read and without the white space and line breaks at its ends, as Foundation
    /// trims them: on the bytes when they are ASCII, whose white space is a tab, a line feed, a vertical tab, a form feed,
    /// a carriage return or a space.
    static func trimmedLabel(_ label: String) -> String {
        var decoded = DiagramLabelDecoder.decodingEntities(label)
        let range = decoded.withUTF8 { bytes -> Range<Int>? in
            guard !bytes.contains(where: { byte in byte >= 0x80 }) else { return nil }
            var start = 0
            var end = bytes.count
            while start < end, isASCIIWhitespace(bytes[start]) { start += 1 }
            while end > start, isASCIIWhitespace(bytes[end - 1]) { end -= 1 }
            return start..<end
        }
        guard let range else { return decoded.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard range.count != decoded.utf8.count else { return decoded }
        return decoded.withUTF8 { bytes in String(decoding: UnsafeBufferPointer(rebasing: bytes[range]), as: UTF8.self) }
    }

    private static func isASCIIWhitespace(_ byte: UInt8) -> Bool {
        byte == 32 || (9...13).contains(byte)
    }

    /// `text` as one line `width` wide at `fontSize`, its line as high as Pele's lines are (one and a half times the size,
    /// rounded), its center at the origin: `DiagramTextBlock(line:width:fontSize:)`'s block.
    static func oneLine(_ text: String, width: CGFloat, fontSize: CGFloat) -> DiagramTextBlock {
        let byteCount = text.utf8.count
        let storage = DiagramTextThreadState.current.storage(forBytes: byteCount, recordBytes: 0)
        let start = DiagramLabelWriting.append(text, to: storage)
        return DiagramTextBlock(storage: storage, record: DiagramTextRecord(first: start, end: start + Int32(byteCount), lineCount: 1, isOneLine: true,
                                                                            hasEmphasis: false, widestLineWidth: width),
                                fontSize: fontSize, lineHeight: (fontSize * CoreTextDiagramTextMeasurer.lineHeightRatio).rounded())
    }

    /// A bit number at `fontSize`, measured as `measurers` measure it at that size.
    static func number<Measurer: DiagramTextMeasuring>(_ bit: Int, fontSize: CGFloat, measurers: inout DiagramTextMeasurerSizes<Measurer>) -> DiagramTextBlock {
        let text = String(bit)
        return oneLine(text, width: measurers.width(of: text, atFontSize: fontSize), fontSize: fontSize)
    }
}
