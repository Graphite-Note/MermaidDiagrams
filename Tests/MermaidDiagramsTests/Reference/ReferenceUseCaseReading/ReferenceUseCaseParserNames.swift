/**
 * File: ReferenceUseCaseParserNames.swift
 * ---------------------------------------
 * Layer: Tests
 * Description: What a use case diagram's statements are made of, as Pele's parser.ts reads them: names with their
 *              labels, metadata, stereotypes, class suffixes, lists of identifiers and styles.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

@testable import MermaidDiagrams

import Foundation

/// One mention of an element: its name, and what this mention says of it.
struct ReferenceUseCaseParsedItem {
    var name: ReferenceUseCaseDraftName
    var shape: UseCaseShape?
    var metadata: [ReferenceUseCaseDraftProperty]?
    var stereotype: String?
    var classes: [String] = []
    /// Whether this mention says something about the element, and so declares it.
    var isExplicit = false
}

extension ReferenceUseCaseParser {
    /// Where a name or a string's text is: without its quotation marks, or a Markdown string's quotation marks and
    /// backticks.
    func contentRange(of token: Int) -> Range<Int> {
        let trim = tokens.kinds[token] == .markdownString ? 2 : tokens.kinds[token] == .plainString ? 1 : 0
        return (tokens.starts[token] + trim)..<max(tokens.starts[token] + trim, tokens.ends[token] - trim)
    }

    func tokenLabel(_ token: Int) -> ReferenceUseCaseDraftLabel {
        let content = contentRange(of: token)
        return ReferenceUseCaseDraftLabel(text: text.text(from: content.lowerBound, to: content.upperBound),
                                 type: tokens.kinds[token] == .markdownString ? .markdown : .text, start: content.lowerBound)
    }

    /// A string, or unquoted text taken from the source as written up to the next delimiter.
    mutating func label() throws(MermaidDiagramReadError) -> ReferenceUseCaseDraftLabel {
        if current == .plainString || current == .markdownString {
            index += 1
            return tokenLabel(index - 1)
        }
        guard current.isLabelText else { throw unexpected(.label) }
        let first = index
        while current.isLabelText { index += 1 }
        return ReferenceUseCaseDraftLabel(text: text.text(from: tokens.starts[first], to: tokens.ends[index - 1]), type: .text, start: tokens.starts[first])
    }

    /// An id with an optional label in parentheses (or, with `brackets`, brackets), or a string that stands for both.
    mutating func name(allowingBrackets brackets: Bool) throws(MermaidDiagramReadError) -> ReferenceUseCaseParsedItem {
        let first = index
        let kind = current
        let start = contentRange(of: first).lowerBound
        switch kind {
        case .identifier:
            index += 1
            let open = current
            guard open == .leftParenthesis || (brackets && open == .leftBracket) else {
                return ReferenceUseCaseParsedItem(name: ReferenceUseCaseDraftName(identifier: image(first), label: tokenLabel(first), start: start, isGenerated: false))
            }
            index += 1
            let label = try label()
            _ = try expect(open == .leftParenthesis ? .rightParenthesis : .rightBracket)
            return ReferenceUseCaseParsedItem(name: ReferenceUseCaseDraftName(identifier: image(first), label: label, start: start, isGenerated: false),
                                     shape: open == .leftParenthesis ? .ellipse : .rectangle)
        case .plainString, .markdownString:
            index += 1
            let label = tokenLabel(first)
            return ReferenceUseCaseParsedItem(name: ReferenceUseCaseDraftName(identifier: Self.generatedIdentifier(label.text), label: label, start: start, isGenerated: true))
        default: throw unexpected(.name)
        }
    }

    /// A name and what may follow it: metadata, a stereotype and classes, in that order.
    mutating func element(isActor: Bool) throws(MermaidDiagramReadError) -> ReferenceUseCaseParsedItem {
        var item = try name(allowingBrackets: !isActor)
        if isActor { item.shape = nil }
        if current == .metadataStart { item.metadata = try metadata() }
        if current == .stereotypeStart {
            index += 1
            let stereotype = try expect(.stereotypeText)
            _ = try expect(.stereotypeEnd)
            item.stereotype = ReferenceUseCaseCharacters.trimmed(image(stereotype))
        }
        if current == .classSeparator { try classSuffix(&item.classes) }
        item.isExplicit = item.shape != nil || item.metadata != nil || item.stereotype != nil
        return item
    }

    /// `:::` and its comma-separated classes.
    mutating func classSuffix(_ classes: inout [String]) throws(MermaidDiagramReadError) {
        repeat {
            index += 1
            classes.append(image(try expect(.identifier)))
        } while current == .comma
    }

    private func isKey(_ kind: ReferenceUseCaseTokenKind) -> Bool { kind == .identifier || kind == .plainString }

    private mutating func property() throws(MermaidDiagramReadError) -> ReferenceUseCaseDraftProperty {
        let key = index
        guard isKey(current) else { throw unexpected(.metadataKey) }
        index += 1
        _ = try expect(.colon)
        let value = index
        let kind = current
        guard isKey(kind) || kind == .trueKeyword || kind == .falseKeyword else { throw unexpected(.metadataValue) }
        index += 1
        let keyContent = contentRange(of: key)
        let valueContent = contentRange(of: value)
        let written: ReferenceUseCaseMetadataValue = kind == .trueKeyword ? .boolean(true) : kind == .falseKeyword ? .boolean(false)
            : .text(text.text(from: valueContent.lowerBound, to: valueContent.upperBound))
        return ReferenceUseCaseDraftProperty(key: text.text(from: keyContent.lowerBound, to: keyContent.upperBound), value: written, keyStart: keyContent.lowerBound)
    }

    /// Whether another property follows. A comma or line breaks before the closing brace do not count, but Chevrotain
    /// looks only three tokens ahead, so a comma and two line breaks, or three line breaks, are taken for a separator
    /// and the brace after them is then an error.
    private func separatorAhead() -> Bool {
        let first = current
        let second = kind(at: index + 1)
        let third = kind(at: index + 2)
        if first == .comma { return isKey(second) || (second == .newline && (third == .newline || isKey(third))) }
        guard first == .newline else { return false }
        return second == .comma || isKey(second) || (second == .newline && (third == .newline || third == .comma || isKey(third)))
    }

    /// `@{ key: value, … }`, its properties separated by commas or line breaks.
    mutating func metadata() throws(MermaidDiagramReadError) -> [ReferenceUseCaseDraftProperty] {
        _ = try expect(.metadataStart)
        var properties: [ReferenceUseCaseDraftProperty] = []
        skipLineBreaks()
        if isKey(current) {
            properties.append(try property())
            while separatorAhead() {
                if current == .comma {
                    index += 1
                } else {
                    skipLineBreaks()
                    if current == .comma { index += 1 }
                }
                skipLineBreaks()
                properties.append(try property())
            }
            if current == .comma { index += 1 }
            skipLineBreaks()
        }
        _ = try expect(.rightBrace)
        return properties
    }

    private mutating func skipLineBreaks() {
        while current == .newline { index += 1 }
    }

    /// Comma-separated identifiers.
    mutating func identifierList() throws(MermaidDiagramReadError) -> [Int] {
        var identifiers = [try expect(.identifier)]
        while current == .comma {
            index += 1
            identifiers.append(try expect(.identifier))
        }
        return identifiers
    }

    /// Comma-separated `property: value` styles, each taken from the source as written, `\,` read as a comma.
    mutating func styles() throws(MermaidDiagramReadError) -> [String] {
        var styles = [try style()]
        while current == .comma {
            index += 1
            styles.append(try style())
        }
        return styles
    }

    private mutating func style() throws(MermaidDiagramReadError) -> String {
        let first = index
        if current.isWord || current == .cssIdentifier {
            index += 1
        } else if current == .markerlessSolid {
            index += 1
            guard current.isWord else { throw unexpected(.token("WORD")) }
            index += 1
        } else {
            throw unexpected(.styleProperty)
        }
        _ = try expect(.colon)
        guard current.isIn(.stylePart) else { throw unexpected(.styleValue) }
        while current.isIn(.stylePart) { index += 1 }
        return text.text(from: tokens.starts[first], to: tokens.ends[index - 1]).replacingOccurrences(of: "\\,", with: ",")
    }
}
