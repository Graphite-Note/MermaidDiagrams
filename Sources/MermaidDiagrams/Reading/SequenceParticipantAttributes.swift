/**
 * File: SequenceParticipantAttributes.swift
 * -----------------------------------------
 * Layer: Core
 * Description: What a sequence participant's `@{ … }` attributes say: the shape its `type` names and the text its
 *              `alias` gives, read as Mermaid reads them, as YAML.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 24/11/2026
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
        if let quoted = Self.quotedTypeAndAlias(text) {
            self = quoted
            return
        }
        self.init(yamlText: text)
    }

    /// Reads the attributes' text as YAML, whatever it holds.
    init?(yamlText text: String) {
        let content = UnicodeScalarText.string(SequenceAttributesFlowSyntax.trimmed(text.unicodeScalars))
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

    /// The attributes as documented, read on their bytes without the YAML reader: blanks, then `"type"` or `"alias"`,
    /// blanks, a colon, blanks and a value in quotation marks, pairs separated by commas, each key once, every byte
    /// between quotation marks printable ASCII other than `"` and `\`, then blanks and the end. Nil for anything else,
    /// which the YAML reader reads: what it reads such a text into is a mapping of those keys to those texts.
    private static func quotedTypeAndAlias(_ text: String) -> SequenceParticipantAttributes? {
        var type: String?
        var alias: String?
        var hasAlias = false
        let found: Bool? = text.utf8.withContiguousStorageIfAvailable { bytes in
            var pairs = QuotedPairs(bytes: bytes)
            pairs.skipBlanks()
            while true {
                guard let (key, value) = pairs.pair() else { return false }
                let written = String(decoding: UnsafeBufferPointer(rebasing: bytes[value]), as: UTF8.self)
                if bytes[key].elementsEqual("type".utf8), type == nil {
                    type = written
                } else if bytes[key].elementsEqual("alias".utf8), !hasAlias {
                    hasAlias = true
                    alias = written.isEmpty ? nil : written
                } else {
                    return false
                }
                switch pairs.end() {
                case .some(true): return true
                case .some(false): continue
                case .none: return false
                }
            }
        }
        guard found == true else { return nil }
        return SequenceParticipantAttributes(type: type, alias: alias)
    }

    /// Pairs of quoted keys and values, read from the start of the attributes' bytes.
    private struct QuotedPairs {
        let bytes: UnsafeBufferPointer<UInt8>
        var index = 0

        mutating func skipBlanks() {
            while index < bytes.count, bytes[index] == 0x20 || bytes[index] == 0x09 { index += 1 }
        }

        /// A key and its value, with the blanks after them: `"key"`, blanks, `:`, blanks, `"value"`.
        mutating func pair() -> (key: Range<Int>, value: Range<Int>)? {
            guard let key = quoted() else { return nil }
            skipBlanks()
            guard index < bytes.count, bytes[index] == 0x3A else { return nil }
            index += 1
            skipBlanks()
            guard let value = quoted() else { return nil }
            skipBlanks()
            return (key, value)
        }

        /// True at the end of the bytes, false past a comma and the blanks after it, nil before anything else.
        mutating func end() -> Bool? {
            if index == bytes.count { return true }
            guard bytes[index] == 0x2C else { return nil }
            index += 1
            skipBlanks()
            return false
        }

        /// The bytes between quotation marks, all printable ASCII other than `"` and `\`, the cursor past the closing one.
        private mutating func quoted() -> Range<Int>? {
            guard index < bytes.count, bytes[index] == 0x22 else { return nil }
            let start = index + 1
            index = start
            while index < bytes.count, bytes[index] != 0x22 {
                guard bytes[index] >= 0x20, bytes[index] <= 0x7E, bytes[index] != 0x5C else { return nil }
                index += 1
            }
            guard index < bytes.count else { return nil }
            index += 1
            return start..<(index - 1)
        }
    }

    private init(type: String?, alias: String?) {
        self.type = type
        self.alias = alias
    }
}
