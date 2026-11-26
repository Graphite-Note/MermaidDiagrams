/**
 * File: AgentFlowMetadataFacts.swift
 * ----------------------------------
 * Layer: Core
 * Description: What an agent flow's reader takes from a metadata body while reading (its shape, label, label type,
 *              curve and view), read on the body's bytes when it is one plain line, by the YAML reader otherwise; the
 *              whole metadata is read again only when a model's metadata is asked for.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

/// A metadata value the reader acts on: text, by the range of its bytes, or any other value.
enum AgentFlowMetadataValue {
    case text(MermaidTextRange)
    case other(SequenceAttributeValue)

    /// JavaScript's truthiness of the value.
    var isTruthy: Bool {
        switch self {
        case .text(let range): !range.isEmpty
        case .other(let value): value.isTruthy
        }
    }

    /// The value as JavaScript's `String` writes it, a range of `text`'s bytes.
    func javaScriptText(in text: inout AgentFlowTextBytes) -> MermaidTextRange {
        switch self {
        case .text(let range): range
        case .other(let value): text.append(value.javaScriptText.utf8)
        }
    }

    /// The value in the YAML reader's terms, for a message.
    func value(in text: AgentFlowTextBytes) -> SequenceAttributeValue {
        switch self {
        case .text(let range): .text(text.string(range))
        case .other(let value): value
        }
    }
}

/// The fields of a metadata body the reader acts on, nil when the body has none; `isMapping` is false for a body YAML
/// reads as a list, a text or a number.
struct AgentFlowMetadataFacts {
    var isMapping = true
    var shape: AgentFlowMetadataValue?
    var label: AgentFlowMetadataValue?
    var labelType: AgentFlowMetadataValue?
    var curve: AgentFlowMetadataValue?
    var view: AgentFlowMetadataValue?

    /// The facts of the body `range` of `text`, or nil when it is not YAML even without the commas that end its lines, as
    /// `AgentFlowMetadataReading.value(of:)` reads it. `entries` is room the plain reader reuses.
    static func reading(_ range: MermaidTextRange, in text: inout AgentFlowTextBytes,
                        entries: inout ScratchList<AgentFlowPlainMetadata.Entry>) -> AgentFlowMetadataFacts? {
        if AgentFlowPlainMetadata.entries(of: text.bytes, range.lowerBound..<range.upperBound, into: &entries) {
            var facts = AgentFlowMetadataFacts()
            for entry in entries { facts.take(entry, in: &text) }
            return facts
        }
        guard let value = AgentFlowMetadataReading.yamlValue(of: text.string(range)) else { return nil }
        guard case .mapping(let fields) = value else { return AgentFlowMetadataFacts(isMapping: false) }
        var facts = AgentFlowMetadataFacts()
        facts.shape = fields["shape"].map { field in Self.value(field, in: &text) }
        facts.label = fields["label"].map { field in Self.value(field, in: &text) }
        facts.labelType = fields["labelType"].map { field in Self.value(field, in: &text) }
        facts.curve = fields["curve"].map { field in Self.value(field, in: &text) }
        facts.view = fields["view"].map { field in Self.value(field, in: &text) }
        return facts
    }

    private static func value(_ value: SequenceAttributeValue, in text: inout AgentFlowTextBytes) -> AgentFlowMetadataValue {
        guard case .text(let written) = value else { return .other(value) }
        return .text(text.append(written.utf8))
    }

    /// One plain entry's value, when its key is one the reader acts on.
    private mutating func take(_ entry: AgentFlowPlainMetadata.Entry, in text: inout AgentFlowTextBytes) {
        let key = text.bytes[entry.key]
        let field = Self.keys.firstIndex { known in known.elementsEqual(key) }
        guard let field else { return }
        let range = MermaidTextRange(start: entry.value.lowerBound, end: entry.value.upperBound)
        let value: AgentFlowMetadataValue = entry.isQuoted || AgentFlowPlainMetadata.isPlainText(text.bytes[entry.value])
            ? .text(range) : Self.value(SequenceAttributesScalarSyntax.scalar(text.bytes[entry.value]), in: &text)
        switch field {
        case 0: shape = value
        case 1: label = value
        case 2: labelType = value
        case 3: curve = value
        default: view = value
        }
    }

    /// The keys the reader acts on, in the order `take` stores them.
    private static let keys: [[UInt8]] = ["shape", "label", "labelType", "curve", "view"].map { key in Array(key.utf8) }
}
