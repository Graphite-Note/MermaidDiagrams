/**
 * File: MermaidSourceText.swift
 * -----------------------------
 * Layer: Core
 * Description: The text a diagram is read from, owned once (the caller's String when preprocessing changed no byte,
 *              else the bytes preprocessing made), and ranges of its UTF-8 bytes that models keep instead of Strings.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

/// A range of the UTF-8 bytes of a diagram's text (`MermaidSourceText`): eight bytes, where a String is sixteen and may
/// own a buffer.
struct MermaidTextRange: Equatable, Hashable, Sendable {
    var start: Int32
    var end: Int32

    init(start: Int, end: Int) {
        self.start = Int32(truncatingIfNeeded: start)
        self.end = Int32(truncatingIfNeeded: end)
    }

    static let empty = MermaidTextRange(start: 0, end: 0)

    var count: Int { Int(end - start) }
    var isEmpty: Bool { end <= start }
    var lowerBound: Int { Int(start) }
    var upperBound: Int { Int(end) }
}

/// The text a diagram is read from: the String handed to the reader when no preprocessing pass changed a byte, kept as
/// it is and read through its own UTF-8 storage, or the bytes the passes made. Models index it with `MermaidTextRange`s
/// and make Strings of it only when asked.
struct MermaidSourceText: Sendable {
    private enum Storage: Sendable {
        case string(String)
        case bytes([UInt8])
    }

    private let storage: Storage
    /// The number of UTF-8 bytes.
    let count: Int

    /// `string`'s bytes, made contiguous once so that every later reading borrows them without copying.
    init(string: String) {
        var contiguous = string
        contiguous.makeContiguousUTF8()
        storage = .string(contiguous)
        count = contiguous.utf8.count
    }

    /// `string`, whose UTF-8 bytes the caller made contiguous (`makeContiguousUTF8`).
    init(contiguousString string: String) {
        storage = .string(string)
        count = string.utf8.count
    }

    init(bytes: [UInt8]) {
        storage = .bytes(bytes)
        count = bytes.count
    }

    /// Calls `body` with the text's bytes, borrowed: they are valid only inside `body`.
    func withBytes<Result>(_ body: (UnsafeBufferPointer<UInt8>) -> Result) -> Result {
        switch storage {
        case .bytes(let bytes): return bytes.withUnsafeBufferPointer(body)
        case .string(let string):
            if let result = string.utf8.withContiguousStorageIfAvailable(body) { return result }
            return Array(string.utf8).withUnsafeBufferPointer(body)
        }
    }

    /// The text of `range`.
    func string(_ range: MermaidTextRange) -> String {
        withBytes { bytes in String(decoding: UnsafeBufferPointer(rebasing: bytes[range.lowerBound..<range.upperBound]), as: UTF8.self) }
    }

    /// The whole text as a String: the caller's own when no pass changed it.
    var string: String {
        switch storage {
        case .string(let string): string
        case .bytes(let bytes): String(decoding: bytes, as: UTF8.self)
        }
    }

    /// A copy of the bytes for the readers that read an array (`MermaidTextCursor`); the bytes themselves, uncopied,
    /// when the text is the bytes preprocessing made.
    var legacyBytes: [UInt8] {
        switch storage {
        case .bytes(let bytes): bytes
        case .string(let string): Array(string.utf8)
        }
    }

    /// The 1-based line of `offset`: one more than the line breaks before it, as `MermaidTextCursor.line` counts them.
    func line(at offset: Int) -> Int {
        withBytes { bytes in Self.line(at: offset, in: bytes) }
    }

    /// The 1-based line of `offset` in `bytes`, line feeds counted sixteen bytes at a time.
    static func line(at offset: Int, in bytes: UnsafeBufferPointer<UInt8>) -> Int {
        let end = min(max(offset, 0), bytes.count)
        var line = 1
        var index = 0
        if let base = bytes.baseAddress {
            let raw = UnsafeRawPointer(base)
            let newlines = SIMD16<UInt8>(repeating: MermaidByte.newline)
            while index + 16 <= end {
                let chunk = raw.loadUnaligned(fromByteOffset: index, as: SIMD16<UInt8>.self)
                line += Int(SIMD16<UInt8>(repeating: 0).replacing(with: 1, where: chunk .== newlines).wrappedSum())
                index += 16
            }
        }
        while index < end {
            if bytes[index] == MermaidByte.newline { line += 1 }
            index += 1
        }
        return line
    }

    /// The first characters at `position`, for an error that shows what could not be read: at most `maximumBytes`, not
    /// past the line, never a character cut in two (`MermaidTextCursor.excerpt`).
    static func excerpt(at position: Int, in bytes: UnsafeBufferPointer<UInt8>, maximumBytes: Int = 24) -> String {
        let start = min(position, bytes.count)
        var end = min(bytes.count, start + maximumBytes)
        if let lineEnd = bytes[start..<end].firstIndex(of: MermaidByte.newline) { end = lineEnd }
        while end < bytes.count, end > start, bytes[end] & 0xC0 == 0x80 { end -= 1 }
        return String(decoding: UnsafeBufferPointer(rebasing: bytes[start..<end]), as: UTF8.self)
    }
}
