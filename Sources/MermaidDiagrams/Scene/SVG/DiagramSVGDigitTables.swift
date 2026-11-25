/**
 * File: DiagramSVGDigitTables.swift
 * ---------------------------------
 * Layer: Core
 * Description: The characters of every whole part below 10,000 and of every two decimals, made once for the process,
 *              which the SVG writer's numbers are read from instead of worked out digit by digit.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

/// The characters the number writer reads (`DiagramSVGNumberWriting.writeNumber`): for each whole part below 10,000,
/// its digits without leading zeros as the low bytes of a 32-bit word, the first digit lowest (`7` is `0x37`, `1250` is
/// `0x30_35_32_31`); for each fraction of two decimals, the point and both decimals as its three low bytes and in its
/// high byte how many of them are written: none for `.00`, the point and one for a second decimal of 0 (`.5`), all
/// three otherwise (`.25`). The tables take 40,400 bytes, made the first time a number is written and kept, never
/// changed, so that any thread reads them.
struct DiagramSVGDigitTables: @unchecked Sendable {
    let wholeParts: UnsafePointer<UInt32>
    let fractions: UnsafePointer<UInt32>

    /// How many whole parts the table holds: the writer's numbers below 9,999 in size, rounded to hundredths.
    static let wholePartCount = 10_000
    /// Where a fraction's word keeps how many of its characters are written.
    static let fractionLengthShift: UInt64 = 24

    /// The process's tables.
    static let shared = DiagramSVGDigitTables()

    private init() {
        let wholeParts = UnsafeMutablePointer<UInt32>.allocate(capacity: Self.wholePartCount)
        for whole in 0..<Self.wholePartCount { wholeParts[whole] = Self.characters(ofWholePart: UInt32(whole)) }
        let fractions = UnsafeMutablePointer<UInt32>.allocate(capacity: 100)
        for fraction in 0..<100 { fractions[fraction] = Self.characters(ofFraction: UInt32(fraction)) }
        self.wholeParts = UnsafePointer(wholeParts)
        self.fractions = UnsafePointer(fractions)
    }

    /// `whole`'s digits, the first lowest; `0` for zero.
    static func characters(ofWholePart whole: UInt32) -> UInt32 {
        var remaining = whole
        var digits: [UInt32] = []
        repeat {
            digits.append(UInt32(UInt8(ascii: "0")) + remaining % 10)
            remaining /= 10
        } while remaining > 0
        var word: UInt32 = 0
        for (position, digit) in digits.reversed().enumerated() { word |= digit << UInt32(8 * position) }
        return word
    }

    /// `.` and the two decimals of `fraction` hundredths, with how many of the three are written in the high byte.
    static func characters(ofFraction fraction: UInt32) -> UInt32 {
        let tens = fraction / 10, ones = fraction % 10
        let writtenCount: UInt32 = fraction == 0 ? 0 : (ones == 0 ? 2 : 3)
        return UInt32(UInt8(ascii: ".")) | (UInt32(UInt8(ascii: "0")) + tens) << 8 | (UInt32(UInt8(ascii: "0")) + ones) << 16
            | writtenCount << UInt32(fractionLengthShift)
    }
}
