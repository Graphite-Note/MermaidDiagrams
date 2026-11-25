/**
 * File: QuadrantChartToken.swift
 * ------------------------------
 * Layer: Core
 * Description: A token of a quadrant chart's text: its kind, where it lies, its line and the ranges of the bytes it
 *              holds, a few integers that copy without reference counting; and the sets of kinds the grammar reads
 *              texts, class names and styles from, tested without hashing.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.3
 * Date: 25/11/2026
 */

/// A piece of a quadrant chart's text, as Mermaid's quadrant grammar cuts it: what it is, where it starts and ends in
/// the diagram's UTF-8 bytes, the line it starts on, and what it holds as ranges of those bytes.
struct QuadrantChartToken: Equatable {
    let kind: QuadrantChartTokenKind
    private let startOffset: Int32
    private let endOffset: Int32
    private let lineNumber: Int32
    /// A title's text, a quoted or Markdown string's text, a class's name, or a point's x coordinate as written; empty
    /// for the others.
    let content: MermaidTextRange
    /// A point's y coordinate as written; for an accessibility statement, its index among the lexer's statements.
    let second: MermaidTextRange

    init(kind: QuadrantChartTokenKind, start: Int, end: Int, line: Int, content: MermaidTextRange = .empty, second: MermaidTextRange = .empty) {
        self.kind = kind
        startOffset = Int32(truncatingIfNeeded: start)
        endOffset = Int32(truncatingIfNeeded: end)
        lineNumber = Int32(truncatingIfNeeded: line)
        self.content = content
        self.second = second
    }

    var start: Int { Int(startOffset) }
    var end: Int { Int(endOffset) }
    var line: Int { Int(lineNumber) }
}

/// A quadrant chart's tokens, and the accessibility statements its accessibility tokens stand for.
struct QuadrantChartTokens {
    var tokens: [QuadrantChartToken] = []
    var statements: [MermaidAccessibilityStatement] = []
}

/// What a piece of a quadrant chart's text is. Keywords, the axis arrow and a point's start take the spaces around
/// them; other text is cut into runs of letters, of digits and of characters beyond ASCII, and single characters.
enum QuadrantChartTokenKind: UInt8, Hashable {
    /// One or more line breaks or carriage returns.
    case lineBreak
    /// `title` and the rest of its line, which is the title.
    case title
    /// `accTitle: …`, `accDescr: …` or `accDescr { … }`.
    case accessibility
    case xAxis
    case yAxis
    /// `-->`: two or more hyphens and `>`, between an axis's two texts.
    case axisArrow
    case quadrant1
    case quadrant2
    case quadrant3
    case quadrant4
    /// `quadrantChart` again, which no statement takes.
    case chartKeyword
    case classDefinition
    /// Text in quotation marks.
    case string
    /// A Markdown string, between "` and `".
    case markdownString
    /// `:::` and a class's name.
    case className
    /// `: [x, y]`.
    case point
    case letters
    /// Characters beyond ASCII.
    case otherCharacters
    case digits
    case colon
    case comma
    case hyphen
    case numberSign
    /// A space, a tab, a vertical tab or a form feed.
    case space
    case semicolon
    case ampersand
    case asterisk
    /// `+`, `=`, `_`, `.`, `!`, `$`, `%`, `'`, `` ` ``, `?`, `\` or `/`.
    case otherPunctuation

    /// Mermaid's `WORD` tokens: what a text may start with besides a string, and holds after it.
    static let wordPieces: QuadrantChartTokenKindSet = [.otherPunctuation, .ampersand, .asterisk, .digits, .letters, .comma, .numberSign,
                                                         .otherCharacters]
    /// What a text may start with.
    static let textStarts = wordPieces.union([.string, .markdownString])
    /// What a text holds after its first piece.
    static let textContinuations = wordPieces.union([.space, .hyphen])
    /// What a class's name after `classDef` is made of.
    static let classNamePieces: QuadrantChartTokenKindSet = [.letters, .digits, .hyphen, .comma, .colon, .ampersand, .numberSign, .asterisk,
                                                                .otherCharacters]
    /// What a style (`stroke-width: 10px`) is made of.
    static let stylePieces: QuadrantChartTokenKindSet = [.letters, .digits, .colon, .space, .numberSign, .hyphen]
    /// The quadrant keywords, quadrant 1 first.
    static let quadrants: [QuadrantChartTokenKind] = [.quadrant1, .quadrant2, .quadrant3, .quadrant4]
}

/// A set of token kinds held in the bits of one integer, tested without hashing as the parser tests each token.
struct QuadrantChartTokenKindSet: ExpressibleByArrayLiteral {
    private let bits: UInt64

    init(arrayLiteral kinds: QuadrantChartTokenKind...) {
        bits = kinds.reduce(0) { bits, kind in bits | Self.bit(kind) }
    }

    private init(bits: UInt64) {
        self.bits = bits
    }

    @inline(__always)
    func contains(_ kind: QuadrantChartTokenKind) -> Bool {
        bits & Self.bit(kind) != 0
    }

    func union(_ other: QuadrantChartTokenKindSet) -> QuadrantChartTokenKindSet {
        QuadrantChartTokenKindSet(bits: bits | other.bits)
    }

    @inline(__always)
    private static func bit(_ kind: QuadrantChartTokenKind) -> UInt64 {
        1 << UInt64(kind.rawValue)
    }
}
