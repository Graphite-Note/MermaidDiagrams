/**
 * File: SequenceParticipantAttributes.swift
 * -----------------------------------------
 * Layer: Core
 * Description: What a sequence participant's `@{ … }` attributes say: the shape its `type` names and the text its
 *              `alias` gives, read as Mermaid reads them, as YAML.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// `participant API@{ "type": "boundary", "alias": "Public API" }`: the text between the braces, up to the first
/// closing brace, read as YAML the way Mermaid reads it. On one line (once trimmed) it is a flow mapping, wrapped in
/// braces; over several lines a block mapping. Keys other than `type` and `alias` are read and not used.
struct SequenceParticipantAttributes: Equatable {
    /// `type`, as JavaScript's `String` writes it, or nil when it is missing or null.
    let type: String?
    /// `alias`, as JavaScript's `String` writes it, or nil when it is missing or not a true value (null, false, 0, "").
    let alias: String?

    /// Reads the attributes' text; nil when it is not YAML, as Mermaid refuses it. Text that holds no mapping (a list, a
    /// scalar) gives neither a type nor an alias.
    init?(text: String) {
        let content = String(String.UnicodeScalarView(SequenceAttributesFlowSyntax.trimmed(text.unicodeScalars)))
        let document = content.contains("\n") ? content + "\n" : "{\n" + content + "\n}"
        guard let value = try? SequenceAttributesBlockSyntax.value(of: document) else { return nil }
        guard case .mapping(let entries) = value else {
            type = nil
            alias = nil
            return
        }
        type = entries["type"].flatMap { written in written == .null ? nil : written.javaScriptText }
        alias = entries["alias"].flatMap { written in written.isTruthy ? written.javaScriptText : nil }
    }
}
