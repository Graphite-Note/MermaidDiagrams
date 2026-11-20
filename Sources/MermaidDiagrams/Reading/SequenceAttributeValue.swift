/**
 * File: SequenceAttributeValue.swift
 * ----------------------------------
 * Layer: Core
 * Description: A value of the YAML a sequence participant's attributes are read as, and how JavaScript turns it into
 *              text and into a truth value, as Mermaid uses `type` and `alias`.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

/// A value of the YAML a participant's attributes (`@{ … }`) are read as, with the JSON schema Mermaid gives js-yaml.
indirect enum SequenceAttributeValue: Equatable, Sendable {
    case null
    case boolean(Bool)
    case number(Double)
    case text(String)
    case list([SequenceAttributeValue])
    case mapping([String: SequenceAttributeValue])

    /// The value as JavaScript's `String(value)` writes it, as Mermaid turns a `type` or an `alias` into text: a list's
    /// items joined by commas (a null one empty), a mapping `[object Object]`.
    var javaScriptText: String {
        switch self {
        case .null: "null"
        case .boolean(let value): value ? "true" : "false"
        case .number(let value): Self.javaScriptText(of: value)
        case .text(let value): value
        case .list(let items): items.map { item in item == .null ? "" : item.javaScriptText }.joined(separator: ",")
        case .mapping: "[object Object]"
        }
    }

    /// Whether JavaScript counts the value as true: not null, false, zero, NaN or empty text.
    var isTruthy: Bool {
        switch self {
        case .null: false
        case .boolean(let value): value
        case .number(let value): value != 0 && !value.isNaN
        case .text(let value): !value.isEmpty
        case .list, .mapping: true
        }
    }

    private static func javaScriptText(of number: Double) -> String {
        if number.isNaN { return "NaN" }
        if number.isInfinite { return number < 0 ? "-Infinity" : "Infinity" }
        return JavaScriptNumberText.text(number)
    }
}

/// Why a participant's attributes are not YAML. `incomplete` is a quoted scalar or a flow collection that runs past
/// the text read so far, which the reader of a block value retries with more lines before giving up.
enum SequenceAttributesYAMLFailure: Error {
    case incomplete
    case invalid
}
