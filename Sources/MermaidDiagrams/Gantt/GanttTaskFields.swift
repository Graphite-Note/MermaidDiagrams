/**
 * File: GanttTaskFields.swift
 * ---------------------------
 * Layer: Core
 * Description: A Gantt task's data after its colon: its tags, identifier, start and end, split and trimmed on the
 *              text's bytes when it is all ASCII.
 *
 * Authors: felixchvl
 * Version: 0.2
 * Date: 23/11/2026
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
        var fields = Self.trimmedFields(of: data)
        var firstField = 0
        while firstField < fields.count, let tag = Self.tag(fields[firstField]) {
            switch tag {
            case .active: isActive = true
            case .done: isDone = true
            case .critical: isCritical = true
            case .milestone: isMilestone = true
            case .verticalMarker: isVerticalMarker = true
            }
            firstField += 1
        }
        fields.removeFirst(firstField)
        guard let last = fields.last else { throw .invalidSyntax(line: line, problem: .taskWithoutEnd(task: name)) }
        guard fields.count <= Self.maximumFieldCount else { throw .invalidSyntax(line: line, problem: .taskWithTooManyFields(task: name)) }
        identifier = fields.count == Self.maximumFieldCount ? fields[0] : nil
        startText = fields.count > 1 ? fields[fields.count - 2] : nil
        endText = last
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
