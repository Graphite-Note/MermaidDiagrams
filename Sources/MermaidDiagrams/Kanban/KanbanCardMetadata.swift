/**
 * File: KanbanCardMetadata.swift
 * ------------------------------
 * Layer: Core
 * Description: Reads a kanban node's metadata, the YAML between `@{` and `}`, into the text of its fields, as Mermaid
 *              reads it with js-yaml and Pele with its own YAML reader.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import Foundation

/// A kanban node's metadata as Pele reads it: the text on one line is a flow mapping (`{ ticket: MC-1, assigned: 'knsv' }`
/// without its braces), the text over several lines a block mapping (`key: value` a line). Each field is read as YAML's
/// JSON schema reads it and kept as JavaScript's `String` writes it, when JavaScript holds it true: no field for null,
/// `false`, `0` or empty text; a flow collection as `String` writes it (`KanbanYAMLValue.text`). A block collection under a
/// key is no field. Metadata that is not a mapping is ignored, as Pele ignores it; metadata that is not YAML is refused.
struct KanbanCardMetadata {
    private(set) var fields: [String: String] = [:]

    /// Why metadata was refused.
    enum Failure: Error {
        case notYAML
    }

    /// The most collections nested in one another that are read, as Pele's YAML reader bounds them.
    static let deepestNesting = 64

    init(text: String) throws(Failure) {
        let bytes = Array(text.utf8)
        let first = bytes.first { byte in !MermaidByte.isWhitespace(byte) }
        if bytes.contains(MermaidByte.newline), first != MermaidByte.openingBrace, first != MermaidByte.openingBracket {
            try readBlock(bytes)
            return
        }
        let document = bytes.contains(MermaidByte.newline) ? bytes : Array("{\n".utf8) + bytes + Array("\n}".utf8)
        var reader = KanbanFlowReader(bytes: document)
        guard case .mapping(let values) = try reader.readDocument() else { return }
        fields = values
    }

    /// A block mapping: each line at the first line's indentation is `key: value`; a line indented more continues a plain
    /// value or holds a collection under a key with no value, which is no field.
    private mutating func readBlock(_ bytes: [UInt8]) throws(Failure) {
        let lines = bytes.split(separator: MermaidByte.newline, omittingEmptySubsequences: false).map { line in
            line.last == MermaidByte.carriageReturn ? line.dropLast() : line
        }
        var mappingIndentation: Int?
        var lastKey: String?
        var lastValue = ""
        var continuesPlainValue = false
        for line in lines {
            let content = line.drop { byte in byte == MermaidByte.space }
            guard let first = content.first, first != UInt8(ascii: "#") else { continue }
            if first == MermaidByte.tab { throw .notYAML }
            let indentation = line.count - content.count
            let isFirst = mappingIndentation == nil
            if isFirst { mappingIndentation = indentation }
            guard let mappingIndentation, indentation >= mappingIndentation else { throw .notYAML }
            if indentation > mappingIndentation {
                guard let lastKey else { throw .notYAML }
                if continuesPlainValue { lastValue += " " + Self.withoutComment(content).trimmed; fields[lastKey] = Self.scalarText(lastValue) }
                continue
            }
            guard let (key, rest) = try Self.keyAndRest(content) else { throw .notYAML }
            lastKey = key
            let value = Self.withoutComment(rest.utf8).trimmed
            continuesPlainValue = !value.isEmpty && !"{['\"".utf8.contains(value.utf8.first ?? 0)
            lastValue = value
            if value.isEmpty {
                fields[key] = nil
            } else if continuesPlainValue {
                fields[key] = Self.scalarText(value)
            } else {
                var reader = KanbanFlowReader(bytes: Array(value.utf8))
                fields[key] = try reader.readDocument().text
            }
        }
    }

    /// `key: rest`, the key plain or quoted, the colon followed by a space or the end of the line.
    private static func keyAndRest(_ content: ArraySlice<UInt8>) throws(Failure) -> (String, String)? {
        var reader = KanbanFlowReader(bytes: Array(content))
        guard let key = try reader.readKey(), reader.skipsColonBeforeValue() else { return nil }
        return (key, reader.rest)
    }

    private static func withoutComment(_ text: some Collection<UInt8>) -> String {
        var previous = MermaidByte.space
        var kept: [UInt8] = []
        for byte in text {
            if byte == UInt8(ascii: "#"), MermaidByte.isSpace(previous) { break }
            kept.append(byte)
            previous = byte
        }
        return String(decoding: kept, as: UTF8.self)
    }

    /// A plain scalar read by YAML's JSON schema, as JavaScript writes it when it holds it true.
    static func scalarText(_ written: String) -> String? {
        KanbanYAMLValue(plainScalar: written).text
    }
}

private extension String {
    var trimmed: String { FoundationTextOnBytes.trimmed(self, includingLineBreaks: false) }
}
