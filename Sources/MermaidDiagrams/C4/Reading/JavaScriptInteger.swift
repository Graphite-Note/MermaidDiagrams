/**
 * File: JavaScriptInteger.swift
 * -----------------------------
 * Layer: Core
 * Description: Reads a whole number from text as JavaScript's parseInt does without a radix, for the values C4
 *              diagrams give to Mermaid's parseInt: label offsets and row counts.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// JavaScript's `parseInt(text)`: white space before it skipped, a sign, `0x` for hexadecimal digits, then the longest
/// run of digits, whatever follows them (`5px` is 5, `1e3` is 1); nil where no digit is read, JavaScript's `NaN`.
enum JavaScriptInteger {
    static func parsed(_ text: String) -> Double? {
        var units = Substring(text).utf16[...]
        while let first = units.first, C4Characters.isSpace(first) { units = units.dropFirst() }
        var sign: Double = 1
        if let first = units.first, first == plus || first == minus {
            if first == minus { sign = -1 }
            units = units.dropFirst()
        }
        var radix: Double = 10
        if units.count >= 2, units.first == zero, let second = units.dropFirst().first, second == lowercaseX || second == uppercaseX {
            radix = 16
            units = units.dropFirst(2)
        }
        var value: Double = 0
        var digitCount = 0
        for unit in units {
            guard let digit = digitValue(unit), digit < radix else { break }
            value = value * radix + digit
            digitCount += 1
        }
        guard digitCount > 0 else { return nil }
        if radix == 10, digitCount > 15, let exact = Double(String(decoding: units.prefix(digitCount), as: UTF16.self)) { value = exact }
        return sign * value
    }

    private static func digitValue(_ unit: UInt16) -> Double? {
        switch unit {
        case 48...57: Double(unit - 48)
        case 65...70: Double(unit - 55)
        case 97...102: Double(unit - 87)
        default: nil
        }
    }

    private static let plus: UInt16 = 43
    private static let minus: UInt16 = 45
    private static let zero: UInt16 = 48
    private static let lowercaseX: UInt16 = 120
    private static let uppercaseX: UInt16 = 88
}
