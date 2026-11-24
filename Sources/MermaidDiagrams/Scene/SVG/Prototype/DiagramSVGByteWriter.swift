/**
 * File: DiagramSVGByteWriter.swift
 * --------------------------------
 * Layer: Core (design prototype, not for merging)
 * Description: One reusable block of bytes an SVG document is written into: room made sure of once per element, then
 *              literals, escaped text and numbers written unchecked at a cursor; the numbers by 0.6.1's rule, faster.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics

/// The bytes of documents written one after another: the block is kept between documents, so that a writer reused on
/// one thread allocates nothing once it has grown to its largest document.
public final class DiagramSVGScratch {
    fileprivate(set) var start: UnsafeMutablePointer<UInt8>
    fileprivate(set) var capacity: Int
    /// The escaped root style and font family of the last font written, kept with the font they are of.
    var hasCachedFont = false
    var cachedFontIsPeleVariables = false
    var cachedFontPostScriptName: String?
    var cachedRootStyleAndFont: [UInt8] = []

    public init(capacity: Int = 16_384) {
        self.capacity = capacity
        start = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
    }

    deinit {
        start.deallocate()
    }

    @inline(never)
    func grow(keeping count: Int, toFit byteCount: Int) {
        let grownCapacity = max(capacity * 2, count + byteCount)
        let grown = UnsafeMutablePointer<UInt8>.allocate(capacity: grownCapacity)
        grown.initialize(from: start, count: count)
        start.deallocate()
        start = grown
        capacity = grownCapacity
    }
}

/// A cursor over a scratch block. `reserve` makes sure of the room for a whole element; every write after it is
/// unchecked (debug builds check it).
struct DiagramSVGByteWriter {
    let scratch: DiagramSVGScratch
    private(set) var count = 0
    private var reservedEnd = 0

    init(scratch: DiagramSVGScratch) {
        self.scratch = scratch
    }

    @inline(__always)
    mutating func reserve(_ byteCount: Int) {
        if scratch.capacity &- count < byteCount { scratch.grow(keeping: count, toFit: byteCount) }
        reservedEnd = count &+ byteCount
    }

    @inline(__always)
    private var cursor: UnsafeMutablePointer<UInt8> {
        scratch.start + count
    }

    /// The document as a String: one allocation and one copy.
    var text: String {
        let written = UnsafeBufferPointer(start: scratch.start, count: count)
        return String(copying: UTF8Span(unchecked: written.span))
    }

    // MARK: Pieces

    @inline(__always)
    mutating func write(_ literal: StaticString) {
        let length = literal.utf8CodeUnitCount
        assert(count + length <= reservedEnd)
        // Short literals copied without a call to memmove.
        let source = literal.utf8Start
        let destination = cursor
        if length <= 16 {
            for index in 0..<length { destination[index] = source[index] }
        } else {
            destination.initialize(from: source, count: length)
        }
        count &+= length
    }

    @inline(__always)
    mutating func write(byte: UInt8) {
        assert(count < reservedEnd)
        cursor.pointee = byte
        count &+= 1
    }

    mutating func write(bytes: UnsafeBufferPointer<UInt8>) {
        guard let source = bytes.baseAddress else { return }
        assert(count + bytes.count <= reservedEnd)
        cursor.initialize(from: source, count: bytes.count)
        count &+= bytes.count
    }

    /// A String known to need no escaping (a color, a class); the room for it reserved here.
    mutating func writeReserving(_ string: String) {
        var string = string
        string.withUTF8 { bytes in
            reserve(bytes.count)
            write(bytes: bytes)
        }
    }

    // MARK: Escaped text

    /// `text` escaped as `DiagramSVGBuffer.appendEscaped` escapes it, its room reserved here: six bytes a byte at most.
    mutating func writeEscapedReserving(_ text: String) {
        var text = text
        text.withUTF8 { bytes in writeEscapedReserving(bytes) }
    }

    mutating func writeEscapedReserving(_ bytes: UnsafeBufferPointer<UInt8>) {
        var mayNeedEscaping = false
        for byte in bytes where Self.mayNeedEscaping(byte) {
            mayNeedEscaping = true
            break
        }
        guard mayNeedEscaping else {
            reserve(bytes.count)
            write(bytes: bytes)
            return
        }
        reserve(bytes.count * 6)
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            switch byte {
            case UInt8(ascii: "&"): write("&amp;")
            case UInt8(ascii: "<"): write("&lt;")
            case UInt8(ascii: ">"): write("&gt;")
            case UInt8(ascii: "\""): write("&quot;")
            case UInt8(ascii: "'"): write("&#39;")
            case 0x09, 0x0A, 0x0D: write(byte: byte)
            case 0x00...0x1F, 0x7F: break
            case 0xEF where index + 2 < bytes.count && bytes[index + 1] == 0xBF && (bytes[index + 2] == 0xBE || bytes[index + 2] == 0xBF):
                index += 2
            default: write(byte: byte)
            }
            index += 1
        }
    }

    private static let lowBytesThatMayNeedEscaping: UInt64 = 0x0000_0000_FFFF_FFFF
        | 1 << 0x22 | 1 << 0x26 | 1 << 0x27 | 1 << 0x3C | 1 << 0x3E

    @inline(__always)
    private static func mayNeedEscaping(_ byte: UInt8) -> Bool {
        byte < 64 ? lowBytesThatMayNeedEscaping >> byte & 1 != 0 : byte == 0x7F || byte == 0xEF
    }

    // MARK: Numbers

    /// The most bytes a number takes: a sign, twelve digits, a point and two decimals.
    static let largestNumberByteCount = 16

    /// `value` to two decimals without trailing zeros, exactly as `DiagramSVGNumberWriting.writeNumber` writes it.
    @inline(__always)
    mutating func write(number value: CGFloat) {
        assert(count + Self.largestNumberByteCount <= reservedEnd)
        count &+= Self.writeNumber(value, to: cursor)
    }

    /// The common case without a branch on its digits: a number under 10,000 in size, its whole digits and its two
    /// decimals made in one 32-bit word each and stored whole, the cursor moved by the digits that count. Larger or
    /// non-finite numbers take the general rule (`writeNumberByDigits`).
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
        let pairs = UnsafeRawPointer(DiagramSVGNumberWriting.digitPairs.utf8Start)
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
        let magnitude: UInt
        if hundredths < 0 {
            destination[0] = UInt8(ascii: "-")
            written = 1
            magnitude = UInt(bitPattern: 0 &- hundredths)
        } else {
            magnitude = UInt(bitPattern: hundredths)
        }
        let whole = magnitude / 100
        let fraction = magnitude &- whole &* 100
        written &+= writeWhole(whole, to: destination + written)
        guard fraction != 0 else { return written }
        let tens = fraction / 10
        let ones = fraction &- tens &* 10
        destination[written] = UInt8(ascii: ".")
        destination[written &+ 1] = UInt8(ascii: "0") &+ UInt8(truncatingIfNeeded: tens)
        guard ones != 0 else { return written &+ 2 }
        destination[written &+ 2] = UInt8(ascii: "0") &+ UInt8(truncatingIfNeeded: ones)
        return written &+ 3
    }

    /// The digits of a whole number: up to four by comparisons, more by pairs from the end.
    @inline(__always)
    private static func writeWhole(_ whole: UInt, to destination: UnsafeMutablePointer<UInt8>) -> Int {
        let pairs = DiagramSVGNumberWriting.digitPairs.utf8Start
        if whole < 10 {
            destination[0] = UInt8(ascii: "0") &+ UInt8(truncatingIfNeeded: whole)
            return 1
        }
        if whole < 100 {
            let pair = Int(whole) &* 2
            destination[0] = pairs[pair]
            destination[1] = pairs[pair &+ 1]
            return 2
        }
        if whole < 1_000 {
            let hundreds = whole / 100
            let pair = Int(whole &- hundreds &* 100) &* 2
            destination[0] = UInt8(ascii: "0") &+ UInt8(truncatingIfNeeded: hundreds)
            destination[1] = pairs[pair]
            destination[2] = pairs[pair &+ 1]
            return 3
        }
        if whole < 10_000 {
            let high = whole / 100
            let highPair = Int(high) &* 2
            let lowPair = Int(whole &- high &* 100) &* 2
            destination[0] = pairs[highPair]
            destination[1] = pairs[highPair &+ 1]
            destination[2] = pairs[lowPair]
            destination[3] = pairs[lowPair &+ 1]
            return 4
        }
        var digitCount = 5
        var power: UInt = 100_000
        while power <= whole {
            digitCount &+= 1
            power &*= 10
        }
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

    // MARK: Paths

    /// The most bytes a verb takes: its letter, three points of two numbers and the spaces between them.
    static let largestVerbByteCount = 1 + 6 * largestNumberByteCount + 5

    /// A flat path's data, its room reserved here once.
    mutating func writePathData(verbs: UnsafePointer<DiagramPathVerb>, verbCount: Int, points: UnsafePointer<CGPoint>) {
        reserve(verbCount &* Self.largestVerbByteCount)
        var destination = cursor
        var point = points
        for index in 0..<verbCount {
            let verb = verbs[index]
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
                destination += 1
                continue
            }
            destination += 1
            for pointIndex in 0..<pointCount {
                if pointIndex > 0 {
                    destination[0] = UInt8(ascii: " ")
                    destination += 1
                }
                destination += Self.writeNumber(point[pointIndex].x, to: destination)
                destination[0] = UInt8(ascii: " ")
                destination += 1
                destination += Self.writeNumber(point[pointIndex].y, to: destination)
            }
            point += pointCount
        }
        count = destination - scratch.start
        assert(count <= reservedEnd)
    }
}
