/**
 * File: ReferenceFirstMatchStatementValues.swift
 * ----------------------------------------------
 * Layer: Tests
 * Description: 0.7.0's values of the title and accessibility statements of Langium's grammars, frozen as main dad6fb8
 *              gave them through Foundation's search, which the values read on bytes are compared with.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import Foundation
@testable import MermaidDiagrams

/// The values of the title and accessibility statements of Langium's grammars, as Mermaid's value converters give them.
enum ReferenceFirstMatchStatementValues {
    /// After `title`, trimmed, each run of two or more blanks one space.
    static func title(of statement: String) -> String {
        single(String(text(after: "title", in: statement)))
    }

    /// After `accTitle` and its colon, trimmed, runs of blanks one space.
    static func accessibilityTitle(of statement: String) -> String {
        let afterKeyword = text(after: "accTitle", in: statement)
        return single(String(afterKeyword.drop { character in character != ":" }.dropFirst()))
    }

    /// After `accDescr` and its colon as for a title; or the text between its braces, each line trimmed, blank lines
    /// left out, and runs of blanks one space.
    static func accessibilityDescription(of statement: String) -> String {
        let afterKeyword = text(after: "accDescr", in: statement)
        let written = afterKeyword.drop { character in character == " " || character == "\t" }
        if written.first == ":" { return single(String(written.dropFirst())) }
        let inside = afterKeyword.drop { character in character != "{" }.dropFirst().prefix { character in character != "}" }
        // `\r\n` is one Character in Swift: it breaks a line as `\n` and `\r` do, as Pele makes every line break `\n` first.
        let lines = inside.split(omittingEmptySubsequences: false) { character in character == "\n" || character == "\r" || character == "\r\n" }
            .map { line in trimmed(String(line)) }
            .filter { line in !line.isEmpty }
        return lines.map(collapsingBlanks).joined(separator: "\n")
    }

    /// The text after the first `keyword` in `statement`.
    private static func text(after keyword: String, in statement: String) -> Substring {
        guard let range = statement.range(of: keyword) else { return "" }
        return statement[range.upperBound...]
    }

    private static func single(_ text: String) -> String {
        collapsingBlanks(trimmed(text))
    }

    /// The text without JavaScript's whitespace at either end, as `trim` leaves it.
    static func trimmed(_ text: String) -> String {
        String(decoding: JavaScriptWhitespace.trimmed(Array(text.utf8)[...]), as: UTF8.self)
    }

    /// Each run of two or more spaces and tabs as one space.
    private static func collapsingBlanks(_ text: String) -> String {
        guard MermaidByte.hasBlankRun(text), text.contains("  ") || text.contains("\t") else { return text }
        var result = ""
        var blankRun = ""
        for character in text {
            if character == " " || character == "\t" {
                blankRun.append(character)
                continue
            }
            result += blankRun.count >= 2 ? " " : blankRun
            blankRun = ""
            result.append(character)
        }
        return result + (blankRun.count >= 2 ? " " : blankRun)
    }
}
