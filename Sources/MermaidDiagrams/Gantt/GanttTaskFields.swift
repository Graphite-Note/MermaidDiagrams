/**
 * File: GanttTaskFields.swift
 * ---------------------------
 * Layer: Core
 * Description: A Gantt task's data after its colon: its tags, identifier, start and end, split, trimmed and its tags
 *              told on the text's bytes when it is all ASCII, so that only the identifier, start and end become text.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.3
 * Date: 25/11/2026
 */

import Foundation

/// A task's data after its colon, read as Mermaid reads it: comma-separated fields, the first ones tags (`active`,
/// `done`, `crit`, `milestone`, `vert`), then an identifier, a start and an end (three fields), a start and an end
/// (two), or an end (one).
struct GanttTaskFields {
    private(set) var isDone = false
    private(set) var isActive = false
    private(set) var isCritical = false
    private(set) var isMilestone = false
    private(set) var isVerticalMarker = false
    /// The identifier written, or nil when the task has fewer than three fields.
    let identifier: String?
    let startText: String?
    let endText: String

    /// The most fields after the tags: an identifier, a start and an end.
    static let maximumFieldCount = 3

    init(name: String, data: String, line: Int) throws(MermaidDiagramReadError) {
        var tags = TagsOnBytes()
        // Up to the last three fields after the tags (identifier, start, end), in order, and how many fields there are.
        var texts: [String] = []
        var fieldCount: Int
        if let fieldsOnBytes = data.utf8.withContiguousStorageIfAvailable({ bytes in Self.fieldRangesOfASCII(bytes) }) ?? nil {
            tags = fieldsOnBytes.tags
            fieldCount = fieldsOnBytes.count
            if fieldCount <= Self.maximumFieldCount {
                texts = data.utf8.withContiguousStorageIfAvailable { bytes in fieldsOnBytes.texts(in: bytes) } ?? []
            }
        } else {
            // Data with a character past ASCII, split and trimmed as Swift's characters split it.
            texts = Self.trimmedFields(of: data)
            let firstField = texts.prefix { field in Self.tag(field).map { tag in tags.set(tag) } != nil }.count
            texts.removeFirst(firstField)
            fieldCount = texts.count
        }
        guard fieldCount > 0 else { throw .invalidSyntax(line: line, problem: .taskWithoutEnd(task: name)) }
        guard fieldCount <= Self.maximumFieldCount else { throw .invalidSyntax(line: line, problem: .taskWithTooManyFields(task: name)) }
        isDone = tags.isDone
        isActive = tags.isActive
        isCritical = tags.isCritical
        isMilestone = tags.isMilestone
        isVerticalMarker = tags.isVerticalMarker
        identifier = texts.count == Self.maximumFieldCount ? texts[0] : nil
        startText = texts.count > 1 ? texts[texts.count - 2] : nil
        endText = texts[texts.count - 1]
    }

    /// The tags that open a task's data, told on their bytes.
    private struct TagsOnBytes {
        var isDone = false
        var isActive = false
        var isCritical = false
        var isMilestone = false
        var isVerticalMarker = false

        mutating func set(_ tag: Tag) {
            switch tag {
            case .active: isActive = true
            case .done: isDone = true
            case .critical: isCritical = true
            case .milestone: isMilestone = true
            case .verticalMarker: isVerticalMarker = true
            }
        }
    }

    /// An ASCII task's tags and the trimmed ranges of the fields after them: the first three kept, without a list, and
    /// how many there are.
    private struct FieldRangesOnBytes {
        var tags = TagsOnBytes()
        var first = 0..<0
        var second = 0..<0
        var third = 0..<0
        var count = 0

        mutating func append(_ range: Range<Int>) {
            switch count {
            case 0: first = range
            case 1: second = range
            case 2: third = range
            default: break
            }
            count += 1
        }

        /// The fields' texts, for at most three fields.
        func texts(in bytes: UnsafeBufferPointer<UInt8>) -> [String] {
            [first, second, third].prefix(count).map { range in String(decoding: UnsafeBufferPointer(rebasing: bytes[range]), as: UTF8.self) }
        }
    }

