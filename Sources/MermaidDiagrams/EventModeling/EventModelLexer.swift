/**
 * File: EventModelLexer.swift
 * ---------------------------
 * Layer: Core
 * Description: The token rules of Mermaid's event modeling grammar, in its lexer's order: keywords that give way to a
 *              longer name, frame numbers, data in braces or quotes, data blocks, titles, comments.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 25/11/2026
 */

/// A token of an event model's text.
enum EventModelTokenKind: Equatable, Sendable {
    case keyword
    /// One of the grammar's words (`tf`, `evt`, `given`, `json` …), by its text.
    case word(String)
    /// `->>`.
    case arrow
    /// `[[` and `]]`.
    case openingReference
    case closingReference
    case graveAccent
    case period
    /// A name: a letter or underscore, then letters, digits and underscores.
    case name
    /// One to three digits.
    case frameNumber
    /// `{ … }`, `"…"` or `'…'` on one line, to the last closing brace or quotation mark of the line.
    case inlineData
    /// `{`, a line break, lines, and a `}` at the start of a line.
    case dataBlock
    case accessibilityDescription
    case accessibilityTitle
    case title
}

/// Mermaid's event modeling tokens, in the order its generated lexer tries them (`EVENTMODELING_TOKENS` in Pele).
/// Each rule names the bytes its match can start with, so that a byte is tried against the rules that may match there.
enum EventModelLexer {
    typealias Rule = FirstMatchTokenRule<EventModelTokenKind>
    typealias Patterns = FirstMatchTokenPatterns

    /// The grammar's words, in its lexer's order; each gives way to a longer name.
    static let words = ["resetframe", "readmodel", "processor", "timeframe", "command", "entity", "event", "jsobj", "figma", "given", "json", "salt",
                        "html", "text", "data", "note", "when", "then", "rmo", "cmd", "evt", "pcr", "uri"]

    static let tokenizer = FirstMatchTokenizer(rules: rules)

    private static var rules: [Rule] {
        var rules = [Rule("eventmodeling", kind: .keyword, firstBytes: bytes("e"), longerAlternatives: [nameRule],
                          match: Patterns.keyword("eventmodeling"))]
        rules += words.map(word)
        rules += [
            sign("->>", .arrow), word("gwt"), word("ui"), word("md"), word("tf"), sign("[[", .openingReference),
            sign("]]", .closingReference), word("rf"), sign("`", .graveAccent), sign(".", .period),
            Rule(nameRule, kind: .name, firstBytes: letters + bytes("_"), match: Patterns.name(first: .letterOrUnderscore, rest: .word)),
            Rule("EM_FID", kind: .frameNumber, firstBytes: bytes("0123456789"), match: .custom(frameNumber)),
            Rule("EM_DATA_INLINE", kind: .inlineData, firstBytes: bytes("{\"'"), match: .custom(inlineData)),
            Rule("EM_DATA_BLOCK", kind: .dataBlock, firstBytes: bytes("{"), match: .custom(dataBlock)),
            Rule("EM_ACC_DESCR", kind: .accessibilityDescription, firstBytes: bytes("\t a"), match: .custom(accessibilityDescription)),
            Rule("EM_ACC_TITLE", kind: .accessibilityTitle, firstBytes: bytes("\t a"), match: Patterns.accessibilityTitle(leadingBlanks: true)),
            Rule("EM_TITLE", kind: .title, firstBytes: bytes("\t t"),
                 match: Patterns.lineStatement("title", leadingBlanks: true, continuesName: .word)),
            Rule("EM_WS", kind: nil, firstBytes: bytes("\t\n\u{0B}\u{0C}\r "), match: Patterns.whitespace(isJavaScriptWhitespace: true)),
            Rule("EM_YAML", kind: nil, firstBytes: bytes("-"), match: Patterns.frontMatterFence),
            Rule("EM_DIRECTIVE", kind: nil, firstBytes: bytes("\t %"), match: Patterns.directive),
            Rule("EM_SINGLE_LINE_COMMENT", kind: nil, firstBytes: bytes("\t %"), match: Patterns.percentComment),
            Rule("EM_ML_COMMENT", kind: nil, firstBytes: bytes("/"), match: Patterns.blockComment(opening: "/*", closing: "*/")),
            Rule("EM_SL_COMMENT", kind: nil, firstBytes: bytes("/"), match: Patterns.lineComment(opening: "//")),
        ]
        return rules
    }

