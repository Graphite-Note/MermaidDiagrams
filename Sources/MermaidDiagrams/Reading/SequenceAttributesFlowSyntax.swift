/**
 * File: SequenceAttributesFlowSyntax.swift
 * ----------------------------------------
 * Layer: Core
 * Description: Reads YAML's flow values (mappings in braces, lists in brackets, quoted and plain scalars) as Pele's
 *              small YAML reader does, for a sequence participant's attributes.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 23/11/2026
 */

/// YAML's flow values, read from UTF-8 bytes as Pele's reader reads them (`src/util/yaml.ts`): entries of a flow
/// collection separated by exactly one comma, comments after a space, plain scalars of the JSON schema, double-quoted
/// escapes, single quotes doubled, line breaks folded. Collections nest at most `maximumDepth` deep. A text is the bytes
/// of `bounds` in an array of bytes, so that a line is read where it stands, without a copy.
enum SequenceAttributesFlowSyntax {
    typealias Text = [Unicode.Scalar]

    static let maximumDepth = 64

    /// The bytes that end a plain scalar: ASCII ones, as YAML's flow indicators are.
    typealias Stops = YAMLBytes.ASCIISet

    /// What ends a plain scalar: a mapping's key, a list's item, a mapping's value in a flow collection (a colon only
    /// when a space, a comma, a bracket or the end follows it).
    private static let mappingKeyStops = Stops([":", ",", "}"])
    private static let listItemStops = Stops([",", "]"])
    private static let mappingValueStops = Stops([",", "}"])

    /// The value starting at scalar `position` of `text` and the scalar position after it, read from the text's bytes.
    static func value(in text: Text, at position: Int, stops: [Unicode.Scalar]) throws(SequenceAttributesYAMLFailure) -> (SequenceAttributeValue, Int) {
        let bytes = Array(UnicodeScalarText.string(text).utf8)
        let start = YAMLBytes.passingScalars(position, in: bytes, from: 0, end: bytes.count)
        let (value, end) = try value(in: bytes, within: 0..<bytes.count, at: start, stops: Stops(stops), as: SequenceAttributeValue.self)
        return (value, String(decoding: bytes[..<end], as: UTF8.self).unicodeScalars.count)
    }

    /// The value starting at `position` of the text `bounds` holds and the position after it. Reading stops a plain
    /// scalar at any of `stops` (a colon only when a space, a comma, a bracket or the end follows it).
    static func value<Value: MermaidYAMLValue>(in bytes: [UInt8], within bounds: Range<Int>, at position: Int, stops: Stops, depth: Int = 0,
                                               as _: Value.Type = Value.self) throws(SequenceAttributesYAMLFailure) -> (Value, Int) {
        guard depth <= maximumDepth else { throw .invalid }
        let start = skipSpaceAndComments(in: bytes, within: bounds, from: position)
        guard start < bounds.upperBound else { return (plainScalar(in: bytes, within: bounds, from: start, stops: stops).value, start) }
        switch bytes[start] {
        case YAMLBytes.openingBrace: return try mappingCollection(in: bytes, within: bounds, from: start, depth: depth)
        case YAMLBytes.openingBracket: return try listCollection(in: bytes, within: bounds, from: start, depth: depth)
        case YAMLBytes.quotationMark: return try doubleQuoted(in: bytes, within: bounds, from: start)
        case YAMLBytes.apostrophe: return try singleQuoted(in: bytes, within: bounds, from: start)
        default: return plainScalar(in: bytes, within: bounds, from: start, stops: stops)
        }
    }

    /// Moves past spaces, tabs, line breaks and comments (a `#` at the start or after white space, to the line's end).
    static func skipSpaceAndComments(in bytes: [UInt8], within bounds: Range<Int>, from position: Int) -> Int {
        var position = position
        while position < bounds.upperBound {
            let byte = bytes[position]
            if byte == YAMLBytes.space || byte == YAMLBytes.newline || byte == YAMLBytes.tab || byte == YAMLBytes.carriageReturn {
                position += 1
            } else if byte == YAMLBytes.hash, position == bounds.lowerBound
                        || YAMLBytes.whitespaceLength(in: bytes, endingAt: position, from: bounds.lowerBound) > 0 {
                position = YAMLBytes.firstIndex(of: YAMLBytes.newline, in: bytes, position..<bounds.upperBound)
            } else {
                break
            }
        }
        return position
    }

