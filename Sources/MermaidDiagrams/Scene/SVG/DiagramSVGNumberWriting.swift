/**
 * File: DiagramSVGNumberWriting.swift
 * -----------------------------------
 * Layer: Core
 * Description: Writes numbers to two decimals and path elements as bytes at a destination with room for them, by exactly
 *              the rule of 0.6.1: a number under 10,000 in size with no branch on its digits, its whole part and its
 *              decimals read from tables made once, larger ones digit by digit.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

import CoreGraphics

/// Writes numbers and path elements at a destination that has room for them. A number is written to two decimals
/// without trailing zeros (`12`, `12.5`, `-0.25`): its hundredths are `Int((value * 100).rounded())`, ties away from
/// zero; a value that is not finite or is 1e12 or more in size is written `0`, as 0.6.1 wrote it.
enum DiagramSVGNumberWriting {
    /// The most bytes `writeNumber` takes at its destination: a sign, twelve digits, a point and two decimals; the
    /// writer of small numbers stores one whole 64-bit word, at most nine bytes from the destination.
    static let largestNumberByteCount = 16

    /// The most bytes one path element takes: its letter, three points of two numbers and the spaces between them.
    static let largestPathElementByteCount = 1 + 6 * largestNumberByteCount + 5

    /// Writes `value` at `destination`, which has room for `largestNumberByteCount` bytes, and returns how many bytes
    /// the number is, its digits read from the thread-safe tables made once (`DiagramSVGDigitTables.shared`).
    @inline(__always)
    static func writeNumber(_ value: CGFloat, to destination: UnsafeMutablePointer<UInt8>) -> Int {
        writeNumber(value, to: destination, digits: DiagramSVGDigitTables.shared)
    }

    /// Writes `value` as `writeNumber(_:to:)` does, with `digits`, which a writer of many numbers reads once. A number
    /// under 9,999 in size (nearly every coordinate) is written without a branch on its digits and without a check the
    /// compiler would add: its hundredths are made an integer by the exact sum with 1.5 × 2⁵² (the hundredths, rounded,
    /// are far below 2⁵¹), split into the whole part and the fraction by a multiplication that divides by 100 exactly
    /// below 2³², and each part's characters are read from a table: the whole part's digits without leading zeros, and
    /// the fraction's point and two decimals with how many of them are written (none for `.00`, two for `.50`). The
    /// whole part's length is the count of its word's characters; both words are joined into one 64-bit word and stored
    /// whole, and the bytes stored past the number are left for what follows to overwrite.
    @inline(__always)
    static func writeNumber(_ value: CGFloat, to destination: UnsafeMutablePointer<UInt8>, digits: DiagramSVGDigitTables) -> Int {
        guard abs(value) < 9_999 else { return writeNumberByDigits(value, to: destination) }
        let scaled = (value * 100).rounded()
        let hundredths = Int64(truncatingIfNeeded: Int(bitPattern: (scaled + exactIntegerShift).bitPattern)) &- exactIntegerShiftBits
        let signMask = hundredths >> 63
        let magnitude = UInt64(bitPattern: (hundredths ^ signMask) &- signMask)
        let whole = (magnitude &* 0x51EB_851F) >> 37
        let fraction = magnitude &- whole &* 100
        let wholeWord = UInt64(digits.wholeParts[Int(truncatingIfNeeded: whole)])
        let fractionWord = UInt64(digits.fractions[Int(truncatingIfNeeded: fraction)])
        // Eight times the whole part's length: its word's characters are its low bytes, each of them nonzero.
        let wholeBitCount = (39 &- UInt64(truncatingIfNeeded: wholeWord.leadingZeroBitCount &- 32)) & ~7
        let sign = Int(truncatingIfNeeded: UInt64(bitPattern: signMask) >> 63)
        destination[0] = UInt8(ascii: "-")
        UnsafeMutableRawPointer(destination + sign).storeBytes(of: (wholeWord | fractionWord << wholeBitCount).littleEndian, as: UInt64.self)
        return sign &+ Int(truncatingIfNeeded: wholeBitCount >> 3) &+ Int(truncatingIfNeeded: fractionWord >> DiagramSVGDigitTables.fractionLengthShift)
    }

    /// 1.5 × 2⁵²: added to an integer of less than 2⁵¹ in size, it leaves the integer in the low bits of the sum's
    /// significand, exactly, which `exactIntegerShiftBits` then takes away.
    private static let exactIntegerShift: CGFloat = 0x1.8p52
    private static let exactIntegerShiftBits: Int64 = 0x4338_0000_0000_0000

    /// The general rule, for numbers of 9,999 or more in size and those that are not finite.
    @inline(never)
    static func writeNumberByDigits(_ value: CGFloat, to destination: UnsafeMutablePointer<UInt8>) -> Int {
        guard value.isFinite, abs(value) < 1e12 else {
            destination[0] = UInt8(ascii: "0")
            return 1
        }
        let hundredths = Int((value * 100).rounded())
        guard hundredths != 0 else {
            destination[0] = UInt8(ascii: "0")
            return 1
        }
        var written = 0
        if hundredths < 0 {
            destination[0] = UInt8(ascii: "-")
            written = 1
        }
        let magnitude = hundredths.magnitude
        let whole = magnitude / 100
        let fraction = magnitude &- whole &* 100
        written &+= writeDigits(of: whole, to: destination + written)
        guard fraction != 0 else { return written }
        let tens = fraction / 10
        let ones = fraction &- tens &* 10
        destination[written] = UInt8(ascii: ".")
        destination[written &+ 1] = UInt8(ascii: "0") &+ UInt8(truncatingIfNeeded: tens)
        guard ones != 0 else { return written &+ 2 }
        destination[written &+ 2] = UInt8(ascii: "0") &+ UInt8(truncatingIfNeeded: ones)
        return written &+ 3
    }

    /// Writes the decimal digits of `whole` at `destination`, from the last to the first, two at a time, and returns how
    /// many it wrote.
    private static func writeDigits(of whole: UInt, to destination: UnsafeMutablePointer<UInt8>) -> Int {
        var digitCount = 1
        var power: UInt = 10
        while power <= whole {
            digitCount &+= 1
            power &*= 10
        }
        let pairs = digitPairs.utf8Start
        var position = digitCount
        var remaining = whole
        while remaining >= 100 {
            let next = remaining / 100
            let pair = Int(remaining &- next &* 100) &* 2
            remaining = next
            position &-= 2
            destination[position] = pairs[pair]
            destination[position &+ 1] = pairs[pair &+ 1]
        }
        if remaining >= 10 {
            let pair = Int(remaining) &* 2
            destination[position &- 2] = pairs[pair]
            destination[position &- 1] = pairs[pair &+ 1]
        } else {
            destination[position &- 1] = UInt8(ascii: "0") &+ UInt8(truncatingIfNeeded: remaining)
        }
        return digitCount
    }

    /// `00`, `01`, … `99`: the two digits of each number below a hundred, at twice the number.
    static let digitPairs: StaticString = """
        00010203040506070809101112131415161718192021222324252627282930313233343536373839\
        40414243444546474849505152535455565758596061626364656667686970717273747576777879\
        8081828384858687888990919293949596979899
        """

    // MARK: Path elements

    /// Writes one element at `destination`, which has room for `largestPathElementByteCount` bytes, and returns how many
    /// bytes it wrote: `M`, `L`, `Q`, `C` or `Z` and its points' absolute coordinates, separated by spaces. Each kind is
    /// written in a straight line, without a loop over its points.
    @inline(__always)
    static func writePathElement(_ verb: DiagramPathVerb, _ points: UnsafePointer<CGPoint>, to destination: UnsafeMutablePointer<UInt8>,
                                 digits: DiagramSVGDigitTables = .shared) -> Int {
        switch verb {
        case .move:
            destination[0] = UInt8(ascii: "M")
            return 1 &+ writePoint(points[0], to: destination + 1, digits: digits)
        case .line:
            destination[0] = UInt8(ascii: "L")
            return 1 &+ writePoint(points[0], to: destination + 1, digits: digits)
        case .quadraticCurve:
            destination[0] = UInt8(ascii: "Q")
            let cursor = destination + 1 + writePoint(points[0], to: destination + 1, digits: digits)
            cursor[0] = UInt8(ascii: " ")
            return cursor + 1 - destination + writePoint(points[1], to: cursor + 1, digits: digits)
        case .cubicCurve:
            destination[0] = UInt8(ascii: "C")
            var cursor = destination + 1 + writePoint(points[0], to: destination + 1, digits: digits)
            cursor[0] = UInt8(ascii: " ")
            cursor += 1 + writePoint(points[1], to: cursor + 1, digits: digits)
            cursor[0] = UInt8(ascii: " ")
            return cursor + 1 - destination + writePoint(points[2], to: cursor + 1, digits: digits)
        case .close:
            destination[0] = UInt8(ascii: "Z")
            return 1
        }
    }

    /// A point's coordinates and the space between them.
    @inline(__always)
    private static func writePoint(_ point: CGPoint, to destination: UnsafeMutablePointer<UInt8>, digits: DiagramSVGDigitTables) -> Int {
        let xLength = writeNumber(point.x, to: destination, digits: digits)
        destination[xLength] = UInt8(ascii: " ")
        return xLength &+ 1 &+ writeNumber(point.y, to: destination + xLength + 1, digits: digits)
    }

    /// Writes one element of a Core Graphics path as `writePathElement(_:_:to:)` writes it; nothing for a kind Core
    /// Graphics may add later.
    @inline(__always)
    static func writePathElement(_ element: CGPathElement, to destination: UnsafeMutablePointer<UInt8>) -> Int {
        let verb: DiagramPathVerb
        switch element.type {
        case .moveToPoint: verb = .move
        case .addLineToPoint: verb = .line
        case .addQuadCurveToPoint: verb = .quadraticCurve
        case .addCurveToPoint: verb = .cubicCurve
        case .closeSubpath: verb = .close
        @unknown default: return 0
        }
        return writePathElement(verb, UnsafePointer(element.points), to: destination)
    }
}
