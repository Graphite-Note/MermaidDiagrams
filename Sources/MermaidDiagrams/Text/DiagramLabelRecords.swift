/**
 * File: DiagramLabelRecords.swift
 * -------------------------------
 * Layer: Core
 * Description: The small records a decoded label is kept as in a text storage: its lines and their spans as byte
 *              ranges, and how Pele reads it, each a few numbers that copy without reference counting.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

/// A line of a decoded label in a `DiagramTextStorage`: its bytes and, when the label has emphasis, its spans.
struct DiagramLabelLineRecord {
    var start: Int32
    var end: Int32
    var firstSpan: Int32
    var spanCount: Int32
}

/// A span of a decoded line in one emphasis: its bytes and its emphasis.
struct DiagramLabelSpanRecord {
    var start: Int32
    var end: Int32
    var style: DiagramTextStyle
}

/// How a label is kept and how Pele reads it.
struct DiagramLabelFlags: OptionSet, Hashable, Sendable {
    let rawValue: UInt8

    /// The label is one line without spans, kept as its byte range: no line record.
    static let isOneLine = DiagramLabelFlags(rawValue: 1 << 0)
    /// The label's lines have spans, one of them with an emphasis.
    static let hasSpans = DiagramLabelFlags(rawValue: 1 << 1)
    /// The label is one line Pele reads without markup: wrapped only at a plain space, a Chinese or Japanese character or
    /// a break hint.
    static let isReadWithoutMarkup = DiagramLabelFlags(rawValue: 1 << 2)
}

/// Where a label's lines are in its storage: a label of one line without spans holds its bytes' range (`first` to
/// `end`); any other label's lines are `lineCount` line records from the record at `first`.
struct DiagramLabelRecord: Sendable {
    var first: Int32
    var end: Int32
    var lineCount: Int32
    var flags: DiagramLabelFlags
}
