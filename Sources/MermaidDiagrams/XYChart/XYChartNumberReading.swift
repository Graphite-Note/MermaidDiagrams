/**
 * File: XYChartNumberReading.swift
 * --------------------------------
 * Layer: Core
 * Description: An XY chart's number token read on its bytes: a sign, digits and a fraction whose digits a double holds
 *              exactly divided once by an exact power of ten, which rounds as reading the text does; any other through
 *              the text.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

enum XYChartNumberReading {
    /// The number the lexer's token from `start` to `end` writes (`[+-]?digits(.digits)?` or `[+-]?.digits`), as
    /// `Double(String)` reads it. When the digits, without the point, make a whole number of at most 2⁵³ and the
    /// fraction has at most 22 digits, that number and the power of ten are both exact doubles, and their quotient is
    /// the correctly rounded value the text's reading gives (Clinger's fast path); otherwise the text is read.
    static func number(in bytes: [UInt8], from start: Int, to end: Int) -> Double? {
        precondition(start >= 0 && start <= end && end <= bytes.count, "A token lies within its text")
        var index = start
        var isNegative = false
        if index < end, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") {
            isNegative = bytes[index] == UInt8(ascii: "-")
            index += 1
        }
        var mantissa: UInt64 = 0
        var fractionDigitCount = 0
        var digitCount = 0
        var isFraction = false
        while index < end {
            let byte = bytes[index]
            if byte == UInt8(ascii: "."), !isFraction {
                isFraction = true
            } else if byte >= UInt8(ascii: "0"), byte <= UInt8(ascii: "9") {
                guard mantissa <= (largestExactWhole - 9) / 10 else { return readText(bytes, start, end) }
                mantissa = mantissa * 10 + UInt64(byte - UInt8(ascii: "0"))
                digitCount += 1
                if isFraction { fractionDigitCount += 1 }
            } else {
                return readText(bytes, start, end)
            }
            index += 1
        }
        guard digitCount > 0, fractionDigitCount < exactPowersOfTen.count else { return readText(bytes, start, end) }
        let magnitude = Double(mantissa) / exactPowersOfTen[fractionDigitCount]
        return isNegative ? -magnitude : magnitude
    }

    /// 2⁵³: every whole number up to it is a double.
    private static let largestExactWhole: UInt64 = 1 << 53

    /// 10⁰ to 10²², each a double exactly.
    private static let exactPowersOfTen: [Double] = [1e0, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9, 1e10, 1e11, 1e12, 1e13, 1e14, 1e15, 1e16, 1e17,
                                                     1e18, 1e19, 1e20, 1e21, 1e22]

    private static func readText(_ bytes: [UInt8], _ start: Int, _ end: Int) -> Double? {
        Double(String(decoding: bytes[start..<end], as: UTF8.self))
    }
}
