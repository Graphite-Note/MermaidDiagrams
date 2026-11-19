/**
 * File: MermaidConfigurationOptions.swift
 * ---------------------------------------
 * Layer: Core
 * Description: The options a diagram's front matter and its `%%{init: …}%%` directives give its type.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.3
 * Date: 19/11/2026
 */

import Foundation

/// The options a diagram gives its type, as Pele reads them: first the front matter's under `config:`, from block YAML
/// with the JSON schema (`config:`, then `sankey:`, then `showValues: false`, each level indented more), then those of
/// each `%%{init: …}%%` directive over them (`MermaidDirectiveConfiguration`). Each option's value is a Boolean
/// (`true`, `false`), a number, text (plain or quoted), or a collection (an option followed by a more indented mapping
/// or list, or written in braces or brackets, or a directive's object or array), whose content is not read. Comment
/// lines and blank lines of the front matter are skipped.
struct MermaidConfigurationOptions {
    enum Value: Equatable {
        case boolean(Bool)
        case number(Double)
        case text(String)
        case collection
    }

    private(set) var values: [String: Value] = [:]
    /// The options inside an option that is a mapping, by their path from the section with the names joined by dots
    /// (`xAxis.showLabel`, `nodeColors.Coal`); the mapping itself is a collection in `values`, or here when it is
    /// itself nested.
    private(set) var nestedValues: [String: Value] = [:]

    /// The options under `config:` and then `section:` in the front matter at the start of `bytes`, with those the
    /// directives after it set under `section` over them; none without either.
    init(section: String, in bytes: [UInt8]) {
        let frontMatter = Self.frontMatter(of: bytes)
        var keys: [(indent: Int, key: String)] = []
        let lines = frontMatter.lines
        let frontMatterBytes = Array(frontMatter.lines.joined(separator: "\n").utf8)
        var lineStarts: [Int] = []
        var lineStart = 0
        for line in lines {
            lineStarts.append(lineStart)
            lineStart += line.utf8.count + 1
        }
        var flowBudget = Self.flowReadingBudget(bytes: frontMatterBytes.count)
        var index = 0
        while index < lines.count {
            let line = lines[index]
            index += 1
            let indent = line.prefix { character in character == " " }.count
            let content = line.trimmingCharacters(in: .whitespaces)
            guard !content.isEmpty, !content.hasPrefix("#"), let (key, written, valueOffset) = Self.keyAndValue(content) else { continue }
            while let last = keys.last, last.indent >= indent { keys.removeLast() }
            let path = keys.map(\.key) + [key]
            let isOption = path.count >= 2 && path[0] == "config" && path[1] == section
            if written.isEmpty {
                if isOption { record(.collection, named: path.dropFirst(2).joined(separator: ".")) }
                keys.append((indent, key))
            } else if let flowStart = written.first, flowStart == "{" || flowStart == "[", Self.isRelevant(path, section: section) {
                // The collection may go on over later lines: it ends where it closes.
                let valueStart = lineStarts[index - 1] + line.prefix { character in character == " " || character == "\t" }.utf8.count + valueOffset
                flowBudget -= frontMatterBytes.count - valueStart
                guard flowBudget >= 0, let (value, end) = MermaidFlowCollectionReader.read(frontMatterBytes, from: valueStart) else {
                    if isOption { record(.collection, named: path.dropFirst(2).joined(separator: ".")) }
                    continue
                }
                record(value, at: path, section: section)
                while index < lines.count, lineStarts[index] < end { index += 1 }
            } else if isOption {
                record(Self.value(written), named: path.dropFirst(2).joined(separator: "."))
            }
        }
        MermaidDirectiveConfiguration.apply(section: section, in: bytes, from: frontMatter.end, to: &self)
    }

    /// How many bytes of flow collections the front matter's lines may have read in all, so that a text of many
    /// collections that never close costs no more than a few readings of its length.
    private static func flowReadingBudget(bytes: Int) -> Int {
        4 * bytes + 1_024
    }

    /// Whether a value at `path` can hold the section's options: it is on the way to them (`config`, or `config` and
    /// the section) or inside them.
    private static func isRelevant(_ path: [String], section: String) -> Bool {
        let target = ["config", section]
        return path.count >= target.count ? path.starts(with: target) : target.starts(with: path)
    }

    /// Records `value`, read from a flow collection written at `path` (the keys from the top of the front matter),
    /// as the section's options: the part of it under `config:` and the section.
    private mutating func record(_ value: DirectiveValue, at path: [String], section: String) {
        let target = ["config", section]
        guard path.count < target.count else {
            record(value, named: path.dropFirst(target.count).joined(separator: "."))
            return
        }
        var node = value
        for key in target.dropFirst(path.count) {
            guard case .object(let object) = node, let next = object[key] else { return }
            node = next
        }
        record(node, named: "")
    }

    /// Leaves no option.
    mutating func removeAll() {
        values = [:]
        nestedValues = [:]
    }

    /// Records `value` under `name` (empty for the section itself): a scalar as it is; a mapping as a collection and,
    /// each entry by its path, its options; an array as a collection.
    mutating func record(_ value: DirectiveValue, named name: String, depth: Int = 0) {
        if case .object(let object) = value {
            if !name.isEmpty { store(.collection, named: name) }
            guard depth < MermaidFlowCollectionReader.deepestNesting else { return }
            for (key, entry) in object where !Self.prototypeKeys.contains(key) {
                record(entry, named: name.isEmpty ? key : name + "." + key, depth: depth + 1)
            }
        } else if let read = value.optionValue {
            store(read, named: name)
        } else {
            removeValue(named: name)
        }
    }

