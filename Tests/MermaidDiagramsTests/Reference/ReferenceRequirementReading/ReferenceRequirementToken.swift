/**
 * File: ReferenceRequirementToken.swift
 * -------------------------------------
 * Layer: Tests
 * Description: 0.7.0's RequirementToken, kept unchanged but for its names as the reference the requirement reader on
 *              bytes is compared with (RequirementReadingEquivalenceTests).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

@testable import MermaidDiagrams

/// A token of a requirement diagram's text: what it is, where it starts (for an error's line) and the bytes of its text.
struct ReferenceRequirementToken: Equatable {
    let kind: ReferenceRequirementTokenKind
    let start: Int
    /// The bytes of its text: an unquoted text without the whitespace at its ends, a quoted one without its quotation
    /// marks, a value without what introduced it.
    let textRange: Range<Int>
}

/// What a token is, after Jison's token names in Mermaid's `requirementDiagram.jison` and Pele's `tokens.ts`.
enum ReferenceRequirementTokenKind: Equatable {
    /// `$end`, after the last token.
    case endOfTokens
    /// A character no rule matches: the lexer stops there.
    case unreadable
    case title
    /// `accTitle:` and its value; `accDescr:` and its value; the text of `accDescr { … }`.
    case accessibilityTitle
    case accessibilityTitleValue
    case accessibilityDescription
    case accessibilityDescriptionValue
    case accessibilityDescriptionBlockValue
    /// A line that holds `direction` and a direction anywhere, to the end of the line the direction ends on.
    case direction(FlowchartDirection)
    /// One or more line breaks.
    case lineBreak
    /// `EOF`: the end of the text outside a string, a value or a style statement.
    case endOfText
    /// `requirementDiagram`, in any case.
    case diagramKeyword
    case openingBrace
    case closingBrace
    /// `:::`.
    case styleSeparator
    /// `:` outside a style statement.
    case fieldSeparator
    case field(ReferenceRequirementFieldName)
    case requirementKind(RequirementKind)
    case risk(RequirementRisk)
    case verificationMethod(RequirementVerificationMethod)
    case element
    case relation(RequirementRelationKind)
    /// `style`, `classDef` and `class`, after which the lexer reads a style statement to its line's end.
    case style
    case classDefinition
    case classAssignment
    /// In a style statement: a run of word characters, `:`, `;`, `%`, `-` and `#`.
    case styleWord
    case styleColon
    case styleSemicolon
    case stylePercent
    case styleMinus
    case styleNumberSign
    /// `<-`, `->` and `-`.
    case leftArrowEnd
    case rightArrowEnd
    case line
    case quotedText
    case unquotedText
    case comma

    /// A part of a style declaration (`isStylePart` in Pele's parser).
    var isStylePart: Bool {
        switch self {
        case .styleWord, .styleColon, .styleNumberSign, .styleMinus, .styleSemicolon: true
        default: false
        }
    }
}

/// The fields of a requirement's and an element's body.
enum ReferenceRequirementFieldName: Equatable {
    case identifier, text, risk, verificationMethod, type, documentReference

    var isRequirementField: Bool {
        switch self {
        case .identifier, .text, .risk, .verificationMethod: true
        case .type, .documentReference: false
        }
    }
}

enum ReferenceRequirementKeywords {
    /// The longest keyword, `functionalrequirement` and `performancerequirement` and `requirementdiagram` among them: a
    /// longer word is never looked up.
    static let longestKeywordLength = 22

    /// Every keyword, lower case: the lexer matches them without regard to case.
    static let byLowercaseWord: [String: ReferenceRequirementTokenKind] = {
        var keywords: [String: ReferenceRequirementTokenKind] = [
            "requirementdiagram": .diagramKeyword, "id": .field(.identifier), "text": .field(.text), "risk": .field(.risk),
            "verifymethod": .field(.verificationMethod), "element": .element, "type": .field(.type), "docref": .field(.documentReference),
            "style": .style, "classdef": .classDefinition, "class": .classAssignment,
            "requirement": .requirementKind(.requirement), "functionalrequirement": .requirementKind(.functionalRequirement),
            "interfacerequirement": .requirementKind(.interfaceRequirement), "performancerequirement": .requirementKind(.performanceRequirement),
            "physicalrequirement": .requirementKind(.physicalRequirement), "designconstraint": .requirementKind(.designConstraint),
            "low": .risk(.low), "medium": .risk(.medium), "high": .risk(.high),
            "analysis": .verificationMethod(.analysis), "demonstration": .verificationMethod(.demonstration),
            "inspection": .verificationMethod(.inspection), "test": .verificationMethod(.test),
        ]
        for relation in RequirementRelationKind.allCases { keywords[relation.rawValue] = .relation(relation) }
        return keywords
    }()
}
