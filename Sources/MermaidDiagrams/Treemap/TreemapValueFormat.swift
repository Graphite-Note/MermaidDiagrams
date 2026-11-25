/**
 * File: TreemapValueFormat.swift
 * ------------------------------
 * Layer: Core
 * Description: Writes a treemap's values by a d3-format specifier, the part of it Mermaid's treemap uses.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 24/11/2026
 */

import Foundation

/// A value format of a treemap's `valueFormat`: the part of d3-format's specifier treemap values use. It reads an optional sign
/// (`+`), an optional `$`, `,` for thousands separators, a precision (`.2`), `~` to drop trailing zeros and a type: `f` (fixed
/// decimals), `%` (a percentage), `d` (a whole number), `e` (an exponent), or none (at most 12 significant digits). A fill,
/// an alignment and a width are read and ignored. A specifier it does not read is `,`; `$0,0`, as Mermaid's documentation
/// writes a dollar amount, is `$,`.
struct TreemapValueFormat: Equatable, Sendable {
    private let signsPositive: Bool
    private let prefix: String
    private let groupsThousands: Bool
    private let precision: Int?
    private let dropsTrailingZeros: Bool
    private let type: Character?

    /// The longest precision a format may ask for.
    private static let largestPrecision = 20
    /// The pattern of a specifier: fill and alignment, sign, `$`, a zero and a width, `,`, precision, `~`, type.
    private static let pattern = try? NSRegularExpression(pattern: #"^(?:.?[<>=^])?([-+( ])?(\$)?0?[0-9]*(,)?(?:\.([0-9]+))?(~)?([a-zA-Z%])?$"#)

    init(specifier: String) {
        let text = specifier == "$0,0" ? "$," : specifier
        let groups = Self.groups(of: text) ?? Self.groups(of: ",") ?? Array(repeating: nil, count: 6)
        signsPositive = groups[0] == "+"
        prefix = groups[1] ?? ""
        groupsThousands = groups[2] != nil
        precision = groups[3].map(Self.precision(of:))
        dropsTrailingZeros = groups[4] != nil
        type = groups[5]?.first
    }

    /// The precision the digits after the `.` ask for, as JavaScript's `Number` reads them (leading zeros aside: `007` is 7),
    /// at most `largestPrecision`.
    private static func precision(of digits: String) -> Int {
        let significant = digits.drop { digit in digit == "0" }
        guard significant.count <= 2 else { return largestPrecision }
        return min(Int(significant) ?? 0, largestPrecision)
    }

    /// The pattern's groups of `text`: sign, `$`, `,`, precision digits, `~` and type; nil when the text does not match.
    private static func groups(of text: String) -> [String?]? {
        guard let pattern else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = pattern.firstMatch(in: text, range: range) else { return nil }
        return (1...6).map { index in
            Range(match.range(at: index), in: text).map { range in String(text[range]) }
        }
    }

    /// `value` written by the format.
    func text(_ value: Double) -> String {
        let magnitude = value.magnitude
        var suffix = ""
        var body: String
        switch type {
        case "f": body = TreemapNumberText.fixed(magnitude, digits: precision ?? 6)
        case "%":
            body = TreemapNumberText.fixed(magnitude * 100, digits: precision ?? 6)
            suffix = "%"
        case "d": body = TreemapNumberText.fixed((magnitude + 0.5).rounded(.down), digits: 0)
        case "e": body = TreemapNumberText.exponential(magnitude, digits: precision ?? 6)
        default: body = TreemapNumberText.shortest(TreemapNumberText.significant(magnitude, digits: max(1, precision ?? 12)))
        }
        // A number's text is ASCII (digits, a point, `e`, a sign, `Infinity`, `NaN`): its characters are looked for in its bytes.
        let hasExponent = body.utf8.contains(UInt8(ascii: "e"))
        if dropsTrailingZeros, body.utf8.contains(UInt8(ascii: ".")), !hasExponent { body = Self.withoutTrailingZeros(body) }
        if groupsThousands, !hasExponent { body = Self.grouped(body) }
        return (value < 0 ? "-" : (signsPositive ? "+" : "")) + prefix + body + suffix
    }

    /// `1,234,567.5` from `1234567.5`: commas between the groups of three digits of the whole part. `Infinity` and `NaN` are
    /// left whole, where Pele would write them with commas.
    private static func grouped(_ body: String) -> String {
        let wholeCount = body.utf8.prefix { byte in byte != UInt8(ascii: ".") }.count
        guard wholeCount > 3, body.utf8.prefix(wholeCount).allSatisfy({ byte in byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9") }) else { return body }
        let whole = body.prefix { character in character != "." }
        var grouped = ""
        for (index, digit) in whole.enumerated() {
            if index > 0, (whole.count - index) % 3 == 0 { grouped.append(",") }
            grouped.append(digit)
        }
        return grouped + body.dropFirst(whole.count)
    }

    /// The text without a trailing run of zeros and the point before it (`1.500` is `1.5`, `2.00` is `2`).
    private static func withoutTrailingZeros(_ body: String) -> String {
        var trimmed = Substring(body)
        while trimmed.last == "0" { trimmed = trimmed.dropLast() }
        if trimmed.last == "." { trimmed = trimmed.dropLast() }
        return String(trimmed)
    }
}
