/**
 * File: DiagramSVGNumberWriting.swift
 * -----------------------------------
 * Layer: Core
 * Description: Writes numbers to two decimals and path elements as bytes at a destination with room for them, by exactly
 *              the rule of 0.6.1: a number under 10,000 in size with no branch on its digits, larger ones digit by digit.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics

/// Writes numbers and path elements at a destination that has room for them. A number is written to two decimals
/// without trailing zeros (`12`, `12.5`, `-0.25`): its hundredths are `Int((value * 100).rounded())`, ties away from
/// zero; a value that is not finite or is 1e12 or more in size is written `0`, as 0.6.1 wrote it.
enum DiagramSVGNumberWriting {
    /// The most bytes `writeNumber` takes at its destination: a sign, twelve digits, a point and two decimals; the
    /// writer of small numbers stores two whole 32-bit words, at most nine bytes from the destination.
    static let largestNumberByteCount = 16

    /// The most bytes one path element takes: its letter, three points of two numbers and the spaces between them.
    static let largestPathElementByteCount = 1 + 6 * largestNumberByteCount + 5

    /// Writes `value` at `destination`, which has room for `largestNumberByteCount` bytes, and returns how many bytes
    /// the number is. A number under 9,999 in size (nearly every coordinate) is written without a branch on its digits:
    /// its whole part from two lookups of two digits each, packed into one 32-bit word and shifted by its length, and its
    /// point and decimals in a second word, both stored whole and the length worked out from the digits; the bytes
    /// stored past the number are left for what follows to overwrite.
    @inline(__always)
    static func writeNumber(_ value: CGFloat, to destination: UnsafeMutablePointer<UInt8>) -> Int {
        guard abs(value) < 9_999 else { return writeNumberByDigits(value, to: destination) }
        let hundredths = Int((value * 100).rounded())
        let isNegative = hundredths < 0
        let magnitude = UInt(bitPattern: isNegative ? 0 &- hundredths : hundredths)
        let whole = magnitude / 100
        let fraction = magnitude &- whole &* 100
        let high = whole / 100
        let low = whole &- high &* 100
        let pairs = UnsafeRawPointer(digitPairs.utf8Start)
        var word = UInt32(pairs.loadUnaligned(fromByteOffset: Int(high) &* 2, as: UInt16.self))
            | UInt32(pairs.loadUnaligned(fromByteOffset: Int(low) &* 2, as: UInt16.self)) << 16
        let wholeLength = 1 &+ (whole >= 10 ? 1 : 0) &+ (whole >= 100 ? 1 : 0) &+ (whole >= 1_000 ? 1 : 0)
        word >>= UInt32(truncatingIfNeeded: (4 &- wholeLength) &* 8)
        destination[0] = UInt8(ascii: "-")
        let digits = UnsafeMutableRawPointer(destination + (isNegative ? 1 : 0))
        digits.storeBytes(of: word, as: UInt32.self)
        let tens = fraction / 10
        let ones = fraction &- tens &* 10
        let decimals = UInt32(UInt8(ascii: ".")) | UInt32(UInt8(ascii: "0") &+ UInt8(truncatingIfNeeded: tens)) << 8
            | UInt32(UInt8(ascii: "0") &+ UInt8(truncatingIfNeeded: ones)) << 16
        digits.storeBytes(of: decimals, toByteOffset: wholeLength, as: UInt32.self)
        let decimalsLength = fraction == 0 ? 0 : (ones == 0 ? 2 : 3)
        return (isNegative ? 1 : 0) &+ wholeLength &+ decimalsLength
    }

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
    /// bytes it wrote: `M`, `L`, `Q`, `C` or `Z` and its points' absolute coordinates, separated by spaces.
    @inline(__always)
    static func writePathElement(_ verb: DiagramPathVerb, _ points: UnsafePointer<CGPoint>, to destination: UnsafeMutablePointer<UInt8>) -> Int {
        let pointCount: Int
        switch verb {
        case .move:
            destination[0] = UInt8(ascii: "M")
            pointCount = 1
        case .line:
            destination[0] = UInt8(ascii: "L")
            pointCount = 1
        case .quadraticCurve:
            destination[0] = UInt8(ascii: "Q")
            pointCount = 2
        case .cubicCurve:
            destination[0] = UInt8(ascii: "C")
            pointCount = 3
        case .close:
            destination[0] = UInt8(ascii: "Z")
            return 1
        }
        var cursor = destination + 1
        for index in 0..<pointCount {
            if index > 0 {
                cursor[0] = UInt8(ascii: " ")
                cursor += 1
            }
            cursor += writeNumber(points[index].x, to: cursor)
            cursor[0] = UInt8(ascii: " ")
            cursor += 1
            cursor += writeNumber(points[index].y, to: cursor)
        }
        return cursor - destination
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
