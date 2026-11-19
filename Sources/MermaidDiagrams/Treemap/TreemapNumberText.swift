/**
 * File: TreemapNumberText.swift
 * -----------------------------
 * Layer: Core
 * Description: Writes numbers as JavaScript's toFixed, toExponential and toPrecision do, which round the exact value of a
 *              double half up.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import Foundation

/// Writes a non-negative number as JavaScript's `toFixed`, `toExponential` and `toPrecision` do: the exact decimal value of
/// the double is rounded, and a value exactly halfway goes up (`(2.5).toFixed(0)` is `3`, where C's `%.0f` gives `2`).
enum TreemapNumberText {
    /// The exact digits of a positive double in scientific form, `digits[0].digits[1]… × 10^exponent`, 101 of them.
    private struct ExactDecimal {
        var digits: [UInt8]
        var exponent: Int

        init(_ magnitude: Double) {
            let written = String(format: "%.100e", magnitude)
            let parts = written.split(separator: "e")
            digits = parts[0].utf8.filter { byte in byte != UInt8(ascii: ".") }.map { byte in byte - UInt8(ascii: "0") }
            exponent = Int(parts[1]) ?? 0
        }

        /// The first `count` digits, the last one raised when the digit after it is 5 or more; the exponent moves up one when
        /// that carries into a new first digit. Zero digits left (`count` is 0 or less) is a one at the place before the first
        /// digit when that digit is 5 or more, else nothing: an empty list.
        func rounded(toDigits count: Int) -> ExactDecimal {
            var result = self
            guard count < digits.count else { return result }
            guard count > 0 else {
                result.digits = count == 0 && digits[0] >= 5 ? [1] : []
                result.exponent = exponent + 1
                return result
            }
            result.digits = Array(digits[..<count])
            guard digits[count] >= 5 else { return result }
            var place = count - 1
            while place >= 0, result.digits[place] == 9 {
                result.digits[place] = 0
                place -= 1
            }
            if place >= 0 {
                result.digits[place] += 1
            } else {
                result.digits.insert(1, at: 0)
                result.digits.removeLast()
                result.exponent += 1
            }
            return result
        }

        /// The digit at the decimal place `place` after the point (1 is the first), 0 where the digits stop or have not begun.
        func digit(atPlace place: Int) -> UInt8 {
            let index = exponent + place
            return digits.indices.contains(index) ? digits[index] : 0
        }
    }

    /// JavaScript's `toFixed(digits)` of `magnitude`, at least zero.
    static func fixed(_ magnitude: Double, digits fractionDigits: Int) -> String {
        guard magnitude.isFinite else { return magnitude.isNaN ? "NaN" : "Infinity" }
        guard magnitude < 1e21 else { return JavaScriptNumberText.text(magnitude) }
        var whole = "0"
        var fraction = Array(repeating: UInt8(0), count: fractionDigits)
        if magnitude > 0 {
            let decimal = ExactDecimal(magnitude)
            let rounded = decimal.rounded(toDigits: decimal.exponent + 1 + fractionDigits)
            if !rounded.digits.isEmpty {
                let wholeDigitCount = max(0, rounded.exponent + 1)
                whole = wholeDigitCount == 0 ? "0" : String(decoding: (0..<wholeDigitCount).map { index in
                    UInt8(ascii: "0") + (rounded.digits.indices.contains(index) ? rounded.digits[index] : 0)
                }, as: UTF8.self)
                for place in 0..<fractionDigits { fraction[place] = rounded.digit(atPlace: place + 1) }
            }
        }
        guard fractionDigits > 0 else { return whole }
        return whole + "." + String(decoding: fraction.map { digit in UInt8(ascii: "0") + digit }, as: UTF8.self)
    }

    /// JavaScript's `toExponential(digits)` of `magnitude`, at least zero: `1.5e+3`.
    static func exponential(_ magnitude: Double, digits fractionDigits: Int) -> String {
        guard magnitude.isFinite else { return magnitude.isNaN ? "NaN" : "Infinity" }
        guard magnitude > 0 else { return "0" + (fractionDigits > 0 ? "." + String(repeating: "0", count: fractionDigits) : "") + "e+0" }
        let rounded = ExactDecimal(magnitude).rounded(toDigits: fractionDigits + 1)
        let digits = String(decoding: rounded.digits.map { digit in UInt8(ascii: "0") + digit }, as: UTF8.self)
        let mantissa = fractionDigits > 0 ? digits.prefix(1) + "." + digits.dropFirst() : Substring(digits)
        return mantissa + "e" + (rounded.exponent >= 0 ? "+" : "-") + String(rounded.exponent.magnitude)
    }

    /// `magnitude` rounded to `digits` significant digits, as `Number(magnitude.toPrecision(digits))` reads it back.
    static func significant(_ magnitude: Double, digits count: Int) -> Double {
        guard magnitude.isFinite, magnitude > 0 else { return magnitude }
        let rounded = ExactDecimal(magnitude).rounded(toDigits: count)
        let digits = String(decoding: rounded.digits.map { digit in UInt8(ascii: "0") + digit }, as: UTF8.self)
        return Double(digits.prefix(1) + "." + digits.dropFirst() + "e" + String(rounded.exponent)) ?? magnitude
    }

    /// `String(number)` in JavaScript.
    static func shortest(_ number: Double) -> String {
        JavaScriptNumberText.text(number)
    }
}