    /// The fields of data all in ASCII, split at its commas, trimmed and the leading tags told on its bytes, or nil for
    /// data with a byte past ASCII, which a mark may join to a comma.
    private static func fieldRangesOfASCII(_ bytes: UnsafeBufferPointer<UInt8>) -> FieldRangesOnBytes? {
        var combined: UInt8 = 0
        for byte in bytes { combined |= byte }
        guard combined < 0x80 else { return nil }
        var result = FieldRangesOnBytes()
        var isReadingTags = true
        var fieldStart = 0
        for index in 0...bytes.count where index == bytes.count || bytes[index] == MermaidByte.comma {
            var start = fieldStart
            var end = index
            fieldStart = index + 1
            while start < end, isASCIIWhitespace(bytes[start]) { start += 1 }
            while start < end, isASCIIWhitespace(bytes[end - 1]) { end -= 1 }
            if isReadingTags, let tag = tag(UnsafeBufferPointer(rebasing: bytes[start..<end])) {
                result.tags.set(tag)
                continue
            }
            isReadingTags = false
            result.append(start..<end)
        }
        return result
    }

    /// The data's comma-separated fields, each without the white space and line breaks at its ends. A comma is a
    /// character of its own unless a mark joins it: in text all in ASCII each byte is one, so the bytes are split;
    /// other text is split by characters.
    private static func trimmedFields(of data: String) -> [String] {
        let bytes = data.utf8
        var isASCII = true
        var commaCount = 0
        for byte in bytes {
            if byte >= 0x80 { isASCII = false }
            if byte == MermaidByte.comma { commaCount += 1 }
        }
        guard isASCII else {
            return data.split(separator: ",", omittingEmptySubsequences: false).map { field in
                FoundationTextOnBytes.trimmed(String(field), includingLineBreaks: true)
            }
        }
        var fields: [String] = []
        fields.reserveCapacity(commaCount + 1)
        var fieldStart = bytes.startIndex
        var index = bytes.startIndex
        while true {
            if index == bytes.endIndex || bytes[index] == MermaidByte.comma {
                var start = fieldStart
                var end = index
                while start < end, isASCIIWhitespace(bytes[start]) { start = bytes.index(after: start) }
                while start < end, isASCIIWhitespace(bytes[bytes.index(before: end)]) { end = bytes.index(before: end) }
                fields.append(String(Substring(bytes[start..<end])))
                if index == bytes.endIndex { break }
                fieldStart = bytes.index(after: index)
            }
            index = bytes.index(after: index)
        }
        return fields
    }

    /// The ASCII members of Foundation's `.whitespacesAndNewlines`: the space, and the tab through the carriage return.
    @inline(__always)
    private static func isASCIIWhitespace(_ byte: UInt8) -> Bool {
        byte == MermaidByte.space || (byte >= MermaidByte.tab && byte <= MermaidByte.carriageReturn)
    }

    /// A tag that can open a task's data.
    private enum Tag {
        case active, done, critical, milestone, verticalMarker
    }

    /// The tag a trimmed field of ASCII bytes is, or nil.
    private static func tag(_ field: UnsafeBufferPointer<UInt8>) -> Tag? {
        switch field.count {
        case 4 where field.elementsEqual(doneBytes): .done
        case 4 where field.elementsEqual(critBytes): .critical
        case 4 where field.elementsEqual(vertBytes): .verticalMarker
        case 6 where field.elementsEqual(activeBytes): .active
        case 9 where field.elementsEqual(milestoneBytes): .milestone
        default: nil
        }
    }

    private static let activeBytes = Array("active".utf8)
    private static let doneBytes = Array("done".utf8)
    private static let critBytes = Array("crit".utf8)
    private static let milestoneBytes = Array("milestone".utf8)
    private static let vertBytes = Array("vert".utf8)

    /// The tag a trimmed field is, or nil.
    private static func tag(_ field: String) -> Tag? {
        switch field {
        case "active": .active
        case "done": .done
        case "crit": .critical
        case "milestone": .milestone
        case "vert": .verticalMarker
        default: nil
        }
    }
}
