/**
 * File: DiagramColorBytes.swift
 * -----------------------------
 * Layer: Core
 * Description: Reads a style's color on its bytes when they are ASCII: a hexadecimal color, `rgb()` and `rgba()`, `none`,
 *              `transparent` and CSS's names, in any case, as `DiagramColor(cssText:)` reads them through characters.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

extension DiagramColor {
    /// The color an ASCII value reads as, as `init?(cssText:)` reads its text: without the spaces and tabs around it
    /// (Foundation's `whitespaces` in ASCII), in lower case (ASCII's), `#` and hexadecimal digits, then `rgb(…)` or
    /// `rgba(…)`, then `none` or `transparent`, then a name. `.some(nil)` for a value that is no color; nil, to be read
    /// through its characters, for a value beyond ASCII.
    static func readOnBytes(_ cssText: String) -> DiagramColor?? {
        var text = cssText
        return text.withUTF8 { bytes -> DiagramColor?? in
            guard !bytes.contains(where: { byte in byte >= 0x80 }) else { return nil }
            var start = 0
            var end = bytes.count
            while start < end, bytes[start] == MermaidByte.space || bytes[start] == MermaidByte.tab { start += 1 }
            while end > start, bytes[end - 1] == MermaidByte.space || bytes[end - 1] == MermaidByte.tab { end -= 1 }
            return .some(read(UnsafeBufferPointer(rebasing: bytes[start..<end])))
        }
    }

    /// The color trimmed ASCII `value` writes, or nil.
    private static func read(_ value: UnsafeBufferPointer<UInt8>) -> DiagramColor? {
        if value.first == UInt8(ascii: "#") { return hexadecimal(value) }
        if spellsPrefix(value, "rgb"), let color = functionalColor(value) { return color }
        if spells(value, "none") || spells(value, "transparent") { return DiagramColor(red: 0, green: 0, blue: 0, alpha: 0) }
        guard value.count <= longestName, let color = cssColorNames[lowercasedText(UnsafeBufferPointer(rebasing: value[...]))] else { return nil }
        return DiagramColor(red: Double(color >> 16 & 0xFF) / 255, green: Double(color >> 8 & 0xFF) / 255, blue: Double(color & 0xFF) / 255)
    }

    /// `rgb(51, 51, 51)`, `rgba(51 51 51 / 50%)` and `rgb(20%, 20%, 20%)`, as `functionalColor` reads their lowered text:
    /// the name before the first `(` `rgb` or `rgba`, a closing `)` last, the arguments between them cut at commas, spaces
    /// and slashes, three channels out of 255 or in percent and an opacity out of 1 or in percent, each clamped.
    private static func functionalColor(_ value: UnsafeBufferPointer<UInt8>) -> DiagramColor? {
        guard let opening = value.firstIndex(of: UInt8(ascii: "(")), value.last == UInt8(ascii: ")"), opening < value.count - 1,
              opening == 3 || (opening == 4 && MermaidByte.lowercased(value[3]) == UInt8(ascii: "a")) else { return nil }
        var parts: [Range<Int>] = []
        var partStart = opening + 1
        for index in (opening + 1)...(value.count - 1) {
            let byte = value[index]
            guard index == value.count - 1 || byte == MermaidByte.comma || byte == MermaidByte.space || byte == UInt8(ascii: "/") else { continue }
            if index > partStart { parts.append(partStart..<index) }
            partStart = index + 1
            if parts.count > 4 { return nil }
        }
        guard parts.count == 3 || parts.count == 4 else { return nil }
        var channels: [Double] = []
        for part in parts.prefix(3) {
            guard let channel = number(UnsafeBufferPointer(rebasing: value[part]), fullScale: 255) else { return nil }
            channels.append(min(1, max(0, channel)))
        }
        let alpha = parts.count == 4 ? number(UnsafeBufferPointer(rebasing: value[parts[3]]), fullScale: 1).map { opacity in min(1, max(0, opacity)) } : 1
        guard let alpha else { return nil }
        return DiagramColor(red: channels[0], green: channels[1], blue: channels[2], alpha: alpha)
    }

    /// A number out of `fullScale`, or a percentage, read by `Double` from the lowered text as `number` reads it.
    private static func number(_ part: UnsafeBufferPointer<UInt8>, fullScale: Double) -> Double? {
        if part.last == UInt8(ascii: "%") {
            return Double(lowercasedText(UnsafeBufferPointer(rebasing: part[..<(part.count - 1)]))).map { percentage in percentage / 100 }
        }
        return Double(lowercasedText(part)).map { number in number / fullScale }
    }

    private static func lowercasedText(_ bytes: UnsafeBufferPointer<UInt8>) -> String {
        String(unsafeUninitializedCapacity: bytes.count) { buffer in
            for index in 0..<bytes.count { buffer[index] = MermaidByte.lowercased(bytes[index]) }
            return bytes.count
        }
    }

    /// Whether the value, lowered, is `word`.
    private static func spells(_ value: UnsafeBufferPointer<UInt8>, _ word: StaticString) -> Bool {
        value.count == word.utf8CodeUnitCount && spellsPrefix(value, word)
    }

    /// Whether the value, lowered, starts with `word`.
    private static func spellsPrefix(_ value: UnsafeBufferPointer<UInt8>, _ word: StaticString) -> Bool {
        guard value.count >= word.utf8CodeUnitCount else { return false }
        let letters = word.utf8Start
        for offset in 0..<word.utf8CodeUnitCount where MermaidByte.lowercased(value[offset]) != letters[offset] { return false }
        return true
    }

    /// The longest of CSS's color names, `lightgoldenrodyellow`.
    private static let longestName = 20
}
