/**
 * File: DiagramSVGBuffer.swift
 * ----------------------------
 * Layer: Core
 * Description: The bytes of an SVG document as the writer builds it: room made sure of once for a piece or a whole
 *              element, then literals, escaped text, compact numbers and path elements written unchecked through a
 *              cursor over one block of memory, the thread's scratch block or one of the buffer's own; a run of path
 *              elements written by a writer handed the cursor.
 *
 * Authors: Bahey Shalash
 * Version: 0.7
 * Date: 25/11/2026
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

    /// `part`'s class (`pele-node`), its entry copied whole: room for `DiagramSVGClassNames.entryByteCount` is reserved.
    @inline(__always)
    mutating func write(classOf part: DiagramScenePart) {
        assertReserved(DiagramSVGClassNames.entryByteCount)
        count &+= DiagramSVGClassNames.shared.write(part, to: cursor)
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

    /// Copies `textBytes` eight bytes at a time and looks at each word on the way (`mayNeedEscaping`): the last few
    /// bytes of a text of eight bytes or more as the text's last eight, which overlap the bytes copied before them, and a
    /// shorter text in one word read four, two and one bytes at a time and padded with `A`; only text with a byte that is,
    /// or may start, something escaped or left out is then written again, byte by byte.
    mutating func appendEscaped(_ textBytes: UnsafeBufferPointer<UInt8>) {
        guard let source = textBytes.baseAddress else { return }
        let byteCount = textBytes.count
        reserve(byteCount &+ 8)
        let destination = UnsafeMutableRawPointer(cursor)
        guard byteCount >= 8 else {
            let word = Self.paddedWord(source, byteCount: byteCount)
            destination.storeBytes(of: word, as: UInt64.self)
            guard Self.mayNeedEscaping(word) == 0 else { return appendEscapedByteByByte(textBytes) }
            count &+= byteCount
            return
        }
        var flags: UInt64 = 0
        var index = 0
        while index &+ 8 <= byteCount {
            let word = UnsafeRawPointer(source + index).loadUnaligned(as: UInt64.self)
            (destination + index).storeBytes(of: word, as: UInt64.self)
            flags |= Self.mayNeedEscaping(word)
            index &+= 8
        }
        if index < byteCount {
            let lastWord = UnsafeRawPointer(source + (byteCount &- 8)).loadUnaligned(as: UInt64.self)
            (destination + (byteCount &- 8)).storeBytes(of: lastWord, as: UInt64.self)
            flags |= Self.mayNeedEscaping(lastWord)
        }
        guard flags == 0 else { return appendEscapedByteByByte(textBytes) }
        count &+= byteCount
    }

    /// The fewer than eight bytes at `source` as the low bytes of a word whose other bytes are `A`, which nothing
    /// escapes: read four, two and one bytes at a time, as many as there are.
    @inline(__always)
    private static func paddedWord(_ source: UnsafePointer<UInt8>, byteCount: Int) -> UInt64 {
        var word = everyByte &* UInt64(UInt8(ascii: "A"))
        var offset = 0
        if byteCount & 4 != 0 {
            word = word & ~0xFFFF_FFFF | UInt64(UnsafeRawPointer(source).loadUnaligned(as: UInt32.self))
            offset = 4
        }
        if byteCount & 2 != 0 {
            let shift = UInt64(truncatingIfNeeded: offset &* 8)
            word = word & ~(0xFFFF << shift) | UInt64(UnsafeRawPointer(source + offset).loadUnaligned(as: UInt16.self)) << shift
            offset &+= 2
        }
        if byteCount & 1 != 0 {
            let shift = UInt64(truncatingIfNeeded: offset &* 8)
            word = word & ~(0xFF << shift) | UInt64(source[offset]) << shift
        }
        return word
    }

    private mutating func appendEscapedByteByByte(_ textBytes: UnsafeBufferPointer<UInt8>) {
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

    /// 0x01 in each byte of a word, and 0x80.
    private static let everyByte: UInt64 = 0x0101_0101_0101_0101
    private static let everyHighBit: UInt64 = 0x8080_8080_8080_8080

    /// Nonzero when one of the word's bytes is, or may start, something escaped or left out: a control character, `"`,
    /// `&`, `'`, `<`, `>`, DEL or the lead byte of U+FFFE and U+FFFF. Each test is the word-wide test for a byte below a
    /// bound or a zero byte (after an exclusive or with the byte looked for), which never misses one; a word it flags
    /// wrongly is only written again byte by byte, the same.
    @inline(__always)
    private static func mayNeedEscaping(_ word: UInt64) -> UInt64 {
        let notWord = ~word
        let control = (word &- everyByte &* 0x20) & notWord
        let quote = hasZeroByte(word ^ (everyByte &* 0x22))
        let ampersandOrApostrophe = hasZeroByte((word & (everyByte &* 0xFE)) ^ (everyByte &* 0x26))
        let angleBracket = hasZeroByte((word & (everyByte &* 0xFD)) ^ (everyByte &* 0x3C))
        let delete = hasZeroByte(word ^ (everyByte &* 0x7F))
        let noncharacterLead = hasZeroByte(word ^ (everyByte &* UInt64(firstByteOfNoncharacter)))
        return (control | quote | ampersandOrApostrophe | angleBracket | delete | noncharacterLead) & everyHighBit
    }

    /// Nonzero, in its high bits, when one of `word`'s bytes is zero.
    @inline(__always)
    private static func hasZeroByte(_ word: UInt64) -> UInt64 {
        (word &- everyByte) & ~word
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