    private static let nameRule = "EM_ID"
    private static let letters = bytes("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")

    private static func word(_ text: String) -> Rule {
        Rule(text, kind: .word(text), firstBytes: [text.utf8.first ?? 0], longerAlternatives: [nameRule], match: Patterns.literal(text))
    }

    private static func sign(_ text: String, _ kind: EventModelTokenKind) -> Rule {
        Rule(text, kind: kind, firstBytes: [text.utf8.first ?? 0], match: Patterns.literal(text))
    }

    private static func bytes(_ text: String) -> [UInt8] {
        Array(text.utf8)
    }

    /// `\d{1,3}`.
    private static let frameNumber: FirstMatchTokenPattern = { text, position in
        var end = position
        while end < text.bytes.count, end - position < 3, MermaidByte.isDigit(text.bytes[end]) { end += 1 }
        return .matched(end: end)
    }

    /// `\{(.*)\}|"(.*)"|'(.*)'`: from the opening character to the last closing one before the line ends.
    private static let inlineData: FirstMatchTokenPattern = { text, position in
        let bytes = text.bytes
        let opening = bytes[position]
        let closing: UInt8
        switch opening {
        case MermaidByte.openingBrace: closing = MermaidByte.closingBrace
        case MermaidByte.quotationMark, Patterns.apostrophe: closing = opening
        default: return .none
        }
        var index = position + 1
        var lastClosing: Int?
        while index < bytes.count, Patterns.lineTerminatorLength(bytes, index) == 0 {
            if bytes[index] == closing { lastClosing = index }
            index += 1
        }
        return lastClosing.map { closingIndex in .matched(end: closingIndex + 1) } ?? .none
    }

    /// `\{[\t ]*\r?\n(?:[\S\s]*?\r?\n)?\}(?:\r?\n|(?!\S))`: a brace that ends its line, up to the first `}` that starts
    /// a line and that a line break, whitespace or the end follows.
    private static let dataBlock: FirstMatchTokenPattern = { text, position in
        let bytes = text.bytes
        guard bytes[position] == MermaidByte.openingBrace else { return .none }
        var index = Patterns.endOfBlanks(bytes, from: position + 1)
        if index < bytes.count, bytes[index] == MermaidByte.carriageReturn { index += 1 }
        guard index < bytes.count, bytes[index] == MermaidByte.newline else { return .none }
        var lineStart = index + 1
        while true {
            if lineStart < bytes.count, bytes[lineStart] == MermaidByte.closingBrace, let end = Patterns.endAfterClosingFence(bytes, lineStart + 1) {
                return .matched(end: end)
            }
            guard let lineBreak = text.firstOccurrence(of: newlineNeedle, from: lineStart) else { return .noneFurtherOn }
            lineStart = lineBreak + 1
        }
    }

    /// `[\t ]*accDescr`, then blanks, `:` and the rest of the line up to `%%`; or whitespace and `{` up to the next `}`.
    private static let accessibilityDescription: FirstMatchTokenPattern = { text, position in
        let bytes = text.bytes
        let start = Patterns.endOfBlanks(bytes, from: position)
        guard Patterns.starts(bytes, at: start, with: descriptionKeyword) else { return .none }
        let afterKeyword = start + descriptionKeyword.count
        let colon = Patterns.endOfBlanks(bytes, from: afterKeyword)
        if colon < bytes.count, bytes[colon] == MermaidByte.colon { return .matched(end: Patterns.endBeforeComment(bytes, from: colon + 1)) }
        let brace = JavaScriptWhitespace.endOfRun(in: bytes, from: afterKeyword)
        guard brace < bytes.count, bytes[brace] == MermaidByte.openingBrace,
              let closing = text.firstOccurrence(of: closingBraceNeedle, from: brace + 1) else { return .none }
        return .matched(end: closing + 1)
    }

    private static let descriptionKeyword = Array("accDescr".utf8)
    private static let newlineNeedle = [MermaidByte.newline]
    private static let closingBraceNeedle = [MermaidByte.closingBrace]
}
