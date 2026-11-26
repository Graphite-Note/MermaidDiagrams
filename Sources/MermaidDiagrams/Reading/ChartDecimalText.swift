/**
 * File: ChartDecimalText.swift
 * ----------------------------
 * Layer: Core
 * Description: The value of a short decimal number written in a chart's bytes, worked out on the bytes when it is the
 *              value Swift's Double reading of the same text gives, so that no String is made for it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

/// The value of a decimal number written as an optional `-`, digits, and optionally a `.` and digits, read on its
/// bytes. Its digits make an integer `m` and its fraction has `k` digits; when `m` is below 2^53 and `k` at most 22,
/// `m` and 10^k are exact doubles and their quotient, rounded once as IEEE division rounds, is the correctly rounded
/// value Double's reading of the text gives (Clinger's fast path). Anything else is nil, for the caller to read as text.
enum ChartDecimalText {
    /// The value of `bytes[start..<end]`, or nil when it is not such a number or not on the fast path.
    static func value(of bytes: [UInt8], from start: Int, to end: Int) -> Double? {
        guard start < end, end <= bytes.count else { return nil }
        var index = start
        let isNegative = bytes[index] == MermaidByte.hyphen
        if isNegative { index += 1 }
        var mantissa: UInt64 = 0
        var digitCount = 0
        var fractionDigitCount = 0
        var isInFraction = false
        while index < end {
            let byte = bytes[index]
            if byte == MermaidByte.period, !isInFraction, digitCount > 0 {
                isInFraction = true
            } else if MermaidByte.isDigit(byte) {
                // 19 digits fit in 64 bits; the mantissa must stay below 2^53 anyway.
                guard digitCount < 19 else { return nil }
                mantissa = mantissa * 10 + UInt64(byte - UInt8(ascii: "0"))
                digitCount += 1
                if isInFraction { fractionDigitCount += 1 }
            } else {
                return nil
            }
            index += 1
        }
        guard digitCount > 0, !(isInFraction && fractionDigitCount == 0), mantissa < (1 << 53), fractionDigitCount < powersOfTen.count else { return nil }
        let value = Double(mantissa) / powersOfTen[fractionDigitCount]
        return isNegative ? -value : value
    }

    /// 10^0 to 10^22, each an exact double.
    private static let powersOfTen: [Double] = (0...22).map { exponent in (0..<exponent).reduce(1.0) { power, _ in power * 10 } }
}
