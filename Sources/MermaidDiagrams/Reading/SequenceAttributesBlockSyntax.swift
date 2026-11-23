/**
 * File: SequenceAttributesBlockSyntax.swift
 * -----------------------------------------
 * Layer: Core
 * Description: Reads YAML's block mappings, block lists and block scalars, and a whole YAML text, as Pele's small YAML
 *              reader does, for a sequence participant's attributes written over several lines.
 *
 * Authors: Bahey Shalash
 * Version: 0.6
 * Date: 23/11/2026
 */

import Foundation

/// YAML's block collections, line by line, as Pele's reader reads them (`src/util/yaml.ts`): a mapping's keys at one
/// indentation, deeper lines its values, `- ` items of a list, `|` and `>` scalars, and flow values that may run over
/// several lines. Collections nest at most `SequenceAttributesFlowSyntax.maximumDepth` deep. The text is read from its
/// UTF-8 bytes, each line a range of them; a line the reader writes again (a list item's mapping) is added after them.
struct SequenceAttributesBlockSyntax {
    typealias Text = [Unicode.Scalar]

    var bytes: [UInt8]
    var lines: [Range<Int>]
    var lineIndex = 0

    /// The value a whole YAML text holds, as a participant's attributes are read.
    static func value(of source: String) throws(SequenceAttributesYAMLFailure) -> SequenceAttributeValue {
        try value(of: Array(source.utf8))
    }

    /// The value a whole YAML text, `source`'s UTF-8 bytes, holds: a flow collection when it is one, else a block value
    /// with nothing after it but blank lines, comments or `...`.
    static func value<Value: MermaidYAMLValue>(of source: [UInt8], as _: Value.Type = Value.self) throws(SequenceAttributesYAMLFailure) -> Value {
        let content = YAMLBytes.trimmedBounds(in: source, source.indices)
        if !content.isEmpty, source[content.lowerBound] == YAMLBytes.openingBrace || source[content.lowerBound] == YAMLBytes.openingBracket {
            do {
                let (value, end): (Value, Int) = try SequenceAttributesFlowSyntax.value(in: source, within: content, at: content.lowerBound,
                                                                                        stops: .none)
                if SequenceAttributesFlowSyntax.skipSpaceAndComments(in: source, within: content, from: end) == content.upperBound { return value }
            } catch {
                throw .invalid
            }
        }
        var reader = SequenceAttributesBlockSyntax(text: source)
        let value: Value
        do { value = try reader.block(minimumIndent: 0, depth: 0) } catch { throw .invalid }
        reader.skipBlankLines()
        if reader.lineIndex < reader.lines.count, !reader.bytes[YAMLBytes.trimmedBounds(in: reader.bytes, reader.lines[reader.lineIndex])]
            .elementsEqual(Self.documentEnd) { throw .invalid }
        return value
    }

    /// The reader of `text` at its first line, its lines split at line feeds. A text with carriage returns, which no
    /// diagram's preprocessed text holds, has them made line feeds through Foundation and its lines split as Swift's
    /// characters, as Pele's port first read every text: Foundation's search leaves a carriage return that a combining
    /// mark follows, and a carriage return and a line feed are one character.
    init(text: [UInt8]) {
        guard MermaidPreprocessing.firstIndex(of: YAMLBytes.carriageReturn, in: text, from: 0) != nil else {
            bytes = text
            var lineBreakCount = 0
            for byte in text where byte == YAMLBytes.newline { lineBreakCount += 1 }
            var lines: [Range<Int>] = []
            lines.reserveCapacity(lineBreakCount + 1)
            var start = 0
            while let lineBreak = MermaidPreprocessing.firstIndex(of: YAMLBytes.newline, in: text, from: start) {
                lines.append(start..<lineBreak)
                start = lineBreak + 1
            }
            lines.append(start..<text.count)
            self.lines = lines
            return
        }
        let normalized = String(decoding: text, as: UTF8.self).replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var bytes: [UInt8] = []
        var lines: [Range<Int>] = []
        for line in MermaidByte.lines(of: normalized) {
            if !lines.isEmpty { bytes.append(YAMLBytes.newline) }
            let start = bytes.count
            bytes.append(contentsOf: line.utf8)
            lines.append(start..<bytes.count)
        }
        self.bytes = bytes
        self.lines = lines
    }

    private static let documentStart = Array("---".utf8)
    private static let documentEnd = Array("...".utf8)

    /// Moves past empty lines, comment lines and `---`.
    mutating func skipBlankLines() {
        while lineIndex < lines.count {
            let content = YAMLBytes.trimmedBounds(in: bytes, lines[lineIndex])
            if !content.isEmpty, bytes[content.lowerBound] != YAMLBytes.hash, !bytes[content].elementsEqual(Self.documentStart) { break }
            lineIndex += 1
        }
    }

    /// The current line's indentation in spaces; a tab there is invalid.
    func indent() throws(SequenceAttributesYAMLFailure) -> Int {
        let line = lines[lineIndex]
        var end = line.lowerBound
        while end < line.upperBound, bytes[end] == YAMLBytes.space { end += 1 }
        if end < line.upperBound, bytes[end] == YAMLBytes.tab { throw .invalid }
        return end - line.lowerBound
    }

