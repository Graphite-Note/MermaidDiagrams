/**
 * File: RailroadSyntaxProblem.swift
 * ---------------------------------
 * Layer: Core
 * Description: What the railroad diagram reader found where the syntax of one of Mermaid's four railroad grammars broke.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// What the railroad diagram reader found where the syntax broke, beyond the problems every type shares.
public enum RailroadSyntaxProblem: Equatable, Sendable {
    /// The keyword is not written in lower case (`RAILROAD-BETA`), or more of a name follows it (`railroad-beta-x`):
    /// Mermaid detects such a diagram as a railroad diagram and its grammar then refuses it.
    case expectedKeyword(String)
    /// A rule's name was expected, at the start of a rule.
    case expectedRuleName
    /// A rule's name is not followed by its sign: `=` (or `::=` in EBNF), or `<-` in a PEG.
    case expectedDefinitionSign
    /// A rule does not end with `;` (in ABNF, a `;` at the end of its line).
    case expectedSemicolon
    /// A part of a rule was expected: a terminal, a name, a special sequence, a constructor or an opening bracket.
    case expectedExpression
    /// A bracket or a constructor's parenthesis is not closed where its content ends, by the closing sign expected.
    case expectedClosing(String)
    /// A constructor (`terminal`, `sequence` …) is not followed by `(`.
    case expectedOpeningParenthesis
    /// `terminal`, `nonterminal` or `special` is not given text in quotation marks.
    case expectedQuotedText
}
