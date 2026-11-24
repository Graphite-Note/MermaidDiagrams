/**
 * File: MermaidDirectiveConfiguration.swift
 * -----------------------------------------
 * Layer: Core
 * Description: Reads the configuration a diagram's `%%{init: …}%%` directives give, as Pele reads it.
 *
 * Authors: Bahey Shalash
 * Version: 0.6
 * Date: 24/11/2026
 */

import Foundation

/// The configuration of a diagram's `%%{init: …}%%` and `%%{initialize: …}%%` directives, read as Pele reads it
/// (Obsidian's `pele.min.js`, seen 2026-11-17): in the text after the front matter, every apostrophe is first made a
/// quotation mark; each directive, wherever it stands, even within a line or over several lines, is matched as
/// Mermaid's directive pattern matches it (`%%{`, a name, an optional colon, then everything up to the first `}%%` or
/// the end of the text); its JSON object is merged over the configuration so far, objects into objects and any other
/// value in the place of the one before; a directive whose JSON cannot be read is left out, and so is one whose
/// content is a single word. Keys that would reach an object's prototype are skipped. Pele merges the front matter's
/// `config:` first, so a directive's option is applied over the front matter's.
enum MermaidDirectiveConfiguration {
    /// The options the directives in `bytes[start...]` set under `section` (as `pie` or `gitGraph`), applied over `options`,
    /// those inside an option that is an object under their path. A directive that gives `section` a value other than an
    /// object leaves the type no option, as in Pele, and a `null` option is no option.
    static func apply(section: String, in bytes: [UInt8], from start: Int, to options: inout MermaidConfigurationOptions) {
        apply(section: section, of: configuration(in: bytes, from: start), to: &options)
    }

    /// The options the directives' merged `configuration` sets under `section`, applied over `options`.
    static func apply(section: String, of configuration: [String: DirectiveValue], to options: inout MermaidConfigurationOptions) {
        guard let sectionValue = configuration[section] else { return }
        guard case .object(let directiveOptions) = sectionValue else {
            options.removeAll()
            return
        }
        for (name, value) in directiveOptions { options.record(value, named: name) }
    }

    /// Every `init` directive's object in `bytes[start...]` merged in their order; empty, with nothing copied, when the
    /// text holds no directive, as most diagrams do.
    static func configuration(in bytes: [UInt8], from start: Int) -> [String: DirectiveValue] {
        guard contains(directiveStart, in: bytes, from: start) else { return [:] }
        var text = Array(bytes[min(start, bytes.count)...])
        for index in text.indices where text[index] == apostrophe { text[index] = MermaidByte.quotationMark }
        var configuration: [String: DirectiveValue] = [:]
        var position = 0
        while let match = nextDirective(in: text, from: position) {
            position = max(match.end, match.start + 1)
            guard match.name == "init" || match.name == "initialize", let content = match.content,
                  let object = text.withUnsafeBufferPointer({ buffer in object(in: UnsafeBufferPointer(rebasing: buffer[content])) }) else { continue }
            merge(object, into: &configuration)
        }
        return configuration
    }