    /// `{ key: value, … }`: each key read as a participant's attribute is, and written as JavaScript writes it.
    private static func mappingCollection<Value: MermaidYAMLValue>(in bytes: [UInt8], within bounds: Range<Int>, from opening: Int,
                                                                   depth: Int) throws(SequenceAttributesYAMLFailure) -> (Value, Int) {
        var entries: [String: Value] = [:]
        var position = opening + 1
        var isSeparated = true
        while true {
            position = skipSpaceAndComments(in: bytes, within: bounds, from: position)
            guard position < bounds.upperBound else { throw .incomplete }
            if bytes[position] == YAMLBytes.closingBrace { return (.mapping(entries), position + 1) }
            guard isSeparated, bytes[position] != YAMLBytes.comma else { throw .invalid }
            let (key, afterKey) = try value(in: bytes, within: bounds, at: position, stops: mappingKeyStops, depth: depth + 1,
                                            as: SequenceAttributeValue.self)
            position = skipSpaceAndComments(in: bytes, within: bounds, from: afterKey)
            var entryValue = Value.null
            if position < bounds.upperBound, bytes[position] == YAMLBytes.colon {
                (entryValue, position) = try value(in: bytes, within: bounds, at: position + 1, stops: mappingValueStops, depth: depth + 1)
            }
            entries[key.javaScriptText] = entryValue
            position = skipSpaceAndComments(in: bytes, within: bounds, from: position)
            isSeparated = position < bounds.upperBound && bytes[position] == YAMLBytes.comma
            if isSeparated { position += 1 }
        }
    }

    /// `[ value, … ]`.
    private static func listCollection<Value: MermaidYAMLValue>(in bytes: [UInt8], within bounds: Range<Int>, from opening: Int,
                                                                depth: Int) throws(SequenceAttributesYAMLFailure) -> (Value, Int) {
        var items: [Value] = []
        var position = opening + 1
        var isSeparated = true
        while true {
            position = skipSpaceAndComments(in: bytes, within: bounds, from: position)
            guard position < bounds.upperBound else { throw .incomplete }
            if bytes[position] == YAMLBytes.closingBracket { return (.list(items), position + 1) }
            guard isSeparated, bytes[position] != YAMLBytes.comma else { throw .invalid }
            let (item, afterItem): (Value, Int) = try value(in: bytes, within: bounds, at: position, stops: listItemStops, depth: depth + 1)
            items.append(item)
            position = skipSpaceAndComments(in: bytes, within: bounds, from: afterItem)
            isSeparated = position < bounds.upperBound && bytes[position] == YAMLBytes.comma
            if isSeparated { position += 1 }
        }
    }

    private static func doubleQuoted<Value: MermaidYAMLValue>(in bytes: [UInt8], within bounds: Range<Int>,
                                                              from opening: Int) throws(SequenceAttributesYAMLFailure) -> (Value, Int) {
        // A backslash takes the byte after it; the rest of a scalar it escapes is never a quotation mark or a backslash.
        var end = opening + 1
        while end < bounds.upperBound, bytes[end] != YAMLBytes.quotationMark { end += bytes[end] == YAMLBytes.backslash ? 2 : 1 }
        guard end < bounds.upperBound else { throw .incomplete }
        return (.text(try SequenceAttributesScalarSyntax.unescaped(bytes, (opening + 1)..<end)), end + 1)
    }

    private static func singleQuoted<Value: MermaidYAMLValue>(in bytes: [UInt8], within bounds: Range<Int>,
                                                              from opening: Int) throws(SequenceAttributesYAMLFailure) -> (Value, Int) {
        var end = opening + 1
        while end < bounds.upperBound {
            if bytes[end] == YAMLBytes.apostrophe {
                guard end + 1 < bounds.upperBound, bytes[end + 1] == YAMLBytes.apostrophe else { break }
                end += 1
            }
            end += 1
        }
        guard end < bounds.upperBound else { throw .incomplete }
        let folded = folding(bytes, (opening + 1)..<end)
        return (.text(SequenceAttributesScalarSyntax.undoublingApostrophes(folded)), end + 1)
    }

