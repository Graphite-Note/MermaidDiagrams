/**
 * File: ReferenceUseCaseTokenKind.swift
 * -------------------------------------
 * Layer: Tests
 * Description: The tokens of Mermaid's use case lexer, in an order that makes its token categories ranges, with the
 *              names its errors give them and the sets the parser decides by.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

@testable import MermaidDiagrams

/// Mermaid's token types for use case diagrams (Pele's `T`), in an order that makes its categories ranges: a word is
/// `useCase` to `identifier`, and label text is `useCase` to `labelSymbol`.
enum ReferenceUseCaseTokenKind: UInt8, CaseIterable {
    case end
    case useCase, actor, systemBoundary, endKeyword, direction, topDown, topBottom, bottomTop, leftRight, rightLeft
    case note, forKeyword, json, classDefinition, classKeyword, style, include, extend, trueKeyword, falseKeyword
    case identifier, number, at, comma, colon, hashColor, cssIdentifier, cssEscapedComma, dash, dot, percent
    case cssPunctuation, labelPunctuation, labelSymbol
    case plainString, markdownString, unclosedMarkdownString, comment, newline
    case accessibilityDescriptionBlock, accessibilityTitleLine, accessibilityDescriptionLine
    case jsonDeclarationStart, jsonObjectLiteral, unclosedJSONObjectLiteral
    case generalization, dependencyArrow, stereotypeStart, stereotypeEnd, stereotypeText, unclosedStereotypeText, classSeparator
    case forwardSolid, backwardSolid, forwardCircle, backwardCircle, forwardCross, backwardCross, markerlessSolid
    case metadataStart, leftBrace, rightBrace, leftBracket, rightBracket, leftParenthesis, rightParenthesis

    /// Mermaid's name for the token, as its errors give it (`FORWARD_SOLID`).
    var mermaidName: String { Self.mermaidNames[Int(rawValue)] }

    private static let mermaidNames = ("EOF USECASE ACTOR SYSTEM_BOUNDARY END DIRECTION TD TB BT LR RL NOTE FOR JSON CLASS_DEF CLASS STYLE INCLUDE "
        + "EXTEND TRUE FALSE IDENTIFIER NUMBER AT COMMA COLON HASH_COLOR CSS_IDENTIFIER CSS_ESCAPED_COMMA DASH DOT PERCENT "
        + "CSS_PUNCTUATION LABEL_PUNCTUATION LABEL_SYMBOL PLAIN_STRING MARKDOWN_STRING UNCLOSED_MARKDOWN_STRING COMMENT NEWLINE "
        + "ACC_DESCR_BLOCK ACC_TITLE_LINE ACC_DESCR_LINE JSON_DECLARATION_START JSON_OBJECT_LITERAL UNCLOSED_JSON_OBJECT_LITERAL "
        + "GENERALIZATION DEPENDENCY_ARROW STEREOTYPE_START STEREOTYPE_END STEREOTYPE_TEXT UNCLOSED_STEREOTYPE_TEXT CLASS_SEPARATOR "
        + "FORWARD_SOLID BACKWARD_SOLID FORWARD_CIRCLE BACKWARD_CIRCLE FORWARD_CROSS BACKWARD_CROSS MARKERLESS_SOLID METADATA_START "
        + "LBRACE RBRACE LBRACKET RBRACKET LPAREN RPAREN").split(separator: " ").map(String.init)

    /// A keyword or an identifier: Mermaid's `WORD` category.
    var isWord: Bool { rawValue >= Self.useCase.rawValue && rawValue <= Self.identifier.rawValue }

    /// What an unquoted label is made of: Mermaid's `LABEL_TEXT` category.
    var isLabelText: Bool { rawValue >= Self.useCase.rawValue && rawValue <= Self.labelSymbol.rawValue }

    /// Label text or a string: what may come between a relationship's two operators.
    var isLabelOrString: Bool { rawValue >= Self.useCase.rawValue && rawValue <= Self.markdownString.rawValue }

    /// The length of a keyword's text; 0 for other tokens.
    var keywordLength: Int {
        guard rawValue <= Self.falseKeyword.rawValue else { return 0 }
        return Self.keywordLengths[Int(rawValue)]
    }

    private static let keywordLengths = [0, 12, 5, 14, 3, 9, 2, 2, 2, 2, 2, 4, 3, 4, 8, 5, 5, 7, 6, 4, 5]

    /// Whether the token is in `set`.
    func isIn(_ set: ReferenceUseCaseTokenSet) -> Bool { ReferenceUseCaseTokenSet.flags[Int(rawValue)] & set.rawValue != 0 }
}

/// The sets of tokens the parser decides by, as Pele's `FLAGS` hold them.
struct ReferenceUseCaseTokenSet: OptionSet {
    let rawValue: UInt8

    /// What may start a line at the top level.
    static let line = ReferenceUseCaseTokenSet(rawValue: 1)
    /// What may start a relationship's tail after its source: an explicit id or an operator.
    static let relation = ReferenceUseCaseTokenSet(rawValue: 2)
    /// What a style value is made of.
    static let stylePart = ReferenceUseCaseTokenSet(rawValue: 4)
    /// What may follow a name that starts a statement.
    static let followsName = ReferenceUseCaseTokenSet(rawValue: 8)
    /// What may start a line inside a system boundary.
    static let boundaryLine = ReferenceUseCaseTokenSet(rawValue: 16)
    /// The operators that may close a label after `--`.
    static let closesLabel = ReferenceUseCaseTokenSet(rawValue: 32)
    /// What may follow `@{` in a metadata statement.
    static let metadataFirst = ReferenceUseCaseTokenSet(rawValue: 64)

    private static let operators: [ReferenceUseCaseTokenKind] = [.dependencyArrow, .generalization, .forwardSolid, .backwardSolid, .markerlessSolid,
                                                        .forwardCircle, .backwardCircle, .forwardCross, .backwardCross]
    private static let names: [ReferenceUseCaseTokenKind] = [.identifier, .plainString, .markdownString]
    private static let statements: [ReferenceUseCaseTokenKind] = [.accessibilityTitleLine, .accessibilityDescriptionLine, .accessibilityDescriptionBlock,
                                                         .direction, .actor, .systemBoundary, .note, .jsonDeclarationStart, .classDefinition,
                                                         .classKeyword, .style]
    private static let words = ReferenceUseCaseTokenKind.allCases.filter(\.isWord)
    private static let styleParts: [ReferenceUseCaseTokenKind] = words + [.plainString, .number, .hashColor, .cssIdentifier, .cssEscapedComma, .dash, .dot,
                                                                  .percent, .cssPunctuation, .colon, .leftParenthesis, .rightParenthesis,
                                                                  .leftBracket, .rightBracket, .leftBrace, .rightBrace, .at, .markerlessSolid]

    /// By token, the sets it is in.
    static let flags: [UInt8] = {
        var flags = [UInt8](repeating: 0, count: ReferenceUseCaseTokenKind.allCases.count)
        func add(_ kinds: [ReferenceUseCaseTokenKind], to set: ReferenceUseCaseTokenSet) {
            for kind in kinds { flags[Int(kind.rawValue)] |= set.rawValue }
        }
        add([.newline, .comment] + statements + names, to: .line)
        add([.identifier] + operators, to: .relation)
        add(styleParts, to: .stylePart)
        add([.stereotypeStart, .classSeparator, .identifier] + operators + [.newline, .end], to: .followsName)
        add([.newline, .comment, .actor] + names, to: .boundaryLine)
        add([.forwardSolid, .markerlessSolid, .forwardCircle, .forwardCross], to: .closesLabel)
        add([.newline, .identifier, .plainString, .rightBrace], to: .metadataFirst)
        return flags
    }()
}
