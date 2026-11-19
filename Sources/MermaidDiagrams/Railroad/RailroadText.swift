/**
 * File: RailroadText.swift
 * ------------------------
 * Layer: Core
 * Description: The text a railroad diagram shows as Pele shows it: literal, Mermaid's entity codes read and invisible
 *              escapes written out, and a repetition's count.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// How a railroad diagram's text is shown.
enum RailroadText {
    /// The text as written: a terminal such as `<br>` or `*` is itself, not markup. Only Mermaid's entity codes stand for
    /// characters (`#35;` for `#`, `#quot;` for `"`; an unknown name is shown as `&name;`, as Mermaid restores it), and a
    /// line break, a carriage return or a tab is written out (`\n`, `\r`, `\t`).
    static func shown(_ text: String) -> String {
        var shown = ""
        var scalars = Substring(text).unicodeScalars[...]
        while let scalar = scalars.first {
            if scalar == "#", let (code, length) = entityCode(at: scalars) {
                shown += decoded(code)
                scalars = scalars.dropFirst(length)
                continue
            }
            switch scalar {
            case "\n": shown += "\\n"
            case "\r": shown += "\\r"
            case "\t": shown += "\\t"
            default: shown.unicodeScalars.append(scalar)
            }
            scalars = scalars.dropFirst()
        }
        return shown
    }

    /// A repetition's count, as Pele writes it: none for “once or more” and “any number of times”, `3×` for exactly
    /// three, `≥2×`, `≤4×`, `2–4×`; an infinite count is `∞`.
    static func count(minimum: Double, maximum: Double) -> String {
        if maximum == .infinity, minimum <= 1 { return "" }
        func text(_ value: Double) -> String { value.isFinite ? JavaScriptNumberText.text(value) : "∞" }
        if minimum == maximum { return text(minimum) + "×" }
        if maximum == .infinity { return "≥" + text(minimum) + "×" }
        return minimum == 0 ? "≤" + text(maximum) + "×" : text(minimum) + "–" + text(maximum) + "×"
    }

    /// The name or number of a `#…;` code at the start of `scalars` (letters, digits and underscores) and its length.
    private static func entityCode(at scalars: Substring.UnicodeScalarView.SubSequence) -> (String, Int)? {
        var code = ""
        for scalar in scalars.dropFirst() {
            if scalar == ";" { return code.isEmpty ? nil : (code, code.unicodeScalars.count + 2) }
            guard scalar.isASCII, FirstMatchTokenPatterns.isWordByte(UInt8(scalar.value)) else { return nil }
            code.unicodeScalars.append(scalar)
        }
        return nil
    }

    /// The character of a code: a number, or a name the package knows; else `&name;`, as Mermaid's placeholders become
    /// before HTML's entities are read.
    private static func decoded(_ code: String) -> String {
        let isNumber = code.allSatisfy(\.isASCIIDigit)
        let entity = (isNumber ? "&#" : "&") + code + ";"
        let decoded = DiagramLabelDecoder.decodingEntities(entity)
        return decoded
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
