/**
 * File: RailroadLexers.swift
 * --------------------------
 * Layer: Core
 * Description: The token rules of Mermaid's four railroad grammars, each in its lexer's order: Mermaid's constructor
 *              notation, EBNF, ABNF and PEG, with the title, accessibility and hidden tokens they share.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// A token of a railroad diagram's text, in any of its notations.
enum RailroadTokenKind: Equatable, Sendable {
    /// One of the constructor notation's words (`terminal`, `sequence` …), by its text.
    case constructor(String)
    /// A sign, by its text: `=`, `::=`, `<-`, `;`, `,`, `|`, `/`, `&`, `!`, `?`, `*`, `+`, `-`, `.`, and the brackets.
    case sign(String)
    case title
    case accessibilityTitle
    case accessibilityDescription
    case name
    /// Text in quotation marks.
    case string
    /// EBNF's `? … ?`.
    case specialSequence
    /// ABNF's `%x41`, `%d65.66`, `%x30-39`.
    case numberValue
    /// ABNF's `2*4` before an element, and its exact count (`3`).
    case repeatCount
    case exactRepeatCount
}

/// Mermaid's railroad tokens per notation, in the order its generated lexers try them (`IR_TOKENS`, `EBNF_TOKENS`,
/// `ABNF_TOKENS` and `PEG_TOKENS` in Pele). The keyword comes first in each and is read by `MermaidDiagramReader`.
enum RailroadLexers {
    typealias Rule = FirstMatchTokenRule<RailroadTokenKind>
    typealias Patterns = FirstMatchTokenPatterns

    static let constructorWords = ["nonterminal", "zeroOrMore", "oneOrMore", "sequence", "optional", "terminal", "special", "choice"]

    static let constructorNotation = FirstMatchTokenizer(rules: constructorWords.map(constructor) + [
        sign("="), sign(";"), sign("("), sign(","), sign(")"),
    ] + statements(nameContinues: isNameContinuation) + [identifier, quoted] + hidden + [
        Rule("RR_BLOCK_COMMENT", kind: nil, firstBytes: bytes("/"), match: Patterns.blockComment(opening: "/*", closing: "*/")),
    ])

    static let extendedBackusNaurForm = FirstMatchTokenizer(rules: [
        sign("::="), sign("="), sign(";"), sign("|"), sign(","), sign("(", longer: ["EBNF_ISO_COMMENT"]), sign(")"), sign("["), sign("]"),
        sign("{"), sign("}"), sign("?", longer: ["EBNF_SPECIAL_SEQUENCE"]), sign("*"), sign("+"), sign("-", longer: ["RR_YAML"]),
    ] + statements(nameContinues: isNameContinuation) + [
        identifier, quoted, Rule("EBNF_SPECIAL_SEQUENCE", kind: .specialSequence, firstBytes: bytes("?"), match: specialSequence),
    ] + hidden + [
        Rule("EBNF_BLOCK_COMMENT", kind: nil, firstBytes: bytes("/"), match: Patterns.blockComment(opening: "/*", closing: "*/")),
        Rule("EBNF_ISO_COMMENT", kind: nil, firstBytes: bytes("("), match: Patterns.blockComment(opening: "(*", closing: "*)")),
    ])

    static let augmentedBackusNaurForm = FirstMatchTokenizer(rules: [
        sign("="), sign(";", longer: ["ABNF_COMMENT"]), sign("/"), sign("("), sign(")"), sign("["), sign("]"),
    ] + statements(nameContinues: isAugmentedNameByte) + [
        Rule("ABNF_RULENAME", kind: .name, firstBytes: letters, match: Patterns.name(first: MermaidByte.isLetter, rest: isAugmentedNameByte)),
        Rule("ABNF_STRING", kind: .string, firstBytes: bytes("\""), match: plainString),
        Rule("ABNF_NUMVAL", kind: .numberValue, firstBytes: bytes("%"), match: numberValue),
        Rule("ABNF_REPEAT", kind: .repeatCount, firstBytes: bytes("0123456789*"), match: repeatCount),
        Rule("ABNF_EXACT_REPEAT", kind: .exactRepeatCount, firstBytes: bytes("0123456789"),
             match: Patterns.name(first: MermaidByte.isDigit, rest: MermaidByte.isDigit)),
    ] + hidden + [
        Rule("ABNF_COMMENT", kind: nil, firstBytes: bytes(";"), match: Patterns.lineComment(opening: ";")),
    ])

    static let parsingExpressionGrammar = FirstMatchTokenizer(rules: [
        sign("<-"), sign(";"), sign("/"), sign("&"), sign("!"), sign("?"), sign("*"), sign("+"), sign("("), sign(")"), sign("."),
    ] + statements(nameContinues: isNameContinuation) + [identifier, quoted] + hidden + [
        Rule("PEG_LINE_COMMENT", kind: nil, firstBytes: bytes("#"), match: Patterns.lineComment(opening: "#")),
    ])

    /// The tokenizer of `notation`.
    static func tokenizer(of notation: RailroadNotation) -> FirstMatchTokenizer<RailroadTokenKind> {
        switch notation {
        case .railroad: constructorNotation
        case .extendedBackusNaurForm: extendedBackusNaurForm
        case .augmentedBackusNaurForm: augmentedBackusNaurForm
        case .parsingExpressionGrammar: parsingExpressionGrammar
        }
    }

    private static let identifierName = "RR_ID"
    private static let letters = bytes("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")

    /// `[A-Z_a-z][\w-]*`.
    private static let identifier = Rule(identifierName, kind: .name, firstBytes: letters + bytes("_"),
                                         match: Patterns.name(first: { byte in MermaidByte.isLetter(byte) || byte == MermaidByte.underscore },
                                                              rest: isNameContinuation))
    private static let quoted = Rule("RR_STRING", kind: .string, firstBytes: bytes("\"'"), match: Patterns.quoted)

    /// Whitespace, front matter fences, directives and `%%` comments, in the order every railroad grammar lists them.
    private static let hidden = [
        Rule("RR_WHITESPACE", kind: nil, firstBytes: bytes("\t \r\n"), match: Patterns.whitespace(isJavaScriptWhitespace: false)),
        Rule("RR_YAML", kind: nil, firstBytes: bytes("-"), match: Patterns.frontMatterFence),
        Rule("RR_DIRECTIVE", kind: nil, firstBytes: bytes("\t %"), match: Patterns.directive),
        Rule("RR_SINGLE_LINE_COMMENT", kind: nil, firstBytes: bytes("\t %"), match: Patterns.percentComment),
    ]

    /// `title`, `accTitle` and `accDescr`, which unlike Mermaid's common grammar take no blanks before them; a title's
    /// keyword followed by a byte `nameContinues` allows is the start of a name.
    private static func statements(nameContinues: @escaping @Sendable (UInt8) -> Bool) -> [Rule] {
        [
            Rule("TITLE", kind: .title, firstBytes: bytes("t"), match: Patterns.lineStatement("title", leadingBlanks: false, continuesName: nameContinues)),
            Rule("ACC_TITLE", kind: .accessibilityTitle, firstBytes: bytes("a"), match: Patterns.accessibilityTitle(leadingBlanks: false)),
            Rule("ACC_DESCR", kind: .accessibilityDescription, firstBytes: bytes("a"), match: accessibilityDescription),
        ]
    }

    private static func constructor(_ word: String) -> Rule {
        Rule(word, kind: .constructor(word), firstBytes: [word.utf8.first ?? 0], longerAlternatives: [identifierName], match: Patterns.literal(word))
    }

    private static func sign(_ text: String, longer: [String] = []) -> Rule {
        Rule(text, kind: .sign(text), firstBytes: [text.utf8.first ?? 0], longerAlternatives: longer, match: Patterns.literal(text))
    }

    private static func bytes(_ text: String) -> [UInt8] {
        Array(text.utf8)
    }

    /// `[\w-]`.
    @Sendable private static func isNameContinuation(_ byte: UInt8) -> Bool {
        Patterns.isWordByte(byte) || byte == MermaidByte.hyphen
    }

    /// `[A-Za-z0-9-]`.
    @Sendable private static func isAugmentedNameByte(_ byte: UInt8) -> Bool {
        MermaidByte.isLetter(byte) || MermaidByte.isDigit(byte) || byte == MermaidByte.hyphen
    }

    /// `accDescr`, blanks, then `:` and the rest of the line up to `%%`; or whitespace and `{` up to the next `}`.
    private static let accessibilityDescription: FirstMatchTokenPattern = { text, position in
        let bytes = text.bytes
        guard Patterns.starts(bytes, at: position, with: descriptionKeyword) else { return .none }
        let afterKeyword = Patterns.endOfBlanks(bytes, from: position + descriptionKeyword.count)
        if afterKeyword < bytes.count, bytes[afterKeyword] == MermaidByte.colon {
            return .matched(end: Patterns.endBeforeComment(bytes, from: afterKeyword + 1))
        }
        let brace = JavaScriptWhitespace.endOfRun(in: bytes, from: afterKeyword)
        guard brace < bytes.count, bytes[brace] == MermaidByte.openingBrace,
              let closing = text.firstOccurrence(of: [MermaidByte.closingBrace], from: brace + 1) else { return .none }
        return .matched(end: closing + 1)
    }

    /// A question mark, text with something other than whitespace in it and no `?` or `;`, and a question mark.
    private static let specialSequence: FirstMatchTokenPattern = { text, position in
        let bytes = text.bytes
        guard bytes[position] == UInt8(ascii: "?") else { return .none }
        var hasText = false
        var index = position + 1
        while index < bytes.count {
            let byte = bytes[index]
            if byte == UInt8(ascii: "?") { return hasText ? .matched(end: index + 1) : .none }
            if byte == MermaidByte.semicolon { return .none }
            let whitespace = JavaScriptWhitespace.length(in: bytes, at: index)
            if whitespace == 0 { hasText = true }
            index += max(1, whitespace)
        }
        return .none
    }

    /// `"[^"]*"`: ABNF's strings have no escapes.
    private static let plainString: FirstMatchTokenPattern = { text, position in
        guard let closing = text.firstOccurrence(of: [MermaidByte.quotationMark], from: position + 1) else { return .noneFurtherOn }
        return .matched(end: closing + 1)
    }

    /// `%[xXdDbB][0-9A-Fa-f]+(?:-[0-9A-Fa-f]+|\.[0-9A-Fa-f]+)*`.
    private static let numberValue: FirstMatchTokenPattern = { text, position in
        let bytes = text.bytes
        guard position + 2 < bytes.count, Array("xXdDbB".utf8).contains(bytes[position + 1]), isHexadecimal(bytes[position + 2]) else { return .none }
        var end = position + 2
        while end < bytes.count, isHexadecimal(bytes[end]) { end += 1 }
        while end + 1 < bytes.count, bytes[end] == MermaidByte.hyphen || bytes[end] == MermaidByte.period, isHexadecimal(bytes[end + 1]) {
            end += 1
            while end < bytes.count, isHexadecimal(bytes[end]) { end += 1 }
        }
        return .matched(end: end)
    }

    /// `[0-9]*\*[0-9]*`.
    private static let repeatCount: FirstMatchTokenPattern = { text, position in
        let bytes = text.bytes
        var end = position
        while end < bytes.count, MermaidByte.isDigit(bytes[end]) { end += 1 }
        guard end < bytes.count, bytes[end] == UInt8(ascii: "*") else { return .none }
        end += 1
        while end < bytes.count, MermaidByte.isDigit(bytes[end]) { end += 1 }
        return .matched(end: end)
    }

    @Sendable private static func isHexadecimal(_ byte: UInt8) -> Bool {
        MermaidByte.isDigit(byte) || (byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "f")) || (byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "F"))
    }

    private static let descriptionKeyword = Array("accDescr".utf8)
}
