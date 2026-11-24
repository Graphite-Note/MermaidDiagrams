/**
 * File: DiagramSVGBuffer.swift
 * ----------------------------
 * Layer: Core
 * Description: The bytes of an SVG document as the writer builds it: room made sure of once for a piece or a whole
 *              element, then literals, escaped text, compact numbers and path elements written unchecked through a
 *              cursor over one block of memory, the thread's scratch block or one of the buffer's own.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 24/11/2026
 */

import CoreGraphics

/// One SVG document's UTF-8 bytes in one block of memory: a block lent by the thread's scratch (`init(lentBy:)`), kept
/// between documents, or one the buffer makes (`init(reservingCapacity:)`). A writer makes sure of the room for a piece
/// or a whole element once (`reserve`) and then writes it through the cursor with no per-byte check (`write…`, which
/// debug builds check against the room reserved); the `append…` pieces make sure of their own room. The block grows, to
/// twice its size or more, only when a piece does not fit. `text` makes the document a String once.
struct DiagramSVGBuffer: ~Copyable {
    private var start: UnsafeMutablePointer<UInt8>
    /// How many bytes are written.
    private(set) var count = 0
    /// How many bytes fit before the block grows.
    private(set) var capacity: Int
    /// How many times the block grew since the buffer was made.
    private(set) var growthCount = 0
    #if DEBUG
    /// Where the room reserved so far ends, which debug builds check each write against.
    private var reservedEnd = 0
    #endif
    /// The scratch the block is lent by, which takes it back when the buffer ends; nil for a block of the buffer's own.
    private let lender: DiagramSVGScratch?

    /// The fewest bytes a buffer of its own holds, so that a small one does not grow at once.
    private static let smallestCapacity = 64

    init(reservingCapacity capacity: Int = 0) {
        self.capacity = max(capacity, Self.smallestCapacity)
        start = UnsafeMutablePointer<UInt8>.allocate(capacity: self.capacity)
        lender = nil
    }

    /// A buffer writing into `scratch`'s block, which it gives back, grown or not, when it ends.
    init(lentBy scratch: DiagramSVGScratch) {
        let block = scratch.lendBlock()
        start = block.start
        capacity = block.capacity
        lender = scratch
    }

    deinit {
        if let lender {
            lender.takeBack(start, capacity: capacity)
        } else {
            start.deallocate()
        }
    }

    /// The written bytes, valid until the buffer changes or ends.
    var bytes: UnsafeBufferPointer<UInt8> {
        UnsafeBufferPointer(start: start, count: count)
    }

    /// The document as a String, copied without checking its UTF-8 again: the bytes are ASCII literals and digits, the
    /// UTF-8 of Strings, and escaped text that leaves out only whole scalars, so they are valid UTF-8 by construction
    /// (which debug builds check). Checking would cost more than half of the copy for text beyond ASCII.
    var text: String {
        Self.string(of: bytes)
    }

    /// `bytes` as a String, unchecked as `text` makes it.
    static func string(of bytes: UnsafeBufferPointer<UInt8>) -> String {
        assert((try? UTF8Span(validating: bytes.span)) != nil, "the SVG's bytes are valid UTF-8")
        return String(copying: UTF8Span(unchecked: bytes.span))
    }

    var isEmpty: Bool {
        count == 0
    }

    /// Where the bytes are, for a test that checks the block is written in place.
    var storageAddress: UnsafePointer<UInt8> {
        UnsafePointer(start)
    }

    // MARK: Room

