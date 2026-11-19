/**
 * File: SequenceAttributesBlockSyntax.swift
 * -----------------------------------------
 * Layer: Core
 * Description: Reads YAML's block mappings, block lists and block scalars, and a whole YAML text, as Pele's small YAML
 *              reader does, for a sequence participant's attributes written over several lines.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// YAML's block collections, line by line, as Pele's reader reads them (`src/util/yaml.ts`): a mapping's keys at one
/// indentation, deeper lines its values, `- ` items of a list, `|` and `>` scalars, and flow values that may run over
/// several lines. Collections nest at most `SequenceAttributesFlowSyntax.maximumDepth` deep.
struct SequenceAttributesBlockSyntax {
    typealias Text = [Unicode.Scalar]

    var lines: [Text]
    var lineIndex = 0

    /// The value a whole YAML text holds: a flow collection when it is one, else a block value with nothing after it
    /// but blank lines, comments or `...`.
    static func value(of source: String) throws(SequenceAttributesYAMLFailure) -> SequenceAttributeValue {
        let text = Array(source.unicodeScalars)
        let trimmed = SequenceAttributesFlowSyntax.trimmed(text)
        if let first = trimmed.first, first == "{" || first == "[" {
            do {
                let (value, end) = try SequenceAttributesFlowSyntax.value(in: trimmed, at: 0, stops: "")
                if SequenceAttributesFlowSyntax.skipSpaceAndComments(in: trimmed, from: end) == trimmed.count { return value }
            } catch {
                throw .invalid
            }
        }
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var reader = SequenceAttributesBlockSyntax(lines: normalized.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            Array(line.unicodeScalars)
        })
        let value: SequenceAttributeValue
        do { value = try reader.block(minimumIndent: 0, depth: 0) } catch { throw .invalid }
        reader.skipBlankLines()
        if reader.lineIndex < reader.lines.count, Self.trimmed(reader.lines[reader.lineIndex]) != Array("...".unicodeScalars) { throw .invalid }
        return value
    }

    /// Moves past empty lines, comment lines and `---`.
    mutating func skipBlankLines() {
        while lineIndex < lines.count {
            let content = Self.trimmed(lines[lineIndex])
            if !content.isEmpty, content[0] != "#", content != Array("---".unicodeScalars) { break }
            lineIndex += 1
        }
    }

    /// The current line's indentation in spaces; a tab there is invalid.
    func indent() throws(SequenceAttributesYAMLFailure) -> Int {
        let line = lines[lineIndex]
        let count = line.prefix { scalar in scalar == " " }.count
        if count < line.count, line[count] == "\t" { throw .invalid }
        return count
    }

    /// The block value starting at the current line, when it is indented at least `minimumIndent`; null otherwise.
    mutating func block(minimumIndent: Int, depth: Int) throws(SequenceAttributesYAMLFailure) -> SequenceAttributeValue {
        guard depth <= SequenceAttributesFlowSyntax.maximumDepth else { throw .invalid }
        skipBlankLines()
        guard lineIndex < lines.count else { return .null }
        let indent = try indent()
        guard indent >= minimumIndent else { return .null }
        let line = Array(lines[lineIndex][indent...])
        if Self.isListItem(line) { return try list(indent: indent, depth: depth) }
        guard Self.splitKey(line) != nil else {
            lineIndex += 1
            return try inlineValue(Self.trimmed(line), indent: indent - 1)
        }
        return try mapping(indent: indent, depth: depth)
    }

    /// `- item` lines at `indent`: an item on its own line below, a mapping started on the item's line, or a value.
    private mutating func list(indent: Int, depth: Int) throws(SequenceAttributesYAMLFailure) -> SequenceAttributeValue {
        var items: [SequenceAttributeValue] = []
        while lineIndex < lines.count {
            skipBlankLines()
            guard lineIndex < lines.count, try self.indent() == indent else { break }
            let current = Array(lines[lineIndex][indent...])
            guard Self.isListItem(current) else { break }
            let rest = Array(current.dropFirst())
            let leading = rest.prefix { scalar in scalar.properties.isWhitespace }.count
            let body = Self.trimmed(Self.withoutComment(rest))
            if body.isEmpty {
                lineIndex += 1
                items.append(try block(minimumIndent: indent + 1, depth: depth + 1))
            } else if Self.splitKey(body) != nil {
                lines[lineIndex] = Array(repeating: " ", count: indent + leading + 1) + rest.dropFirst(leading)
                items.append(try block(minimumIndent: indent + leading + 1, depth: depth + 1))
            } else {
                lineIndex += 1
                items.append(try inlineValue(Self.trimmed(rest), indent: indent))
            }
        }
        return .list(items)
    }

    /// `key: value` lines at `indent`; a key with no value on its line takes the deeper block below it, or null.
    private mutating func mapping(indent: Int, depth: Int) throws(SequenceAttributesYAMLFailure) -> SequenceAttributeValue {
        var entries: [String: SequenceAttributeValue] = [:]
        while lineIndex < lines.count {
            skipBlankLines()
            guard lineIndex < lines.count else { break }
            let lineIndent = try self.indent()
            if lineIndent < indent { break }
            guard lineIndent == indent else { throw .invalid }
            let current = Array(lines[lineIndex][indent...])
            guard let (key, valueStart) = Self.splitKey(current) else { throw .invalid }
            let keyText = try SequenceAttributesFlowSyntax.value(in: key, at: 0, stops: "").0.javaScriptText
            let rest = Array(current[valueStart...])
            lineIndex += 1
            if Self.trimmed(Self.withoutComment(rest)).isEmpty {
                entries[keyText] = try valueBelow(keyIndent: indent, depth: depth)
            } else {
                entries[keyText] = try inlineValue(Self.trimmed(rest), indent: indent)
            }
        }
        return .mapping(entries)
    }

    /// The block under a key without a value on its line: deeper lines, or a list at the key's indentation.
    private mutating func valueBelow(keyIndent: Int, depth: Int) throws(SequenceAttributesYAMLFailure) -> SequenceAttributeValue {
        skipBlankLines()
        guard lineIndex < lines.count else { return .null }
        let next = try indent()
        let isList = Self.isListItem(Array(lines[lineIndex][next...]))
        guard next > keyIndent || (isList && next == keyIndent) else { return .null }
        return try block(minimumIndent: isList ? keyIndent : keyIndent + 1, depth: depth + 1)
    }

    static func isListItem(_ line: Text) -> Bool {
        line == ["-"] || (line.count >= 2 && line[0] == "-" && line[1] == " ")
    }

    static func trimmed(_ text: Text) -> Text {
        SequenceAttributesFlowSyntax.trimmed(text)
    }
}
