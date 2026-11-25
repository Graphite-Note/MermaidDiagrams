/**
 * File: KanbanCardFields.swift
 * ----------------------------
 * Layer: Core
 * Description: The six fields of a kanban node's metadata that a board uses (label, icon, ticket, assigned, priority,
 *              shape), read on the metadata's bytes when it is a flow mapping on one line of plain and quoted scalars,
 *              and from the whole YAML reader (KanbanCardMetadata) otherwise.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

/// The fields of a kanban node's metadata that its board reads, each as JavaScript's `String` writes it when JavaScript
/// holds it true, or nil. Other keys are read only as far as YAML needs to refuse a text that is not YAML.
struct KanbanCardFields {
    private(set) var label: String?
    private(set) var icon: String?
    private(set) var ticket: String?
    private(set) var assigned: String?
    private(set) var priority: String?
    private(set) var shape: String?

    private init() {}

    /// The fields of a node's metadata, the text between `@{` and `}`. Metadata on one line whose entries are all
    /// `key: value` with a key of letters, digits, `_` and `-` and a value plain (without `#`, a bracket or a brace) or
    /// quoted (without a backslash or a doubled quotation mark) is read on its bytes; any other metadata is read by
    /// `KanbanCardMetadata`, which gives the same fields for the texts read here, as KanbanMetadataEquivalenceTests checks.
    init(metadata: String) throws(KanbanCardMetadata.Failure) {
        if let fieldsOnBytes = Self.fieldsOnBytes(metadata) {
            self = fieldsOnBytes
            return
        }
        let fields = try KanbanCardMetadata(text: metadata).fields
        self.init()
        label = fields["label"]
        icon = fields["icon"]
        ticket = fields["ticket"]
        assigned = fields["assigned"]
        priority = fields["priority"]
        shape = fields["shape"]
    }

    /// The fields of metadata read on its bytes, or nil when it is not of the subset read there.
    static func fieldsOnBytes(_ metadata: String) -> KanbanCardFields? {
        metadata.utf8.withContiguousStorageIfAvailable { bytes in flowMappingOnOneLine(bytes) } ?? nil
    }

    /// The fields of a flow mapping on one line read on its bytes, or nil when the text is not of the subset read here.
    private static func flowMappingOnOneLine(_ bytes: UnsafeBufferPointer<UInt8>) -> KanbanCardFields? {
        // Metadata over several lines is a block mapping, or a flow collection the whole reader reads.
        guard !bytes.contains(MermaidByte.newline) else { return nil }
        var fields = KanbanCardFields()
        var line = FlowLine(bytes: bytes)
        while true {
            line.skipBlanks()
            guard !line.isAtEnd else { return fields }
            guard let keyRange = line.readKey(), let (valueRange, isPlain) = line.readValue() else { return nil }
            if let key = KnownKey(bytes, keyRange) {
                let text = String(decoding: UnsafeBufferPointer(rebasing: bytes[valueRange]), as: UTF8.self)
                fields.set(key, to: isPlain ? KanbanYAMLValue(plainScalar: text).text : text.isEmpty ? nil : text)
            }
            line.skipBlanks()
            guard !line.isAtEnd else { return fields }
            guard line.skipsOneComma() else { return nil }
        }
    }

    /// A flow mapping's line read entry by entry, each step nil for a text not of the subset read on bytes.
    private struct FlowLine {
        let bytes: UnsafeBufferPointer<UInt8>
        private var position = 0

        init(bytes: UnsafeBufferPointer<UInt8>) {
            self.bytes = bytes
        }

        var isAtEnd: Bool { position >= bytes.count }

        mutating func skipBlanks() {
            while position < bytes.count, MermaidByte.isWhitespace(bytes[position]) { position += 1 }
        }

        /// A key of letters, digits, `_` and `-`, then blanks and a colon that a blank or the end follows. A key without
        /// a colon, or a colon followed by something else, is read by the whole reader.
        mutating func readKey() -> Range<Int>? {
            let start = position
            while position < bytes.count, KanbanCardFields.isKeyByte(bytes[position]) { position += 1 }
            let end = position
            guard end > start else { return nil }
            while position < bytes.count, MermaidByte.isSpace(bytes[position]) { position += 1 }
            guard position < bytes.count, bytes[position] == MermaidByte.colon else { return nil }
            position += 1
            guard isAtEnd || MermaidByte.isWhitespace(bytes[position]) else { return nil }
            skipBlanks()
            return start..<end
        }

        /// A quoted value's body, without a backslash or a doubled quotation mark, or a plain value up to the next comma.
        mutating func readValue() -> (range: Range<Int>, isPlain: Bool)? {
            let start = position
            guard position < bytes.count, bytes[position] == KanbanCardFields.singleQuote || bytes[position] == KanbanCardFields.doubleQuote else {
                while position < bytes.count, bytes[position] != MermaidByte.comma {
                    if KanbanCardFields.isRefusedInPlainValue(bytes[position]) { return nil }
                    position += 1
                }
                return (start..<position, true)
            }
            let quote = bytes[position]
            position += 1
            while position < bytes.count, bytes[position] != quote {
                if bytes[position] == KanbanCardFields.backslash, quote == KanbanCardFields.doubleQuote { return nil }
                position += 1
            }
            // A doubled quotation mark leaves its second one after the value, where no comma is: that text is not read here.
            guard position < bytes.count else { return nil }
            position += 1
            return (start + 1..<position - 1, false)
        }

        /// Entries are separated by a comma; anything else after a value is the whole reader's, and so is a second comma,
        /// as no key starts with one.
        mutating func skipsOneComma() -> Bool {
            guard bytes[position] == MermaidByte.comma else { return false }
            position += 1
            return true
        }
    }

    private mutating func set(_ key: KnownKey, to value: String?) {
        switch key {
        case .label: label = value
        case .icon: icon = value
        case .ticket: ticket = value
        case .assigned: assigned = value
        case .priority: priority = value
        case .shape: shape = value
        }
    }

    /// The keys a board reads.
    private enum KnownKey {
        case label, icon, ticket, assigned, priority, shape

        /// The key the bytes spell, or nil for another key.
        init?(_ bytes: UnsafeBufferPointer<UInt8>, _ range: Range<Int>) {
            let key = UnsafeBufferPointer(rebasing: bytes[range])
            switch key.count {
            case 4 where key.elementsEqual(Self.iconBytes): self = .icon
            case 5 where key.elementsEqual(Self.labelBytes): self = .label
            case 5 where key.elementsEqual(Self.shapeBytes): self = .shape
            case 6 where key.elementsEqual(Self.ticketBytes): self = .ticket
            case 8 where key.elementsEqual(Self.assignedBytes): self = .assigned
            case 8 where key.elementsEqual(Self.priorityBytes): self = .priority
            default: return nil
            }
        }

        private static let labelBytes = Array("label".utf8)
        private static let iconBytes = Array("icon".utf8)
        private static let ticketBytes = Array("ticket".utf8)
        private static let assignedBytes = Array("assigned".utf8)
        private static let priorityBytes = Array("priority".utf8)
        private static let shapeBytes = Array("shape".utf8)
    }

    /// A byte of a key read here: an ASCII letter, a digit, `_` or `-`.
    private static func isKeyByte(_ byte: UInt8) -> Bool {
        MermaidByte.isLetter(byte) || MermaidByte.isDigit(byte) || byte == MermaidByte.underscore || byte == hyphen
    }

    /// What a plain value read here may not hold: a comment's `#` and the flow indicators the whole reader treats
    /// otherwise (`{`, `}`, `[`, `]`).
    private static func isRefusedInPlainValue(_ byte: UInt8) -> Bool {
        byte == numberSign || byte == MermaidByte.openingBrace || byte == MermaidByte.closingBrace
            || byte == MermaidByte.openingBracket || byte == closingBracket
    }

    private static let singleQuote = UInt8(ascii: "'")
    private static let doubleQuote = UInt8(ascii: "\"")
    private static let backslash = UInt8(ascii: "\\")
    private static let hyphen = UInt8(ascii: "-")
    private static let numberSign = UInt8(ascii: "#")
    private static let closingBracket = UInt8(ascii: "]")
}
