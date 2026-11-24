/**
 * File: DiagramTextRecords.swift
 * ------------------------------
 * Layer: Core
 * Description: The small records text is measured into: a font face by its index, a face's advances by byte, a
 *              measurer that measures UTF-8 bytes, and the line, run and block records of measured text, each a few
 *              numbers that copy without reference counting.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics

/// A font a diagram's text is measured in, as its place in `DiagramFontFaceRegistry`: copying it retains nothing.
/// Negative for a face past the registry's room, which is measured through a bounded cache of faces instead.
struct DiagramFontFaceIndex: Hashable, Sendable {
    let rawValue: Int32

    /// No face kept in the registry.
    static let unregistered = DiagramFontFaceIndex(rawValue: -1)

    var isRegistered: Bool { rawValue >= 0 }
}

/// The advances of a face by byte, 256 of them: those of printable ASCII, space (32) to tilde (126), and zero for every
/// other byte. The table is made once per face and never freed, so a copy is a pointer.
struct DiagramFontAdvances: @unchecked Sendable {
    /// The advance of each byte.
    let byByte: UnsafePointer<CGFloat>
    /// Whether every advance is a binary fraction of at most 20 bits below 1,024 points: any sum of fewer than 2^22 of
    /// them is then exact in a Double, so that widths added in any order, or continued and taken apart, are the same sum
    /// to the bit.
    let isExactlySummable: Bool

    static let firstPrintableASCII: UInt8 = 32
    static let lastPrintableASCII: UInt8 = 126

    static func isPrintable(_ byte: UInt8) -> Bool {
        byte >= firstPrintableASCII && byte <= lastPrintableASCII
    }

    /// `width` with each byte's advance added, in order; every byte is printable ASCII.
    @inline(__always)
    func width<Bytes: Sequence<UInt8>>(continuing width: CGFloat, over bytes: Bytes) -> CGFloat {
        var width = width
        for byte in bytes { width += byByte[Int(byte)] }
        return width
    }

    /// The width of `bytes[start..<end]` added up from the first byte, or nil when a byte is not printable ASCII.
    @inline(__always)
    func width(of bytes: UnsafePointer<UInt8>, from start: Int, to end: Int) -> CGFloat? {
        var width: CGFloat = 0
        var index = start
        while index < end {
            let byte = bytes[index]
            guard Self.isPrintable(byte) else { return nil }
            width += byByte[Int(byte)]
            index += 1
        }
        return width
    }
}

/// A measurer that measures UTF-8 bytes as well as Strings, in its own font or with an emphasis added: Core Text's adds
/// up printable ASCII from its face's table and looks other text up by its bytes, without making a String; any other
/// measurer (the fixed widths of tests) measures the String the bytes make.
protocol DiagramByteTextMeasuring: DiagramTextMeasuring {
    /// The width of `bytes`, valid UTF-8, on one line in the measurer's font with `style` added.
    func width(ofUTF8 bytes: UnsafeBufferPointer<UInt8>, style: DiagramTextStyle) -> CGFloat
    /// The advances the measurer of `style` adds up for printable ASCII, or nil when it measures whole texts only.
    func advances(of style: DiagramTextStyle) -> DiagramFontAdvances?
}

/// A line of measured text in a `DiagramTextStorage`: its bytes, its runs when the text has emphasis, and its width.
struct DiagramTextLineRecord {
    var start: Int32
    var end: Int32
    var firstRun: Int32
    var runCount: Int32
    var width: CGFloat
}

/// A run of a measured line, in one emphasis: its bytes, its width in that emphasis, and the emphasis.
struct DiagramTextRunRecord {
    var start: Int32
    var end: Int32
    var width: CGFloat
    var style: DiagramTextStyle
}

/// Where a block's measured lines are in its storage. A block of one line without emphasis, most blocks, holds its line
/// itself (`isOneLine`): `first` and `end` are the line's bytes and `widestLineWidth` its width. Any other block's
/// lines are `lineCount` line records from the record at `first`.
struct DiagramTextRecord: Equatable, Sendable {
    var first: Int32
    var end: Int32
    var lineCount: Int32
    var isOneLine: Bool
    var hasEmphasis: Bool
    var widestLineWidth: CGFloat

    /// No lines.
    static let empty = DiagramTextRecord(first: 0, end: 0, lineCount: 0, isOneLine: false, hasEmphasis: false, widestLineWidth: 0)
}