    /// The object a directive's content writes, its white space trimmed as Foundation trims it: read on its bytes
    /// (`MermaidConfigurationJSONReader`) when it is JSON read there, else by `JSONDecoder`; nil when it is not an
    /// object or its JSON cannot be read, and the directive is then left out, as in Pele.
    static func object(in content: UnsafeBufferPointer<UInt8>) -> [String: DirectiveValue]? {
        if let trimmed = asciiTrimmed(content), let object = MermaidConfigurationJSONReader.object(in: trimmed) { return object }
        let trimmed = String(decoding: content, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let read = try? JSONDecoder().decode(DirectiveValue.self, from: Data(trimmed.utf8)) // Unreadable JSON is left out, as in Pele.
        guard case .object(let object) = read else { return nil }
        return object
    }

    /// `content` without the ASCII white space at its ends (tabs, line breaks, vertical tabs, form feeds, carriage returns
    /// and spaces, the ASCII members of Foundation's `whitespacesAndNewlines`); nil when a byte beyond ASCII is then at
    /// an end, where Foundation might trim more.
    private static func asciiTrimmed(_ content: UnsafeBufferPointer<UInt8>) -> UnsafeBufferPointer<UInt8>? {
        var start = 0
        var end = content.count
        while start < end, isASCIIWhitespaceOrNewline(content[start]) { start += 1 }
        while end > start, isASCIIWhitespaceOrNewline(content[end - 1]) { end -= 1 }
        guard start < end, content[start] < 0x80, content[end - 1] < 0x80 else { return nil }
        return UnsafeBufferPointer(rebasing: content[start..<end])
    }

    private static func isASCIIWhitespaceOrNewline(_ byte: UInt8) -> Bool {
        byte == MermaidByte.space || (0x09...0x0D).contains(byte)
    }

    /// A directive found as Mermaid's pattern finds it: its name, its content (nil when it is a single word or nothing)
    /// and where the match ends.
    struct DirectiveMatch {
        let start: Int
        let name: String
        let content: Range<Int>?
        let end: Int
    }

    /// The pattern `%%{\s*(?:(\w+)\s*:|(\w+))\s*(?:(\w+)|((?:(?!}%%).|\r?\n)*))?\s*(?:}%%)?` from `position` on.
    static func nextDirective(in text: [UInt8], from position: Int) -> DirectiveMatch? {
        var start = position
        while start + directiveStart.count <= text.count {
            guard text[start] == MermaidByte.percent, text[start + 1] == MermaidByte.percent, text[start + 2] == MermaidByte.openingBrace else {
                start += 1
                continue
            }
            var index = skipWhitespace(in: text, from: start + directiveStart.count)
            let nameStart = index
            while index < text.count, isWordByte(text[index]) { index += 1 }
            guard index > nameStart else {
                start += 1
                continue
            }
            let name = String(decoding: text[nameStart..<index], as: UTF8.self)
            let afterName = skipWhitespace(in: text, from: index)
            index = afterName < text.count && text[afterName] == MermaidByte.colon ? afterName + 1 : afterName
            index = skipWhitespace(in: text, from: index)
            var content: Range<Int>?
            if index < text.count, isWordByte(text[index]) {
                while index < text.count, isWordByte(text[index]) { index += 1 }
            } else {
                let contentStart = index
                index = endOfContent(in: text, from: index)
                if index > contentStart { content = contentStart..<index }
            }
            index = skipWhitespace(in: text, from: index)
            if hasDirectiveEnd(in: text, at: index) { index += directiveEnd.count }
            return DirectiveMatch(start: start, name: name, content: content, end: index)
        }
        return nil
    }

    /// Where `((?:(?!}%%).|\r?\n)*)` stops: before the first `}%%`, a carriage return not followed by a line break, a
    /// line or paragraph separator, or at the end.
    private static func endOfContent(in text: [UInt8], from start: Int) -> Int {
        var index = start
        while index < text.count, !hasDirectiveEnd(in: text, at: index) {
            let byte = text[index]
            if byte == MermaidByte.carriageReturn {
                guard index + 1 < text.count, text[index + 1] == MermaidByte.newline else { return index }
                index += 2
                continue
            }
            if byte == 0xE2, index + 2 < text.count, text[index + 1] == 0x80, text[index + 2] == 0xA8 || text[index + 2] == 0xA9 { return index }
            index += 1
        }
        return index
    }

    /// Pele's merge: an object into an object, any other value in the place of the one before; prototype keys skipped.
    private static func merge(_ source: [String: DirectiveValue], into target: inout [String: DirectiveValue]) {
        for (key, value) in source where !prototypeKeys.contains(key) {
            if case .object(let object) = value {
                var merged: [String: DirectiveValue] = [:]
                if case .object(let former) = target[key] { merged = former }
                merge(object, into: &merged)
                target[key] = .object(merged)
            } else {
                target[key] = value
            }
        }
    }

    private static func skipWhitespace(in text: [UInt8], from start: Int) -> Int {
        var index = start
        while index < text.count, isJavaScriptWhitespace(text[index]) { index += 1 }
        return index
    }

    /// `\s` of a JavaScript pattern among ASCII bytes: spaces, tabs, line breaks, carriage returns, vertical tabs and
    /// form feeds.
    private static func isJavaScriptWhitespace(_ byte: UInt8) -> Bool {
        MermaidByte.isWhitespace(byte) || byte == 0x0B || byte == 0x0C
    }

    /// `\w` of a JavaScript pattern: ASCII letters, digits and the underscore.
    private static func isWordByte(_ byte: UInt8) -> Bool {
        MermaidByte.isLetter(byte) || MermaidByte.isDigit(byte) || byte == MermaidByte.underscore
    }

    private static func hasDirectiveEnd(in text: [UInt8], at index: Int) -> Bool {
        index + directiveEnd.count <= text.count && text[index] == MermaidByte.closingBrace && text[index + 1] == MermaidByte.percent
            && text[index + 2] == MermaidByte.percent
    }

    private static func contains(_ literal: [UInt8], in bytes: [UInt8], from start: Int) -> Bool {
        guard start >= 0, start < bytes.count else { return false }
        // Most texts hold no directive: their bytes are looked through sixteen at a time.
        return MermaidPreprocessing.firstIndex(of: literal, in: bytes, from: start) != nil
    }

    private static let directiveStart = Array("%%{".utf8)
    private static let directiveEnd = Array("}%%".utf8)
    private static let apostrophe = UInt8(ascii: "'")
    private static let prototypeKeys: Set<String> = ["__proto__", "constructor", "prototype"]
}

/// A value of a directive's JSON, as `JSONDecoder` reads it.
enum DirectiveValue: Decodable, Equatable {
    case object([String: DirectiveValue])
    case array([DirectiveValue])
    case text(String)
    case number(Double)
    case boolean(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let boolean = try? container.decode(Bool.self) { // Not a Boolean: one of the kinds below.
            self = .boolean(boolean)
        } else if let number = try? container.decode(Double.self) { // Not a number: one of the kinds below.
            self = .number(number)
        } else if let text = try? container.decode(String.self) { // Not text: an object or an array.
            self = .text(text)
        } else if let object = try? container.decode([String: DirectiveValue].self) { // Not an object: an array.
            self = .object(object)
        } else {
            self = .array(try container.decode([DirectiveValue].self))
        }
    }

    /// The value as an option's value; nil for `null`.
    var optionValue: MermaidConfigurationOptions.Value? {
        switch self {
        case .boolean(let boolean): .boolean(boolean)
        case .number(let number): .number(number)
        case .text(let text): .text(text)
        case .object, .array: .collection
        case .null: nil
        }
    }
}