    private mutating func record(_ value: Value, named name: String) {
        store(value, named: name)
    }

    private mutating func store(_ value: Value, named name: String) {
        guard !name.isEmpty else { return }
        if name.contains(".") { nestedValues[name] = value } else { values[name] = value }
    }

    private mutating func removeValue(named name: String) {
        if name.contains(".") { nestedValues.removeValue(forKey: name) } else { values.removeValue(forKey: name) }
    }

    private static let prototypeKeys: Set<String> = ["__proto__", "constructor", "prototype"]

    /// The lines between the opening `---` and the closing one, the opening first in the text after blank space, and
    /// where the text after the closing one starts; no lines and 0 without front matter.
    private static func frontMatter(of bytes: [UInt8]) -> (lines: [Substring], end: Int) {
        var cursor = MermaidTextCursor(bytes: bytes)
        if cursor.hasPrefix(byteOrderMark) { cursor.advance(by: byteOrderMark.count) }
        cursor.skipWhitespace()
        // Most diagrams have no front matter: nothing past this is decoded for them.
        guard cursor.hasPrefix(Self.fence), cursor.readRestOfLine() == "---" else { return ([], 0) }
        var lines: [Substring] = []
        while !cursor.isAtEnd {
            cursor.advance()
            let line = cursor.readRestOfLine()
            if line.trimmingCharacters(in: .whitespaces) == "---" { return (lines, cursor.position) }
            lines.append(Substring(line))
        }
        return ([], 0)
    }

    private static let byteOrderMark: [UInt8] = [0xEF, 0xBB, 0xBF]
    private static let fence = Array("---".utf8)

    /// `key: value` or `key:`, the key plain or quoted: the key, the value as written (empty when none follows) and where
    /// the value starts, in bytes from the start of `content`.
    private static func keyAndValue(_ content: String) -> (key: String, value: String, valueOffset: Int)? {
        guard !content.hasPrefix("- ") else { return nil }
        var key: String
        var rest: Substring
        if let quote = content.first, quote == "\"" || quote == "'", let closing = content.dropFirst().firstIndex(of: quote) {
            key = String(content[content.index(after: content.startIndex)..<closing])
            rest = content[content.index(after: closing)...]
            guard rest.first == ":" else { return nil }
            rest = rest.dropFirst()
        } else {
            guard let colon = content.firstIndex(where: { character in character == ":" }) else { return nil }
            let after = content.index(after: colon)
            guard after == content.endIndex || content[after] == " " else { return nil }
            key = String(content[..<colon]).trimmingCharacters(in: .whitespaces)
            rest = content[after...]
        }
        let valueStart = rest.firstIndex { character in character != " " && character != "\t" } ?? rest.endIndex
        return (key, withoutComment(rest.trimmingCharacters(in: .whitespaces)), content.utf8.distance(from: content.startIndex, to: valueStart))
    }

    /// A plain value without the comment after it (` #`); a quoted one as it is.
    private static func withoutComment(_ written: String) -> String {
        guard let first = written.first, first != "\"", first != "'", let comment = written.range(of: " #") else { return written }
        return written[..<comment.lowerBound].trimmingCharacters(in: .whitespaces)
    }

    private static func value(_ written: String) -> Value {
        if let first = written.first, first == "{" || first == "[" { return .collection }
        if let first = written.first, first == "\"" || first == "'", written.count >= 2, written.last == first {
            return .text(String(written.dropFirst().dropLast()))
        }
        if written == "true" || written == "false" { return .boolean(written == "true") }
        if isNumber(written), let number = Double(written) { return .number(number) }
        return .text(written)
    }

    /// Whether the text is a number of YAML's JSON schema: a sign, digits with a fraction and an exponent.
    static func isNumber(_ written: String) -> Bool {
        var bytes = Substring(written).utf8[...]
        if let sign = bytes.first, sign == UInt8(ascii: "+") || sign == UInt8(ascii: "-") { bytes = bytes.dropFirst() }
        let integerDigits = bytes.prefix { byte in MermaidByte.isDigit(byte) }.count
        bytes = bytes.dropFirst(integerDigits)
        var fractionDigits = 0
        if bytes.first == MermaidByte.period {
            fractionDigits = bytes.dropFirst().prefix { byte in MermaidByte.isDigit(byte) }.count
            bytes = bytes.dropFirst(fractionDigits + 1)
        }
        guard integerDigits + fractionDigits > 0 else { return false }
        if let exponent = bytes.first, exponent == UInt8(ascii: "e") || exponent == UInt8(ascii: "E") {
            bytes = bytes.dropFirst()
            if let sign = bytes.first, sign == UInt8(ascii: "+") || sign == UInt8(ascii: "-") { bytes = bytes.dropFirst() }
            let exponentDigits = bytes.prefix { byte in MermaidByte.isDigit(byte) }.count
            guard exponentDigits > 0 else { return false }
            bytes = bytes.dropFirst(exponentDigits)
        }
        return bytes.isEmpty
    }
}
