/**
 * File: AgentFlowMetadataReading.swift
 * ------------------------------------
 * Layer: Core
 * Description: An agent flow's `@{ … }` metadata read as YAML as Pele's database reads it: one line as a flow
 *              mapping, several as a block, retried without the commas that end lines, keys that could pollute a
 *              prototype dropped, merged into what the element had.
 *
 * Authors: Bahey Shalash
 * Version: 0.5
 * Date: 24/11/2026
 */

import Foundation

enum AgentFlowMetadataReading {
    /// The YAML of a metadata block's body, or nil when it is not YAML even without the commas that end its lines. A
    /// body on one line is read inside braces; one of several lines as a block. A null value is an empty mapping.
    static func value(of body: String) -> SequenceAttributeValue? {
        // Most bodies are one line of plain entries, read on their bytes as the YAML reader reads them.
        if let plain = AgentFlowPlainMetadata.value(of: body) { return plain }
        return yamlValue(of: body)
    }

    /// The YAML of a metadata body read by the YAML reader, as `value(of:)` reads any body.
    static func yamlValue(of body: String) -> SequenceAttributeValue? {
        // A line feed is a character of its own but after a carriage return: without one, its byte is the character.
        let isMultiline = body.utf8.contains(MermaidByte.newline) && (!body.utf8.contains(MermaidByte.carriageReturn) || body.contains("\n"))
        let document = isMultiline ? body + "\n" : "{\n" + body + "\n}"
        var parsed = try? SequenceAttributesBlockSyntax.value(of: document)
        if parsed == nil, isMultiline {
            // Block YAML refuses the comma-separated style of the one-line form, so it is tried once more without them.
            let stripped = withoutLineTrailingCommas(body)
            if stripped != body { parsed = try? SequenceAttributesBlockSyntax.value(of: stripped + "\n") }
        }
        guard let parsed else { return nil }
        return withoutPrototypeKeys(parsed == .null ? .mapping([:]) : parsed)
    }

    /// `metadata` with what `value` holds added, as JavaScript's `Object.assign` spreads it: a mapping's keys, a list's
    /// indexes, a text's characters by index; other values add nothing.
    static func merged(_ metadata: AgentFlowMetadata?, with value: SequenceAttributeValue) -> AgentFlowMetadata {
        var merged = metadata ?? [:]
        switch value {
        case .mapping(let fields):
            merged.reserveCapacity(merged.count + fields.count)
            for (key, field) in fields { merged[key] = field }
        case .list(let items):
            for (index, item) in items.enumerated() { merged[String(index)] = item }
        case .text(let text):
            for (index, unit) in text.utf16.enumerated() { merged[String(index)] = .text(String(decoding: [unit], as: UTF16.self)) }
        default:
            break
        }
        return merged
    }

    /// The value without `__proto__`, `constructor` and `prototype` keys at any depth, so that a consumer merging
    /// metadata into its own objects cannot be made to pollute a prototype. The YAML reader bounds the depth.
    private static func withoutPrototypeKeys(_ value: SequenceAttributeValue) -> SequenceAttributeValue {
        // Most metadata holds no such key: it is then kept as it is, not built again.
        guard holdsPrototypeKey(value) else { return value }
        switch value {
        case .mapping(let fields):
            var kept: [String: SequenceAttributeValue] = [:]
            kept.reserveCapacity(fields.count)
            for (key, field) in fields where !prototypeKeys.contains(key) { kept[key] = withoutPrototypeKeys(field) }
            return .mapping(kept)
        case .list(let items): return .list(items.map(withoutPrototypeKeys))
        default: return value
        }
    }

    private static let prototypeKeys: Set<String> = ["__proto__", "constructor", "prototype"]

    /// Whether a mapping at any depth of `value` has a `__proto__`, `constructor` or `prototype` key.
    private static func holdsPrototypeKey(_ value: SequenceAttributeValue) -> Bool {
        switch value {
        case .mapping(let fields): fields.contains { key, field in prototypeKeys.contains(key) || holdsPrototypeKey(field) }
        case .list(let items): items.contains(where: holdsPrototypeKey)
        default: false
        }
    }

    /// The body without the comma that ends each line, which block YAML does not allow; commas inside quoted scalars,
    /// flow collections and block scalars are content and stay.
    static func withoutLineTrailingCommas(_ body: String) -> String {
        var state = CommaState()
        return body.split(separator: "\n", omittingEmptySubsequences: false).map { line in state.line(Array(line)) }.joined(separator: "\n")
    }

    /// What a line leaves open for the next: a quoted scalar, a flow collection's depth, a block scalar's indent.
    private struct CommaState {
        var isInSingleQuotes = false
        var isInDoubleQuotes = false
        var flowDepth = 0
        var blockScalarIndent: Int?

        mutating func line(_ line: [Character]) -> String {
            let indent = line.prefix { character in character.isWhitespace }.count
            let isBlank = line.allSatisfy(\.isWhitespace)
            if let blockIndent = blockScalarIndent {
                if isBlank || indent > blockIndent { return String(line) }
                blockScalarIndent = nil
            }
            let commentStart = scan(line)
            if isInSingleQuotes || isInDoubleQuotes || flowDepth > 0 { return String(line) }
            let code = String(commentStart.map { start in line[..<start] } ?? line[...])
            let comment = commentStart.map { start in String(line[start...]) } ?? ""
            if Self.opensBlockScalar(code) {
                blockScalarIndent = indent
                return String(line)
            }
            return Self.withoutTrailingComma(code) + comment
        }

        /// Follows the quotes and brackets of a line; where its comment starts, or nil.
        private mutating func scan(_ line: [Character]) -> Int? {
            var index = 0
            while index < line.count {
                let character = line[index]
                if isInDoubleQuotes {
                    if character == "\\" { index += 1 } else if character == "\"" { isInDoubleQuotes = false }
                } else if isInSingleQuotes {
                    if character == "'" { isInSingleQuotes = false }
                } else if character == "\"" {
                    isInDoubleQuotes = true
                } else if character == "'" {
                    isInSingleQuotes = true
                } else if character == "#", index == 0 || line[index - 1] == " " || line[index - 1] == "\t" {
                    return index
                } else if character == "[" || character == "{" {
                    flowDepth += 1
                } else if character == "]" || character == "}" {
                    flowDepth = max(0, flowDepth - 1)
                }
                index += 1
            }
            return nil
        }

        /// `:\s*[>|][\d+-]*\s*$`.
        private static func opensBlockScalar(_ code: String) -> Bool {
            code.range(of: #":\s*[>|][\d+-]*\s*$"#, options: .regularExpression) != nil
        }

        /// `,([\t ]*)$` made `$1`.
        private static func withoutTrailingComma(_ code: String) -> String {
            guard let range = code.range(of: #",([\t ]*)$"#, options: .regularExpression) else { return code }
            return code.replacingCharacters(in: range, with: String(code[range].dropFirst()))
        }
    }
}