    /// Makes sure `byteCount` more bytes fit, growing the block when they do not; the writes after it, up to that many
    /// bytes, need no check of their own.
    @inline(__always)
    mutating func reserve(_ byteCount: Int) {
        if capacity &- count < byteCount { grow(toFit: byteCount) }
        #if DEBUG
        reservedEnd = max(reservedEnd, count + byteCount)
        #endif
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

    /// Checks, in debug builds only, that `byteCount` more bytes lie within the room reserved last: a write the room
    /// does not cover would go past the block's end, which the output alone does not show.
    @inline(__always)
    private func assertReserved(_ byteCount: Int) {
        #if DEBUG
        assert(count + byteCount <= reservedEnd && reservedEnd <= capacity, "a write past the room reserved for it")
        #endif
    }

    /// The end of what is written, where the next byte goes.
    @inline(__always)
    private var cursor: UnsafeMutablePointer<UInt8> {
        start + count
    }

    // MARK: Unchecked writes, within the room reserved

    /// A literal; short ones copied byte by byte without a call.
    @inline(__always)
    mutating func write(_ literal: StaticString) {
        let length = literal.utf8CodeUnitCount
        assertReserved(length)
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
        assertReserved(1)
        cursor.pointee = byte
        count &+= 1
    }

    @inline(__always)
    mutating func write(_ bytes: UnsafeBufferPointer<UInt8>) {
        guard let source = bytes.baseAddress else { return }
        assertReserved(bytes.count)
        cursor.initialize(from: source, count: bytes.count)
        count &+= bytes.count
    }

    /// The first `byteCount` bytes of `packed`, from its lowest, stored as one word: room for all eight is reserved.
    @inline(__always)
    mutating func write(packedBytes packed: UInt64, count byteCount: Int) {
        assertReserved(8)
        UnsafeMutableRawPointer(cursor).storeBytes(of: packed.littleEndian, as: UInt64.self)
        count &+= byteCount
    }

    /// A number, as `appendNumber` writes it.
    @inline(__always)
    mutating func write(number value: CGFloat) {
        assertReserved(DiagramSVGNumberWriting.largestNumberByteCount)
        count &+= DiagramSVGNumberWriting.writeNumber(value, to: cursor)
    }

    /// One path element, as `DiagramSVGNumberWriting.writePathElement` writes it.
    @inline(__always)
    mutating func write(pathElement verb: DiagramPathVerb, _ points: UnsafePointer<CGPoint>) {
        assertReserved(DiagramSVGNumberWriting.largestPathElementByteCount)
        count &+= DiagramSVGNumberWriting.writePathElement(verb, points, to: cursor)
    }

    /// Path elements written at the cursor by `body` in one go, `byteCount` bytes reserved for them: `body` writes at
    /// the pointer it is given and returns how many bytes it wrote, at most `byteCount`.
    @inline(__always)
    mutating func write(reserving byteCount: Int, _ body: (UnsafeMutablePointer<UInt8>) -> Int) {
        reserve(byteCount)
        let written = body(cursor)
        assert(written <= byteCount, "a write past the room reserved for it")
        count &+= written
    }

    /// One element of a Core Graphics path.
    @inline(__always)
    mutating func write(pathElement element: CGPathElement) {
        assertReserved(DiagramSVGNumberWriting.largestPathElementByteCount)
        count &+= DiagramSVGNumberWriting.writePathElement(element, to: cursor)
    }

    /// An opacity attribute whose name holds its space and `="` (` fill-opacity="`), or nothing for full opacity.
    @inline(__always)
    mutating func write(opacity: CGFloat, attribute: StaticString) {
        guard opacity < 1 else { return }
        write(attribute)
        write(number: max(0, opacity))
        write(byte: UInt8(ascii: "\""))
    }

    // MARK: Pieces that make sure of their own room

    /// Inlined, so that a literal's length is known where it is written and its bytes are copied without a call.
    @inline(__always)
    mutating func append(_ literal: StaticString) {
        reserve(literal.utf8CodeUnitCount)
        write(literal)
    }

    /// `string` as it is, unescaped: for text known to need no escaping (a color, a part's class, an identifier). A
    /// native String's bytes are read in place, without a copy of the String (and the retain it takes).
    mutating func append(_ string: String) {
        if let appended: Void = string.utf8.withContiguousStorageIfAvailable({ stringBytes in append(stringBytes) }) { return appended }
        var copy = string
        copy.withUTF8 { stringBytes in append(stringBytes) }
    }

    mutating func append(_ bytes: UnsafeBufferPointer<UInt8>) {
        reserve(bytes.count)
        write(bytes)
    }

    mutating func append(byte: UInt8) {
        reserve(1)
        write(byte: byte)
    }

    /// `value` to two decimals without trailing zeros (`12`, `12.5`, `-0.25`), as Pele writes coordinates; 0 for a value
    /// that is not finite or is 1e12 or more in size.
    mutating func appendNumber(_ value: CGFloat) {
        reserve(DiagramSVGNumberWriting.largestNumberByteCount)
        write(number: value)
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
        reserve(attribute.utf8CodeUnitCount + DiagramSVGNumberWriting.largestNumberByteCount + 4)
        write(byte: UInt8(ascii: " "))
        write(attribute)
        write("=\"")
        write(number: max(0, opacity))
        write(byte: UInt8(ascii: "\""))
    }

    // MARK: Text

    /// `text` for an attribute's value or an element's content: `&`, `<`, `>`, `"` and `'` as entities, and the
    /// characters XML 1.0 has no place for (control characters other than tab, line feed and carriage return, U+FFFE and
    /// U+FFFF) left out. Text with none of them, as nearly all is, is copied as it is.
    mutating func appendEscaped(_ text: String) {
        if let appended: Void = text.utf8.withContiguousStorageIfAvailable({ textBytes in appendEscaped(textBytes) }) { return appended }
        var copy = text
        copy.withUTF8 { textBytes in appendEscaped(textBytes) }
    }

    mutating func appendEscaped(_ textBytes: UnsafeBufferPointer<UInt8>) {
        guard textBytes.contains(where: Self.mayNeedEscaping) else { return append(textBytes) }
        var index = 0
        while index < textBytes.count {
            let byte = textBytes[index]
            // An entity is at most six bytes (`&quot;`) for one byte.
            reserve(6)
            switch byte {
            case UInt8(ascii: "&"): write("&amp;")
            case UInt8(ascii: "<"): write("&lt;")
            case UInt8(ascii: ">"): write("&gt;")
            case UInt8(ascii: "\""): write("&quot;")
            case UInt8(ascii: "'"): write("&#39;")
            case 0x09, 0x0A, 0x0D: write(byte: byte)
            case 0x00...0x1F, 0x7F: break
            case Self.firstByteOfNoncharacter where Self.isNoncharacterForbiddenInXML(textBytes, at: index):
                index += 2
            default: write(byte: byte)
            }
            index += 1
        }
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

    // MARK: Paths

    /// A Core Graphics path's data: `M`, `L`, `Q`, `C` and `Z` with absolute coordinates. Core Graphics hands each
    /// element to a C function, which makes sure of its room once and writes it whole at the cursor: no block is made
    /// for the call, and nothing is copied through scratch memory.
    mutating func appendPathData(_ path: CGPath) {
        withUnsafeMutablePointer(to: &self) { buffer in
            path.apply(info: UnsafeMutableRawPointer(buffer)) { info, element in
                let buffer = info.unsafelyUnwrapped.assumingMemoryBound(to: DiagramSVGBuffer.self)
                buffer.pointee.reserve(DiagramSVGNumberWriting.largestPathElementByteCount)
                buffer.pointee.write(pathElement: element.pointee)
            }
        }
    }
}
