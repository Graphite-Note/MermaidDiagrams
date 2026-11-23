/**
 * File: MermaidYAMLDocument.swift
 * -------------------------------
 * Layer: Core
 * Description: A YAML text read as Pele's util/yaml.ts reads it, for a diagram's front matter and a flowchart node's
 *              `@{ … }`, as the values a configuration holds.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

/// A YAML text read by the package's port of Pele's YAML reader (`SequenceAttributesBlockSyntax`, first written for a
/// sequence participant's attributes): block and flow collections, quoted scalars folded across lines, a backslash
/// before a line break in double quotes, a key with nothing after it null, block scalars, the JSON schema's scalars.
enum MermaidYAMLDocument {
    /// The value `source` holds, or nil when Pele's reader refuses it.
    static func value(of source: String) -> DirectiveValue? {
        value(of: Array(source.utf8))
    }

    /// The value the UTF-8 bytes `source` hold, built as a configuration's values as it is read; nil when Pele's
    /// reader refuses it.
    static func value(of source: [UInt8]) -> DirectiveValue? {
        try? SequenceAttributesBlockSyntax.value(of: source, as: DirectiveValue.self)
    }

    /// JavaScript's `String(value)`, as Pele writes the front matter's `title` and `displayMode`.
    static func javaScriptText(_ value: DirectiveValue) -> String {
        sequenceValue(value).javaScriptText
    }

    /// Whether JavaScript counts the value as true, as Pele tests the front matter's `title` and `displayMode`.
    static func isTruthy(_ value: DirectiveValue) -> Bool {
        sequenceValue(value).isTruthy
    }

    private static func sequenceValue(_ value: DirectiveValue) -> SequenceAttributeValue {
        switch value {
        case .null: .null
        case .boolean(let boolean): .boolean(boolean)
        case .number(let number): .number(number)
        case .text(let text): .text(text)
        case .array(let items): .list(items.map(sequenceValue))
        case .object(let entries): .mapping(entries.mapValues(sequenceValue))
        }
    }
}

/// A configuration's values as the YAML reader builds them: a list is an array, a mapping an object.
extension DirectiveValue: MermaidYAMLValue {
    static func list(_ items: [DirectiveValue]) -> DirectiveValue {
        .array(items)
    }

    static func mapping(_ entries: [String: DirectiveValue]) -> DirectiveValue {
        .object(entries)
    }
}
