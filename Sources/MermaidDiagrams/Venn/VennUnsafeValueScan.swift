/**
 * File: VennUnsafeValueScan.swift
 * -------------------------------
 * Layer: Core
 * Description: Finds in an ASCII style value what Pele's unsafe pattern finds, without a regular expression: url( and
 *              expression( with blanks before the bracket, javascript:, @import, image-set, a comment and <>{};\.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

/// `url\s*\(|expression\s*\(|javascript:|[<>{};\\]|@import|image-set|/\*`, case-insensitive, on ASCII text: compiling and
/// running the pattern through Foundation's regular expressions cost more than reading a C4 diagram's or a Venn
/// diagram's styles. In ASCII the pattern's `\s` is a space, a tab, a line feed, a form feed or a carriage return (a
/// vertical tab makes a value unsafe anyway), and its case-insensitive letters are the ASCII letters; text beyond ASCII is
/// left to the pattern, whose case folding there is the regular expression engine's.
enum VennUnsafeValueScan {
    /// Whether the pattern matches somewhere in `value`; nil when `value` is not ASCII.
    static func matchesUnsafePattern(_ value: String) -> Bool? {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(value.utf8.count)
        for byte in value.utf8 {
            guard byte < 0x80 else { return nil }
            bytes.append(lowercased(byte))
        }
        for start in bytes.indices {
            switch bytes[start] {
            case UInt8(ascii: "<"), UInt8(ascii: ">"), UInt8(ascii: "{"), UInt8(ascii: "}"), UInt8(ascii: ";"), UInt8(ascii: "\\"): return true
            case UInt8(ascii: "/") where start + 1 < bytes.count && bytes[start + 1] == UInt8(ascii: "*"): return true
            default: break
            }
            if hasWord(url, in: bytes, at: start) || hasWord(expression, in: bytes, at: start) {
                let wordEnd = start + (bytes[start] == UInt8(ascii: "u") ? url.count : expression.count)
                var bracket = wordEnd
                while bracket < bytes.count, isBlank(bytes[bracket]) { bracket += 1 }
                if bracket < bytes.count, bytes[bracket] == UInt8(ascii: "(") { return true }
            }
            if hasWord(javascript, in: bytes, at: start) || hasWord(atImport, in: bytes, at: start) || hasWord(imageSet, in: bytes, at: start) {
                return true
            }
        }
        return false
    }

    private static func hasWord(_ word: [UInt8], in bytes: [UInt8], at start: Int) -> Bool {
        start + word.count <= bytes.count && bytes[start] == word[0] && bytes[start..<(start + word.count)].elementsEqual(word)
    }

    private static func lowercased(_ byte: UInt8) -> UInt8 {
        byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z") ? byte + 32 : byte
    }

    /// The pattern's `\s` in ASCII, but the vertical tab: a space, a tab, a line feed, a form feed or a carriage return.
    private static func isBlank(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0C || byte == 0x0D
    }

    private static let url = Array("url".utf8)
    private static let expression = Array("expression".utf8)
    private static let javascript = Array("javascript:".utf8)
    private static let atImport = Array("@import".utf8)
    private static let imageSet = Array("image-set".utf8)
}
