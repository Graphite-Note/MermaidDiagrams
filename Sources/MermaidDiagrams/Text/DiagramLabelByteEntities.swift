/**
 * File: DiagramLabelByteEntities.swift
 * ------------------------------------
 * Layer: Core
 * Description: A label line's text between its markup written into its spans as Pele writes it: icon names left out
 *              with the space after them, Mermaid's and HTML's entity codes read, each piece joined to the span before
 *              when it has the same emphasis; on bytes.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

extension DiagramLabelByteDecoder {
    /// Pele's `pushIcons` then `pushPlain` for the text pending, in `style`. Pele draws `fa:fa-name` (and `fab:`, `fak:`,
    /// `fal:`, `far:`, `fas:`) as an icon only when the host gives it one by that name (text/icons.ts `iconMarkup`); with
    /// none an icon takes no room: its name is left out with the space after it, or, at the end of the text, with the
    /// spaces before it (text/label.ts `pushIcons`). The package has no icons to draw, so every name is left out so.
    mutating func flush(style: DiagramTextStyle, firstSpan: Int) {
        guard !pending.isEmpty else { return }
        // The pending text is taken out while it is read, and its room given back after, so that neither is copied.
        var text: [UInt8] = []
        swap(&text, &pending)
        text.withUnsafeBufferPointer { text in
            var kept = 0
            var searchStart = 0
            while let name = Self.nextIconName(text, from: searchStart) {
                appendText(text, kept..<name.lowerBound, style: style, firstSpan: firstSpan)
                kept = name.upperBound
                searchStart = name.upperBound
                if kept < text.count, text[kept] == UInt8(ascii: " ") {
                    kept += 1
                } else if kept == text.count, spans.count > firstSpan {
                    trimLastSpanEnd()
                }
            }
            appendText(text, kept..<text.count, style: style, firstSpan: firstSpan)
        }
        text.removeAll(keepingCapacity: true)
        swap(&text, &pending)
    }

    /// The line's last span without the white space at its end, which is the output's end.
    private mutating func trimLastSpanEnd() {
        let lastIndex = spans.count - 1
        let spanStart = Int(spans[lastIndex].start)
        var trimmedEnd = Int(spans[lastIndex].end)
        while trimmedEnd > spanStart, case let length = output.withUnsafeBufferPointer({ bytes in JavaScriptWhitespace.lengthOfLast(in: bytes[spanStart..<trimmedEnd]) }),
              length > 0 {
            trimmedEnd -= length
        }
        spans[lastIndex].end = Int32(trimmedEnd)
        output.removeSubrange(trimmedEnd...)
    }

    /// The length of `fa:fa-` (or `fab:fa-` and the others) at `index`, or nil.
    private static func iconPrefixLength(_ text: UnsafeBufferPointer<UInt8>, at index: Int) -> Int? {
        guard index + 1 < text.count, text[index] == UInt8(ascii: "f"), text[index + 1] == UInt8(ascii: "a") else { return nil }
        var colon = index + 2
        if colon < text.count, "bklrs".utf8.contains(text[colon]) { colon += 1 }
        guard colon + 3 < text.count, text[colon] == UInt8(ascii: ":"), text[colon + 1] == UInt8(ascii: "f"), text[colon + 2] == UInt8(ascii: "a"),
              text[colon + 3] == UInt8(ascii: "-") else { return nil }
        return colon + 4 - index
    }

    /// The first icon name at or after `start`: Pele's `(fa[bklrs]?):fa-([\w-]+)`.
    private static func nextIconName(_ text: UnsafeBufferPointer<UInt8>, from start: Int) -> Range<Int>? {
        var index = start
        while index < text.count {
            if let prefix = iconPrefixLength(text, at: index) {
                var end = index + prefix
                while end < text.count, isWordByte(text[end]) || text[end] == UInt8(ascii: "-") { end += 1 }
                if end > index + prefix { return index..<end }
            }
            index += 1
        }
        return nil
    }

    /// `text[range]` with its codes read, joined to the line's last span when that has the same emphasis.
    private mutating func appendText(_ text: UnsafeBufferPointer<UInt8>, _ range: Range<Int>, style: DiagramTextStyle, firstSpan: Int) {
        guard !range.isEmpty else { return }
        let spanStart = Int32(output.count)
        appendDecodingEntities(UnsafeBufferPointer(rebasing: text[range]))
        if spans.count > firstSpan, spans[spans.count - 1].style == style {
            spans[spans.count - 1].end = Int32(output.count)
        } else {
            spans.append(DiagramLabelSpanRecord(start: spanStart, end: Int32(output.count), style: style))
        }
    }

    /// Pele's entity codes (preprocess.ts `encodeEntities`, text/entities.ts `decodeEntities`): each `#` and word
    /// characters and `;` written as HTML's code (`&#` before digits, `&` before anything else), then HTML's codes read
    /// from left to right, each ending at its first `;`.
    private mutating func appendDecodingEntities(_ text: UnsafeBufferPointer<UInt8>) {
        guard text.contains(UInt8(ascii: ";")), text.contains(where: { byte in byte == UInt8(ascii: "#") || byte == UInt8(ascii: "&") }) else {
            return output.append(contentsOf: text)
        }
        codes.removeAll(keepingCapacity: true)
        var index = 0
        while index < text.count {
            if text[index] == UInt8(ascii: "#") {
                var wordEnd = index + 1
                var isNumber = true
                while wordEnd < text.count, Self.isWordByte(text[wordEnd]) {
                    if text[wordEnd] < UInt8(ascii: "0") || text[wordEnd] > UInt8(ascii: "9") { isNumber = false }
                    wordEnd += 1
                }
                if wordEnd > index + 1, wordEnd < text.count, text[wordEnd] == UInt8(ascii: ";") {
                    codes.append(UInt8(ascii: "&"))
                    if isNumber { codes.append(UInt8(ascii: "#")) }
                    codes.append(contentsOf: text[(index + 1)...wordEnd])
                    index = wordEnd + 1
                    continue
                }
            }
            codes.append(text[index])
            index += 1
        }
        let written = codes
        written.withUnsafeBufferPointer { codes in
            var index = 0
            while index < codes.count {
                if codes[index] == UInt8(ascii: "&"), let end = appendCode(codes, at: index) {
                    index = end
                    continue
                }
                output.append(codes[index])
                index += 1
            }
        }
    }

    /// The code at `start` (an `&`) read into the output, and the position after it; nil where no code starts: Pele's
    /// `&(?:#(\d+)|#[xX]([0-9a-fA-F]+)|(\w+));`. A name Pele's table lacks stays as written.
    private mutating func appendCode(_ codes: UnsafeBufferPointer<UInt8>, at start: Int) -> Int? {
        let body = start + 1
        guard body < codes.count else { return nil }
        func endOfRun(from position: Int, while belongs: (UInt8) -> Bool) -> Int {
            var end = position
            while end < codes.count, belongs(codes[end]) { end += 1 }
            return end
        }
        if codes[body] == UInt8(ascii: "#") {
            let end = endOfRun(from: body + 1) { byte in byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9") }
            if end > body + 1, end < codes.count, codes[end] == UInt8(ascii: ";") {
                appendCharacter(numbered: codes, (body + 1)..<end, radix: 10, code: start...end)
                return end + 1
            }
            let digits = body + 2
            guard digits < codes.count, codes[body + 1] == UInt8(ascii: "x") || codes[body + 1] == UInt8(ascii: "X") else { return nil }
            let hexadecimalEnd = endOfRun(from: digits) { byte in Self.hexadecimalValue(byte) != nil }
            guard hexadecimalEnd > digits, hexadecimalEnd < codes.count, codes[hexadecimalEnd] == UInt8(ascii: ";") else { return nil }
            appendCharacter(numbered: codes, digits..<hexadecimalEnd, radix: 16, code: start...hexadecimalEnd)
            return hexadecimalEnd + 1
        }
        let end = endOfRun(from: body, while: Self.isWordByte)
        guard end > body, end < codes.count, codes[end] == UInt8(ascii: ";") else { return nil }
        if let named = DiagramLabelEntityNames.character(named: String(decoding: UnsafeBufferPointer(rebasing: codes[body..<end]), as: UTF8.self)) {
            UTF8.encode(named) { byte in output.append(byte) }
        } else {
            output.append(contentsOf: codes[start...end])
        }
        return end + 1
    }

    /// The character a number stands for, or the code as written when it stands for none (zero, past U+10FFFF, a
    /// surrogate: Pele's `codePoint`).
    private mutating func appendCharacter(numbered codes: UnsafeBufferPointer<UInt8>, _ digits: Range<Int>, radix: UInt32, code: ClosedRange<Int>) {
        var value: UInt32 = 0
        for index in digits {
            guard let digit = Self.hexadecimalValue(codes[index]), value <= (0x10FFFF - digit) / radix else {
                return output.append(contentsOf: codes[code])
            }
            value = value * radix + digit
        }
        guard value > 0, let scalar = Unicode.Scalar(value) else { return output.append(contentsOf: codes[code]) }
        UTF8.encode(scalar) { byte in output.append(byte) }
    }

    private static func hexadecimalValue(_ byte: UInt8) -> UInt32? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): UInt32(byte) - 48
        case UInt8(ascii: "a")...UInt8(ascii: "f"): UInt32(byte) - 87
        case UInt8(ascii: "A")...UInt8(ascii: "F"): UInt32(byte) - 55
        default: nil
        }
    }
}
