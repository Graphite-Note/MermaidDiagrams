/**
 * File: DiagramLabelEntities.swift
 * --------------------------------
 * Layer: Core
 * Description: Reads entity codes as Pele reads them: Mermaid's #name; and #123; codes turned into HTML's, then HTML's
 *              named, decimal and hexadecimal codes into their characters, a code that names none left as HTML's.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 23/11/2026
 */

/// Pele's entity codes (preprocess.ts `encodeEntities`, text/entities.ts `decodeEntities`). Mermaid hides each `#` and
/// one or more word characters and `;` (`#quot;`, `#9829;`) before parsing and turns it back into HTML's code when the
/// text is drawn: `&quot;` for a name, `&#9829;` for digits. HTML's codes are then read: `&#` and decimal digits, `&#x`
/// and hexadecimal digits, or `&` and a name of Pele's table, each followed by `;`. A number that is no character (zero,
/// past U+10FFFF, a surrogate) and a name the table lacks stay as HTML's code: `#0;` is drawn `&#0;`, `#nothing;` is
/// drawn `&nothing;`.
enum DiagramLabelEntities {
    /// `text` with every code read.
    static func decoded(_ text: String) -> String {
        // Most text has no semicolon byte, so has no `;` character either: looked for in the bytes first.
        guard text.utf8.contains(UInt8(ascii: ";")), text.contains(";"), text.contains("#") || text.contains("&") else { return text }
        return htmlCodesRead(mermaidCodesAsHTML(Array(text.unicodeScalars)))
    }

    /// `text` with HTML's codes read and Mermaid's left as written: text whose Mermaid codes are already HTML's.
    static func htmlDecoded(_ text: String) -> String {
        guard text.utf8.contains(UInt8(ascii: "&")), text.contains("&"), text.contains(";") else { return text }
        return htmlCodesRead(Array(text.unicodeScalars))
    }

    /// Each `#` followed by word characters and `;` as HTML's code: `&#` before digits, `&` before anything else.
    static func mermaidCodesAsHTML(_ scalars: [Unicode.Scalar]) -> [Unicode.Scalar] {
        guard scalars.contains("#") else { return scalars }
        var result: [Unicode.Scalar] = []
        result.reserveCapacity(scalars.count + 4)
        var index = 0
        while index < scalars.count {
            if scalars[index] == "#", let end = endOfWordCharacters(in: scalars, from: index + 1), end > index + 1, end < scalars.count,
               scalars[end] == ";" {
                let isNumber = scalars[(index + 1)..<end].allSatisfy(isDigit)
                result.append("&")
                if isNumber { result.append("#") }
                result.append(contentsOf: scalars[(index + 1)...end])
                index = end + 1
                continue
            }
            result.append(scalars[index])
            index += 1
        }
        return result
    }

    /// HTML's codes read, from left to right, each code ending at its first `;`.
    private static func htmlCodesRead(_ scalars: [Unicode.Scalar]) -> String {
        var result = String.UnicodeScalarView()
        var index = 0
        while index < scalars.count {
            if scalars[index] == "&", let (decoded, end) = code(in: scalars, at: index) {
                result.append(contentsOf: decoded)
                index = end
                continue
            }
            result.append(scalars[index])
            index += 1
        }
        return String(result)
    }

    /// The characters the code at `start` (an `&`) stands for and the position after it, or nil where no code starts:
    /// Pele's `&(?:#(\d+)|#[xX]([0-9a-fA-F]+)|(\w+));`.
    private static func code(in scalars: [Unicode.Scalar], at start: Int) -> (String.UnicodeScalarView, Int)? {
        let body = start + 1
        guard body < scalars.count else { return nil }
        if scalars[body] == "#" {
            if let end = endOfRun(in: scalars, from: body + 1, where: isDigit), end > body + 1, end < scalars.count, scalars[end] == ";" {
                return (character(numbered: scalars[(body + 1)..<end], radix: 10, code: scalars[start...end]), end + 1)
            }
            let digits = body + 2
            guard digits < scalars.count, scalars[body + 1] == "x" || scalars[body + 1] == "X",
                  let end = endOfRun(in: scalars, from: digits, where: isHexadecimalDigit), end > digits, end < scalars.count, scalars[end] == ";"
            else { return nil }
            return (character(numbered: scalars[digits..<end], radix: 16, code: scalars[start...end]), end + 1)
        }
        guard let end = endOfWordCharacters(in: scalars, from: body), end > body, end < scalars.count, scalars[end] == ";" else { return nil }
        let name = UnicodeScalarText.string(scalars[body..<end])
        if let named = DiagramLabelEntityNames.character(named: name) { return (String.UnicodeScalarView([named]), end + 1) }
        return (String.UnicodeScalarView(scalars[start...end]), end + 1)
    }

    /// The character a number stands for, or the code as written when it stands for none (Pele's `codePoint`).
    private static func character(numbered digits: ArraySlice<Unicode.Scalar>, radix: UInt32, code: ArraySlice<Unicode.Scalar>) -> String.UnicodeScalarView {
        var value: UInt32 = 0
        for digit in digits {
            guard let digitValue = hexadecimalValue(of: digit), value <= (0x10FFFF - digitValue) / radix else {
                return String.UnicodeScalarView(code)
            }
            value = value * radix + digitValue
        }
        guard value > 0, let scalar = Unicode.Scalar(value) else { return String.UnicodeScalarView(code) }
        return String.UnicodeScalarView([scalar])
    }

    /// JavaScript's `\w`: ASCII letters, digits and `_`.
    static func isWordCharacter(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "a"..."z", "A"..."Z", "0"..."9", "_": true
        default: false
        }
    }

    private static func isDigit(_ scalar: Unicode.Scalar) -> Bool {
        ("0"..."9").contains(scalar)
    }

    private static func isHexadecimalDigit(_ scalar: Unicode.Scalar) -> Bool {
        hexadecimalValue(of: scalar) != nil
    }

    private static func hexadecimalValue(of scalar: Unicode.Scalar) -> UInt32? {
        switch scalar {
        case "0"..."9": scalar.value - 48
        case "a"..."f": scalar.value - 87
        case "A"..."F": scalar.value - 55
        default: nil
        }
    }

    private static func endOfWordCharacters(in scalars: [Unicode.Scalar], from start: Int) -> Int? {
        endOfRun(in: scalars, from: start, where: isWordCharacter)
    }

    private static func endOfRun(in scalars: [Unicode.Scalar], from start: Int, where belongs: (Unicode.Scalar) -> Bool) -> Int? {
        guard start <= scalars.count else { return nil }
        var end = start
        while end < scalars.count, belongs(scalars[end]) { end += 1 }
        return end
    }
}