    /// The current line after its first `indent` bytes, spaces.
    private func currentLine(after indent: Int) -> Range<Int> {
        (lines[lineIndex].lowerBound + indent)..<lines[lineIndex].upperBound
    }

    /// The block value starting at the current line, when it is indented at least `minimumIndent`; null otherwise.
    mutating func block<Value: MermaidYAMLValue>(minimumIndent: Int, depth: Int) throws(SequenceAttributesYAMLFailure) -> Value {
        guard depth <= SequenceAttributesFlowSyntax.maximumDepth else { throw .invalid }
        skipBlankLines()
        guard lineIndex < lines.count else { return .null }
        let indent = try indent()
        guard indent >= minimumIndent else { return .null }
        let line = currentLine(after: indent)
        if isListItem(line) { return try list(indent: indent, depth: depth) }
        guard splitKey(line) != nil else {
            lineIndex += 1
            return try inlineValue(YAMLBytes.trimmedBounds(in: bytes, line), indent: indent - 1)
        }
        return try mapping(indent: indent, depth: depth)
    }

    /// `- item` lines at `indent`: an item on its own line below, a mapping started on the item's line, or a value.
    private mutating func list<Value: MermaidYAMLValue>(indent: Int, depth: Int) throws(SequenceAttributesYAMLFailure) -> Value {
        var items: [Value] = []
        while lineIndex < lines.count {
            skipBlankLines()
            guard lineIndex < lines.count, try self.indent() == indent else { break }
            let current = currentLine(after: indent)
            guard isListItem(current) else { break }
            let rest = (current.lowerBound + 1)..<current.upperBound
            let body = YAMLBytes.trimmedBounds(in: bytes, rest.lowerBound..<commentStart(in: rest))
            if body.isEmpty {
                lineIndex += 1
                items.append(try block(minimumIndent: indent + 1, depth: depth + 1))
            } else if splitKey(body) != nil {
                // The item's line is read again as the mapping's first line, its dash and the blanks after it spaces.
                let leading = YAMLBytes.leadingWhitespace(in: bytes, rest, orByteOrderMark: false)
                let written = Array(repeating: YAMLBytes.space, count: indent + leading.scalarCount + 1) + bytes[leading.end..<rest.upperBound]
                lines[lineIndex] = bytes.count..<(bytes.count + written.count)
                bytes.append(contentsOf: written)
                items.append(try block(minimumIndent: indent + leading.scalarCount + 1, depth: depth + 1))
            } else {
                lineIndex += 1
                items.append(try inlineValue(YAMLBytes.trimmedBounds(in: bytes, rest), indent: indent))
            }
        }
        return .list(items)
    }

    /// `key: value` lines at `indent`; a key with no value on its line takes the deeper block below it, or null.
    private mutating func mapping<Value: MermaidYAMLValue>(indent: Int, depth: Int) throws(SequenceAttributesYAMLFailure) -> Value {
        var entries: [String: Value] = [:]
        while lineIndex < lines.count {
            skipBlankLines()
            guard lineIndex < lines.count else { break }
            let lineIndent = try self.indent()
            if lineIndent < indent { break }
            guard lineIndent == indent else { throw .invalid }
            let current = currentLine(after: indent)
            guard let (key, valueStart) = splitKey(current) else { throw .invalid }
            let keyText = if let plain = plainKeyText(key) { plain } else {
                try SequenceAttributesFlowSyntax.value(in: bytes, within: key, at: key.lowerBound, stops: .none,
                                                       as: SequenceAttributeValue.self).0.javaScriptText
            }
            let rest = valueStart..<current.upperBound
            lineIndex += 1
            if isBlankBeforeComment(rest) {
                entries[keyText] = try valueBelow(keyIndent: indent, depth: depth)
            } else {
                entries[keyText] = try inlineValue(YAMLBytes.trimmedBounds(in: bytes, rest), indent: indent)
            }
        }
        return .mapping(entries)
    }

    /// The block under a key without a value on its line: deeper lines, or a list at the key's indentation.
    private mutating func valueBelow<Value: MermaidYAMLValue>(keyIndent: Int, depth: Int) throws(SequenceAttributesYAMLFailure) -> Value {
        skipBlankLines()
        guard lineIndex < lines.count else { return .null }
        let next = try indent()
        let isList = isListItem(currentLine(after: next))
        guard next > keyIndent || (isList && next == keyIndent) else { return .null }
        return try block(minimumIndent: isList ? keyIndent : keyIndent + 1, depth: depth + 1)
    }

    /// Whether the line is a list item: `-` alone, or `-` and a space.
    func isListItem(_ line: Range<Int>) -> Bool {
        guard !line.isEmpty, bytes[line.lowerBound] == YAMLBytes.hyphen else { return false }
        return line.count == 1 || bytes[line.lowerBound + 1] == YAMLBytes.space
    }
}
