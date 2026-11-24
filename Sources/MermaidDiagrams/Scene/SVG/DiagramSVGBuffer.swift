/**
 * File: DiagramSVGBuffer.swift
 * ----------------------------
 * Layer: Core
 * Description: The bytes of an SVG document as the writer builds it: literals, escaped text, compact numbers and a
 *              path's data written as UTF-8 through a cursor over one block of memory, made a String once at the end.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import CoreGraphics

/// One SVG document's UTF-8 bytes, in one block of memory the buffer owns. Each piece makes sure of its room once (a
/// literal, a String's bytes, a number, a path element) and is then written through a pointer at the end of what is
/// written, with no per-byte check; the block grows, to twice its size or more, only when a piece does not fit, which a
/// document whose room was reserved from its scene does not do. `text` makes the document a String once.
struct DiagramSVGBuffer: ~Copyable {
    private var start: UnsafeMutablePointer<UInt8>
    /// How many bytes are written.
    private(set) var count = 0
    /// How many bytes fit before the block grows.
    private(set) var capacity: Int
    /// How many times the block grew since the buffer was made.
    private(set) var growthCount = 0

    /// The fewest bytes a buffer holds, so that a small one does not grow at once.
    private static let smallestCapacity = 64

    init(reservingCapacity capacity: Int = 0) {
        self.capacity = max(capacity, Self.smallestCapacity)
        start = UnsafeMutablePointer<UInt8>.allocate(capacity: self.capacity)
    }

    deinit {
        start.deallocate()
    }

    /// The document as a String, copied without checking its UTF-8 again: the bytes are ASCII literals and digits, the
    /// UTF-8 of Strings, and escaped text that leaves out only whole scalars, so they are valid UTF-8 by construction
    /// (which debug builds check). Checking would cost more than half of the copy for text beyond ASCII.
    var text: String {
        let written = UnsafeBufferPointer(start: start, count: count)
        let span = written.span
        assert((try? UTF8Span(validating: span)) != nil, "the SVG's bytes are valid UTF-8")
        return String(copying: UTF8Span(unchecked: span))
    }

    var isEmpty: Bool {
        count == 0
    }

    /// Where the bytes are, for a test that checks the block is written in place.
    var storageAddress: UnsafePointer<UInt8> {
        UnsafePointer(start)
    }

    // MARK: Room

    /// Makes sure `byteCount` more bytes fit, growing the block when they do not.
    @inline(__always)
    private mutating func reserveRoom(_ byteCount: Int) {
        if capacity &- count < byteCount { grow(toFit: byteCount) }
    }

    /// Moves the bytes into a block of at least twice the size, with room for `byteCount` more.
    @inline(never)
    private mutating func grow(toFit byteCount: Int) {
        let grownCapacity = max(capacity * 2, count + byteCount)
        let grown = UnsafeMutablePointer<UInt8>.allocate(capacity: grownCapacity)
        grown.initialize(from: start, count: count)
        start.deallocate()
        start = grown
        capacity = grownCapacity
        growthCount += 1
    }

    /// The end of what is written, where the next byte goes; the room after it is reserved by the caller.
    @inline(__always)
    private var cursor: UnsafeMutablePointer<UInt8> {
        start + count
    }

    // MARK: Pieces

    /// Inlined, so that a literal's length is known where it is written and its bytes are copied without a call.
    @inline(__always)
    mutating func append(_ literal: StaticString) {
        let length = literal.utf8CodeUnitCount
        reserveRoom(length)
        cursor.initialize(from: literal.utf8Start, count: length)
        count &+= length
    }

    /// `string` as it is, unescaped: for text known to need no escaping (a color, a part's class, an identifier).
    mutating func append(_ string: String) {
        var string = string
        string.withUTF8 { stringBytes in append(stringBytes) }
    }

    private mutating func append(_ bytes: UnsafeBufferPointer<UInt8>) {
        guard let source = bytes.baseAddress else { return }
        reserveRoom(bytes.count)
        cursor.initialize(from: source, count: bytes.count)
        count &+= bytes.count
    }

    mutating func append(byte: UInt8) {
        reserveRoom(1)
        cursor.initialize(to: byte)
        count &+= 1
    }

    // MARK: Text

    /// `text` for an attribute's value or an element's content: `&`, `<`, `>`, `"` and `'` as entities, and the
    /// characters XML 1.0 has no place for (control characters other than tab, line feed and carriage return, U+FFFE and
    /// U+FFFF) left out. Text with none of them, as nearly all is, is copied as it is.
    mutating func appendEscaped(_ text: String) {
        var text = text
        text.withUTF8 { textBytes in appendEscaped(textBytes) }
    }

    private mutating func appendEscaped(_ textBytes: UnsafeBufferPointer<UInt8>) {
        guard textBytes.contains(where: Self.mayNeedEscaping) else {
            append(textBytes)
            return
        }
        var index = 0
        while index < textBytes.count {
            let byte = textBytes[index]
            // An entity is at most six bytes (`&quot;`) for one byte.
            reserveRoom(6)
            switch byte {
            case UInt8(ascii: "&"): writeUnchecked("&amp;")
            case UInt8(ascii: "<"): writeUnchecked("&lt;")
            case UInt8(ascii: ">"): writeUnchecked("&gt;")
            case UInt8(ascii: "\""): writeUnchecked("&quot;")
            case UInt8(ascii: "'"): writeUnchecked("&#39;")
            case 0x09, 0x0A, 0x0D: writeUnchecked(byte)
            case 0x00...0x1F, 0x7F: break
            case Self.firstByteOfNoncharacter where Self.isNoncharacterForbiddenInXML(textBytes, at: index):
                index += 2
            default: writeUnchecked(byte)
            }
            index += 1
        }
    }

    /// A literal written where room is already reserved.
    @inline(__always)
    private mutating func writeUnchecked(_ literal: StaticString) {
        cursor.initialize(from: literal.utf8Start, count: literal.utf8CodeUnitCount)
        count &+= literal.utf8CodeUnitCount
    }

    @inline(__always)
    private mutating func writeUnchecked(_ byte: UInt8) {
        cursor.initialize(to: byte)
        count &+= 1
    }

    /// The lead byte of U+FFFE and U+FFFF in UTF-8 (`EF BF BE`, `EF BF BF`).
    private static let firstByteOfNoncharacter: UInt8 = 0xEF

    /// The bytes below 64 that are, or may start, something escaped or left out: the control characters, `"`, `&`, `'`,
    /// `<` and `>`, one bit each.
    private static let lowBytesThatMayNeedEscaping: UInt64 = 0x0000_0000_FFFF_FFFF
        | 1 << 0x22 | 1 << 0x26 | 1 << 0x27 | 1 << 0x3C | 1 << 0x3E

    /// A byte that is, or may start, something escaped or left out; any other byte is copied.
    @inline(__always)
    private static func mayNeedEscaping(_ byte: UInt8) -> Bool {
        byte < 64 ? lowBytesThatMayNeedEscaping >> byte & 1 != 0 : byte == 0x7F || byte == firstByteOfNoncharacter
    }

    /// Whether the bytes at `index` are U+FFFE or U+FFFF.
    private static func isNoncharacterForbiddenInXML(_ textBytes: UnsafeBufferPointer<UInt8>, at index: Int) -> Bool {
        index + 2 < textBytes.count && textBytes[index + 1] == 0xBF && (textBytes[index + 2] == 0xBE || textBytes[index + 2] == 0xBF)
    }

    // MARK: Numbers

    /// `value` to two decimals without trailing zeros (`12`, `12.5`, `-0.25`), as Pele writes coordinates; 0 for a value
    /// that is not finite or is 1e12 or more in size.
    mutating func appendNumber(_ value: CGFloat) {
        reserveRoom(DiagramSVGNumberWriting.largestNumberByteCount)
        count &+= DiagramSVGNumberWriting.writeNumber(value, to: cursor)
    }

    /// The numbers joined by single spaces.
    mutating func appendNumbers(_ values: [CGFloat]) {
        for (index, value) in values.enumerated() {
            if index > 0 { append(byte: UInt8(ascii: " ")) }
            appendNumber(value)
        }
    }

    /// An opacity attribute (` fill-opacity="0.4"`), or nothing for full opacity.
    mutating func appendOpacity(_ opacity: CGFloat, attribute: StaticString) {
        guard opacity < 1 else { return }
        reserveRoom(attribute.utf8CodeUnitCount + DiagramSVGNumberWriting.largestNumberByteCount + 4)
        writeUnchecked(UInt8(ascii: " "))
        writeUnchecked(attribute)
        writeUnchecked("=\"")
        count &+= DiagramSVGNumberWriting.writeNumber(max(0, opacity), to: cursor)
        writeUnchecked(UInt8(ascii: "\""))
    }

    // MARK: Paths

    /// A path's data: `M`, `L`, `Q`, `C` and `Z` with absolute coordinates. Core Graphics hands each element to a C
    /// function, which writes it whole at the cursor after making sure of its room once: no block is made for the call,
    /// and nothing is copied through scratch memory.
    mutating func appendPathData(_ path: CGPath) {
        withUnsafeMutablePointer(to: &self) { buffer in
            path.apply(info: UnsafeMutableRawPointer(buffer)) { info, element in
                info.unsafelyUnwrapped.assumingMemoryBound(to: DiagramSVGBuffer.self).pointee.appendPathElement(element.pointee)
            }
        }
    }

    private mutating func appendPathElement(_ element: CGPathElement) {
        reserveRoom(DiagramSVGNumberWriting.largestPathElementByteCount)
        count &+= DiagramSVGNumberWriting.writePathElement(element, to: cursor)
    }
}

/// Writes numbers and path elements as bytes at a destination with room for them, by exactly the rule of 0.6.1.
enum DiagramSVGNumberWriting {
    /// The most bytes `writeNumber` writes: a sign, twelve digits, a point and two decimals.
    static let largestNumberByteCount = 16

    /// The most bytes one path element takes: its letter, three points of two numbers and the spaces between them.
    static let largestPathElementByteCount = 1 + 6 * largestNumberByteCount + 5

    /// Writes `value` as `DiagramSVGBuffer.appendNumber` appends it at `destination`, which has room for
    /// `largestNumberByteCount` bytes, and returns how many bytes it wrote.
    static func writeNumber(_ value: CGFloat, to destination: UnsafeMutablePointer<UInt8>) -> Int {
        guard value.isFinite, abs(value) < 1e12 else {
            destination[0] = UInt8(ascii: "0")
            return 1
        }
        let hundredths = Int((value * 100).rounded())
        guard hundredths != 0 else {
            destination[0] = UInt8(ascii: "0")
            return 1
        }
        var count = 0
        if hundredths < 0 {
            destination[0] = UInt8(ascii: "-")
            count = 1
        }
        let magnitude = hundredths.magnitude
        count += writeDigits(of: magnitude / 100, to: destination + count)
        let pairs = digitPairs.utf8Start
        let fraction = Int(magnitude % 100)
        guard fraction != 0 else { return count }
        destination[count] = UInt8(ascii: ".")
        destination[count + 1] = pairs[fraction &* 2]
        guard !fraction.isMultiple(of: 10) else { return count + 2 }
        destination[count + 2] = pairs[fraction &* 2 + 1]
        return count + 3
    }

    /// Writes the decimal digits of `whole` at `destination`, from the last to the first, two at a time, and returns how
    /// many it wrote.
    private static func writeDigits(of whole: UInt, to destination: UnsafeMutablePointer<UInt8>) -> Int {
        var digitCount = 1
        var power: UInt = 10
        while power <= whole {
            digitCount += 1
            power &*= 10
        }
        let pairs = digitPairs.utf8Start
        var position = digitCount
        var remaining = whole
        while remaining >= 100 {
            let pair = Int(remaining % 100) &* 2
            remaining /= 100
            position -= 2
            destination[position] = pairs[pair]
            destination[position + 1] = pairs[pair + 1]
        }
        if remaining >= 10 {
            let pair = Int(remaining) &* 2
            destination[position - 2] = pairs[pair]
            destination[position - 1] = pairs[pair + 1]
        } else {
            destination[position - 1] = UInt8(ascii: "0") + UInt8(truncatingIfNeeded: remaining)
        }
        return digitCount
    }

    /// `00`, `01`, … `99`: the two digits of each number below a hundred, at twice the number.
    static let digitPairs: StaticString = """
        00010203040506070809101112131415161718192021222324252627282930313233343536373839\
        40414243444546474849505152535455565758596061626364656667686970717273747576777879\
        8081828384858687888990919293949596979899
        """

    /// Writes one path element at `destination`, which has room for `largestPathElementByteCount` bytes, and returns how
    /// many bytes it wrote.
    static func writePathElement(_ element: CGPathElement, to destination: UnsafeMutablePointer<UInt8>) -> Int {
        let points = element.points
        let pointCount: Int
        switch element.type {
        case .moveToPoint:
            destination[0] = UInt8(ascii: "M")
            pointCount = 1
        case .addLineToPoint:
            destination[0] = UInt8(ascii: "L")
            pointCount = 1
        case .addQuadCurveToPoint:
            destination[0] = UInt8(ascii: "Q")
            pointCount = 2
        case .addCurveToPoint:
            destination[0] = UInt8(ascii: "C")
            pointCount = 3
        case .closeSubpath:
            destination[0] = UInt8(ascii: "Z")
            return 1
        @unknown default:
            return 0
        }
        var count = 1
        for index in 0..<pointCount {
            if index > 0 {
                destination[count] = UInt8(ascii: " ")
                count += 1
            }
            count += writeNumber(points[index].x, to: destination + count)
            destination[count] = UInt8(ascii: " ")
            count += 1
            count += writeNumber(points[index].y, to: destination + count)
        }
        return count
    }
}
