/**
 * File: SequenceAttributesFlowSyntax.swift
 * ----------------------------------------
 * Layer: Core
 * Description: Reads YAML's flow values (mappings in braces, lists in brackets, quoted and plain scalars) as Pele's
 *              small YAML reader does, for a sequence participant's attributes.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

/// YAML's flow values, read from Unicode scalars as Pele's reader reads them (`src/util/yaml.ts`): entries of a flow
/// collection separated by exactly one comma, comments after a space, plain scalars of the JSON schema, double-quoted
/// escapes, single quotes doubled, line breaks folded. Collections nest at most `maximumDepth` deep.
enum SequenceAttributesFlowSyntax {
    typealias Text = [Unicode.Scalar]

    static let maximumDepth = 64

    /// The value starting at `position` and the position after it. Reading stops a plain scalar at any of `stops` (a
    /// colon only when a space, a comma, a bracket or the end follows it).
    static func value(in text: Text, at position: Int, stops: String, depth: Int = 0) throws(SequenceAttributesYAMLFailure) -> (SequenceAttributeValue, Int) {
        guard depth <= maximumDepth else { throw .invalid }
        let start = skipSpaceAndComments(in: text, from: position)
        guard start < text.count else { return (plainScalar(in: text, from: start, stops: stops).value, start) }
        switch text[start] {
        case "{": return try collection(in: text, from: start, closing: "}", depth: depth)
        case "[": return try collection(in: text, from: start, closing: "]", depth: depth)
        case "\"": return try doubleQuoted(in: text, from: start)
        case "'": return try singleQuoted(in: text, from: start)
        default: return plainScalar(in: text, from: start, stops: stops)
        }
    }

    /// Moves past spaces, tabs, line breaks and comments (a `#` at the start or after white space, to the line's end).
    static func skipSpaceAndComments(in text: Text, from position: Int) -> Int {
        var position = position
        while position < text.count {
            let scalar = text[position]
            if scalar == " " || scalar == "\n" || scalar == "\t" || scalar == "\r" {
                position += 1
            } else if scalar == "#", position == 0 || isWhitespace(text[position - 1]) {
                position = text[position...].firstIndex(of: "\n") ?? text.count
            } else {
                break
            }
        }
        return position
    }

    /// `{ key: value, … }` or `[ value, … ]`.
    private static func collection(in text: Text, from opening: Int, closing: Unicode.Scalar,
                                   depth: Int) throws(SequenceAttributesYAMLFailure) -> (SequenceAttributeValue, Int) {
        let isMapping = closing == "}"
        var mapping: [String: SequenceAttributeValue] = [:]
        var items: [SequenceAttributeValue] = []
        var position = opening + 1
        var isSeparated = true
        while true {
            position = skipSpaceAndComments(in: text, from: position)
            guard position < text.count else { throw .incomplete }
            if text[position] == closing { return (isMapping ? .mapping(mapping) : .list(items), position + 1) }
            guard isSeparated, text[position] != "," else { throw .invalid }
            let (first, afterFirst) = try value(in: text, at: position, stops: isMapping ? ":,}" : ",]", depth: depth + 1)
            position = skipSpaceAndComments(in: text, from: afterFirst)
            if isMapping {
                var entryValue = SequenceAttributeValue.null
                if position < text.count, text[position] == ":" {
                    (entryValue, position) = try value(in: text, at: position + 1, stops: ",}", depth: depth + 1)
                }
                mapping[first.javaScriptText] = entryValue
                position = skipSpaceAndComments(in: text, from: position)
            } else {
                items.append(first)
            }
            isSeparated = position < text.count && text[position] == ","
            if isSeparated { position += 1 }
        }
    }

    private static func doubleQuoted(in text: Text, from opening: Int) throws(SequenceAttributesYAMLFailure) -> (SequenceAttributeValue, Int) {
        var end = opening + 1
        while end < text.count, text[end] != "\"" { end += text[end] == "\\" ? 2 : 1 }
        guard end < text.count else { throw .incomplete }
        return (.text(try unescaped(Array(text[(opening + 1)..<end]))), end + 1)
    }

    private static func singleQuoted(in text: Text, from opening: Int) throws(SequenceAttributesYAMLFailure) -> (SequenceAttributeValue, Int) {
        var end = opening + 1
        while end < text.count {
            if text[end] == "'" {
                guard end + 1 < text.count, text[end + 1] == "'" else { break }
                end += 1
            }
            end += 1
        }
        guard end < text.count else { throw .incomplete }
        let folded = folding(Array(text[(opening + 1)..<end]))
        return (.text(string(folded).replacingOccurrences(of: "''", with: "'")), end + 1)
    }

    /// A plain scalar up to a stop or a comment, its line breaks folded, read as the JSON schema reads it.
    private static func plainScalar(in text: Text, from start: Int, stops: String) -> (value: SequenceAttributeValue, end: Int) {
        let stopScalars = Array(stops.unicodeScalars)
        var end = start
        while end < text.count {
            let scalar = text[end]
            if stopScalars.contains(scalar), scalar != ":" || end + 1 >= text.count || endsPlainKey(text[end + 1]) { break }
            if scalar == "#", end > start, isWhitespace(text[end - 1]) {
                let lineEnd = text[end...].firstIndex(of: "\n") ?? text.count
                return (SequenceAttributesScalarSyntax.scalar(string(folding(trimmed(text[start..<end])))), lineEnd)
            }
            end += 1
        }
        return (SequenceAttributesScalarSyntax.scalar(string(folding(trimmed(text[start..<end])))), end)
    }

    /// After a colon, what makes it end a plain key: white space, a comma or a bracket.
    private static func endsPlainKey(_ scalar: Unicode.Scalar) -> Bool {
        isWhitespace(scalar) || scalar == "," || scalar == "[" || scalar == "]" || scalar == "{" || scalar == "}"
    }

    /// A double-quoted scalar's body with its escapes replaced; an escaped line break and the blanks after it go first.
    private static func unescaped(_ body: Text) throws(SequenceAttributesYAMLFailure) -> String {
        guard body.contains("\\") else { return string(folding(body)) }
        let text = folding(SequenceAttributesScalarSyntax.removingEscapedLineBreaks(body))
        var result = String.UnicodeScalarView()
        var index = 0
        while index < text.count {
            guard text[index] == "\\" else {
                result.append(text[index])
                index += 1
                continue
            }
            index += 1
            guard index < text.count else { throw .invalid }
            let (scalars, length) = try SequenceAttributesScalarSyntax.escape(text, at: index)
            result.append(contentsOf: scalars)
            index += length
        }
        return String(result)
    }

    /// Folds line breaks as YAML does in a flow scalar: blanks around a break go, one break becomes a space, and each
    /// further break stays.
    static func folding(_ text: Text) -> Text {
        guard text.contains("\n") else { return text }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var trimmedLines: [Text] = []
        for (index, line) in lines.enumerated() {
            var slice = line[...]
            if index > 0 { while let first = slice.first, first == " " || first == "\t" { slice = slice.dropFirst() } }
            if index < lines.count - 1 { while let last = slice.last, last == " " || last == "\t" { slice = slice.dropLast() } }
            trimmedLines.append(Array(slice))
        }
        var folded: Text = []
        var breakCount = 0
        for (index, line) in trimmedLines.enumerated() {
            if index > 0 { breakCount += 1 }
            if line.isEmpty, index < trimmedLines.count - 1 { continue }
            if breakCount == 1 { folded.append(" ") } else if breakCount > 1 { folded += Array(repeating: "\n", count: breakCount - 1) }
            breakCount = 0
            folded += line
        }
        if breakCount == 1 { folded.append(" ") } else if breakCount > 1 { folded += Array(repeating: "\n", count: breakCount - 1) }
        return folded
    }

    /// The text without white space at either end, as JavaScript's `trim` takes it.
    static func trimmed<Scalars: BidirectionalCollection>(_ text: Scalars) -> Text where Scalars.Element == Unicode.Scalar {
        Array(text[trimmedBounds(text)])
    }

    /// Where the text is once trimmed, without copying it.
    static func trimmedBounds<Scalars: BidirectionalCollection>(_ text: Scalars) -> Range<Scalars.Index> where Scalars.Element == Unicode.Scalar {
        var start = text.startIndex
        var end = text.endIndex
        while start < end, isTrimmed(text[start]) { text.formIndex(after: &start) }
        while start < end, case let before = text.index(before: end), isTrimmed(text[before]) { end = before }
        return start..<end
    }

    /// What JavaScript's `trim` takes off: white space and the byte order mark.
    @inline(__always)
    static func isTrimmed(_ scalar: Unicode.Scalar) -> Bool {
        isWhitespace(scalar) || scalar == "\u{FEFF}"
    }

    /// Unicode's White_Space property, read without the property tables for ASCII, which is most of a YAML text.
    @inline(__always)
    static func isWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value < 0x80 ? scalar.value == 0x20 || (0x09...0x0D).contains(scalar.value) : scalar.properties.isWhitespace
    }

    static func string<Scalars: Sequence>(_ text: Scalars) -> String where Scalars.Element == Unicode.Scalar {
        UnicodeScalarText.string(text)
    }
}