    /// A plain scalar up to a stop or a comment, its line breaks folded, read as the JSON schema reads it.
    private static func plainScalar<Value: MermaidYAMLValue>(in bytes: [UInt8], within bounds: Range<Int>, from start: Int,
                                                             stops: Stops) -> (value: Value, end: Int) {
        var end = start
        while end < bounds.upperBound {
            let byte = bytes[end]
            if stops.contains(byte),
               byte != YAMLBytes.colon || end + 1 >= bounds.upperBound || endsPlainKey(in: bytes, at: end + 1, end: bounds.upperBound) {
                break
            }
            if byte == YAMLBytes.hash, end > start, YAMLBytes.whitespaceLength(in: bytes, endingAt: end, from: start) > 0 {
                let lineEnd = YAMLBytes.firstIndex(of: YAMLBytes.newline, in: bytes, end..<bounds.upperBound)
                return (SequenceAttributesScalarSyntax.scalar(folding(bytes, YAMLBytes.trimmedBounds(in: bytes, start..<end))), lineEnd)
            }
            end += 1
        }
        return (SequenceAttributesScalarSyntax.scalar(folding(bytes, YAMLBytes.trimmedBounds(in: bytes, start..<end))), end)
    }

    /// After a colon, what makes it end a plain key: white space, a comma or a bracket.
    private static func endsPlainKey(in bytes: [UInt8], at index: Int, end: Int) -> Bool {
        let byte = bytes[index]
        return YAMLBytes.isWhitespace(in: bytes, at: index, end: end) || byte == YAMLBytes.comma || byte == YAMLBytes.openingBracket
            || byte == YAMLBytes.closingBracket || byte == YAMLBytes.openingBrace || byte == YAMLBytes.closingBrace
    }

    /// Folds line breaks as YAML does in a flow scalar: blanks around a break go, one break becomes a space, and each
    /// further break stays. The bytes of `range` themselves when it holds no line break.
    static func folding(_ bytes: [UInt8], _ range: Range<Int>) -> ArraySlice<UInt8> {
        let firstBreak = YAMLBytes.firstIndex(of: YAMLBytes.newline, in: bytes, range)
        guard firstBreak < range.upperBound else { return bytes[range] }
        var folded: [UInt8] = []
        folded.reserveCapacity(range.count)
        var breakCount = 0
        var lineStart = range.lowerBound
        var isFirstLine = true
        while true {
            let lineEnd = YAMLBytes.firstIndex(of: YAMLBytes.newline, in: bytes, lineStart..<range.upperBound)
            let isLastLine = lineEnd == range.upperBound
            var start = lineStart
            var end = lineEnd
            if !isFirstLine { while start < end, bytes[start] == YAMLBytes.space || bytes[start] == YAMLBytes.tab { start += 1 } }
            if !isLastLine { while end > start, bytes[end - 1] == YAMLBytes.space || bytes[end - 1] == YAMLBytes.tab { end -= 1 } }
            if !isFirstLine { breakCount += 1 }
            if start < end || isLastLine {
                appendBreaks(breakCount, to: &folded)
                breakCount = 0
                folded.append(contentsOf: bytes[start..<end])
            }
            if isLastLine { break }
            isFirstLine = false
            lineStart = lineEnd + 1
        }
        appendBreaks(breakCount, to: &folded)
        return folded[...]
    }

    /// One folded break as a space, more as all but one of them.
    private static func appendBreaks(_ count: Int, to folded: inout [UInt8]) {
        if count == 1 {
            folded.append(YAMLBytes.space)
        } else if count > 1 {
            folded.append(contentsOf: repeatElement(YAMLBytes.newline, count: count - 1))
        }
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

    static func string<Scalars: Collection>(_ text: Scalars) -> String where Scalars.Element == Unicode.Scalar {
        UnicodeScalarText.string(text)
    }
}
