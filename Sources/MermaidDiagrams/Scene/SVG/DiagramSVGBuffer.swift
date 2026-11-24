/**
 * File: DiagramSVGBuffer.swift
 * ----------------------------
 * Layer: Core
 * Description: The bytes of an SVG document as the writer builds it: literals, escaped text, compact numbers and a
 *              path's data appended as UTF-8 into one buffer, made a String once at the end.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import CoreGraphics

/// One SVG document's UTF-8 bytes. Everything the writer joins goes straight into this one buffer, with no String per
/// number, path element or attribute; `text` makes the document a String once.
struct DiagramSVGBuffer {
    private(set) var bytes: [UInt8] = []

    init(reservingCapacity capacity: Int = 0) {
        bytes.reserveCapacity(capacity)
    }

    /// The document as a String, copied without checking its UTF-8 again: the bytes are ASCII literals and digits, the
    /// UTF-8 of Strings, and escaped text that leaves out only whole scalars, so they are valid UTF-8 by construction
    /// (which debug builds check). Checking would cost more than half of the copy for text beyond ASCII.
    var text: String {
        let span = bytes.span
        assert((try? UTF8Span(validating: span)) != nil, "the SVG's bytes are valid UTF-8")
        return String(copying: UTF8Span(unchecked: span))
    }

    var isEmpty: Bool {
        bytes.isEmpty
    }

    mutating func append(_ literal: StaticString) {
        literal.withUTF8Buffer { literalBytes in bytes.append(contentsOf: literalBytes) }
    }

    /// `string` as it is, unescaped: for text known to need no escaping (a color, a part's class, an identifier).
    mutating func append(_ string: String) {
        bytes.append(contentsOf: string.utf8)
    }

    mutating func append(_ other: DiagramSVGBuffer) {
        bytes.append(contentsOf: other.bytes)
    }

    mutating func append(byte: UInt8) {
        bytes.append(byte)
    }

    /// `other`'s bytes put in at `offset`, the bytes after it moved along.
    mutating func insert(_ other: DiagramSVGBuffer, at offset: Int) {
        bytes.insert(contentsOf: other.bytes, at: offset)
    }

    var count: Int {
        bytes.count
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
            bytes.append(contentsOf: textBytes)
            return
        }
        var index = 0
        while index < textBytes.count {
            let byte = textBytes[index]
            switch byte {
            case UInt8(ascii: "&"): append("&amp;")
            case UInt8(ascii: "<"): append("&lt;")
            case UInt8(ascii: ">"): append("&gt;")
            case UInt8(ascii: "\""): append("&quot;")
            case UInt8(ascii: "'"): append("&#39;")
            case 0x09, 0x0A, 0x0D: bytes.append(byte)
            case 0x00...0x1F, 0x7F: break
            case Self.firstByteOfNoncharacter where Self.isNoncharacterForbiddenInXML(textBytes, at: index):
                index += 2
            default: bytes.append(byte)
            }
            index += 1
        }
    }

    /// The lead byte of U+FFFE and U+FFFF in UTF-8 (`EF BF BE`, `EF BF BF`).
    private static let firstByteOfNoncharacter: UInt8 = 0xEF

    /// A byte that is, or may start, something escaped or left out; any other byte is copied.
    private static func mayNeedEscaping(_ byte: UInt8) -> Bool {
        switch byte {
        case 0x00...0x1F, 0x7F, firstByteOfNoncharacter, UInt8(ascii: "&"), UInt8(ascii: "<"), UInt8(ascii: ">"), UInt8(ascii: "\""),
             UInt8(ascii: "'"): true
        default: false
        }
    }

    /// Whether the bytes at `index` are U+FFFE or U+FFFF.
    private static func isNoncharacterForbiddenInXML(_ textBytes: UnsafeBufferPointer<UInt8>, at index: Int) -> Bool {
        index + 2 < textBytes.count && textBytes[index + 1] == 0xBF && (textBytes[index + 2] == 0xBE || textBytes[index + 2] == 0xBF)
    }

    // MARK: Numbers

    /// The most bytes `writeNumber` writes: a sign, twelve digits, a point and two decimals.
    static let largestNumberByteCount = 16

    /// `value` to two decimals without trailing zeros (`12`, `12.5`, `-0.25`), as Pele writes coordinates; 0 for a value
    /// that is not finite or is 1e12 or more in size.
    mutating func appendNumber(_ value: CGFloat) {
        withUnsafeTemporaryAllocation(of: UInt8.self, capacity: Self.largestNumberByteCount) { scratch in
            let start = scratch.baseAddress.unsafelyUnwrapped
            bytes.append(contentsOf: UnsafeBufferPointer(start: start, count: Self.writeNumber(value, to: start)))
        }
    }

    /// Writes `value` as `appendNumber` appends it at `destination`, which has room for `largestNumberByteCount` bytes,
    /// and returns how many bytes it wrote.
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
        var digitCount = whole < 10 ? 1 : whole < 100 ? 2 : whole < 1_000 ? 3 : whole < 10_000 ? 4 : 5
        if digitCount == 5 {
            var power: UInt = 100_000
            while power <= whole {
                digitCount += 1
                power &*= 10
            }
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
            destination[position - 1] = digit(remaining)
        }
        return digitCount
    }

    /// `00`, `01`, … `99`: the two digits of each number below a hundred, at twice the number.
    private static let digitPairs: StaticString = """
        00010203040506070809101112131415161718192021222324252627282930313233343536373839\
        40414243444546474849505152535455565758596061626364656667686970717273747576777879\
        8081828384858687888990919293949596979899
        """

    private static func digit(_ value: UInt) -> UInt8 {
        UInt8(ascii: "0") + UInt8(truncatingIfNeeded: value)
    }

    /// The numbers joined by single spaces.
    mutating func appendNumbers(_ values: [CGFloat]) {
        for (index, value) in values.enumerated() {
            if index > 0 { bytes.append(UInt8(ascii: " ")) }
            appendNumber(value)
        }
    }

    /// An opacity attribute (` fill-opacity="0.4"`), or nothing for full opacity.
    mutating func appendOpacity(_ opacity: CGFloat, attribute: StaticString) {
        guard opacity < 1 else { return }
        bytes.append(UInt8(ascii: " "))
        append(attribute)
        append("=\"")
        appendNumber(max(0, opacity))
        bytes.append(UInt8(ascii: "\""))
    }

    // MARK: Paths

    /// A path's data: `M`, `L`, `Q`, `C` and `Z` with absolute coordinates. The elements are written one after the
    /// other into scratch memory with room for the longest data the path can take, and appended at once.
    mutating func appendPathData(_ path: DiagramScenePath) {
        let counts = path.elementAndPointCounts
        let room = counts.elements + counts.points * (2 * Self.largestNumberByteCount + 2)
        withUnsafeTemporaryAllocation(of: UInt8.self, capacity: room) { scratch in
            let first = scratch.baseAddress.unsafelyUnwrapped
            var destination = first
            path.forEachElement { element, points in destination += Self.writePathElement(element, points, to: destination) }
            bytes.append(contentsOf: UnsafeBufferPointer(start: first, count: destination - first))
        }
    }

    /// A Core Graphics path's data, as `appendPathData` writes a scene path's.
    mutating func appendPathData(_ path: CGPath) {
        appendPathData(DiagramScenePath(path))
    }

    /// Writes one path element at `destination` and returns how many bytes it wrote.
    @inline(__always)
    private static func writePathElement(_ element: DiagramScenePathElement, _ points: UnsafeBufferPointer<CGPoint>,
                                         to destination: UnsafeMutablePointer<UInt8>) -> Int {
        switch element {
        case .move: destination[0] = UInt8(ascii: "M")
        case .line: destination[0] = UInt8(ascii: "L")
        case .quadCurve: destination[0] = UInt8(ascii: "Q")
        case .curve: destination[0] = UInt8(ascii: "C")
        case .close:
            destination[0] = UInt8(ascii: "Z")
            return 1
        }
        var count = 1
        for index in 0..<points.count {
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
