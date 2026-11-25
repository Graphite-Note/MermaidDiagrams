/**
 * File: UseCaseParserNames.swift
 * ------------------------------
 * Layer: Core
 * Description: The parts of a use case diagram's statements that name things: labels, names and the shapes, metadata,
 *              stereotypes and classes that may follow them, identifier lists and style lists, as Pele's parser.ts
 *              reads them, each kept as a range of the text or an interned name.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 25/11/2026
 */

import Foundation

/// One mention of an element: its name, and what this mention says of it.
struct UseCaseParsedItem {
    var name: UseCaseDraftName
    var shape: UseCaseShape?
    var metadata = UseCaseListSpan.empty
    var hasMetadata = false
    var stereotype = MermaidTextRange.empty
    var hasStereotype = false
    var classes = UseCaseListSpan.empty
    /// Whether this mention says something about the element, and so declares it.
    var isExplicit = false
}

extension UseCaseParser {
    /// Where a name or a string's text is: without its quotation marks, or a Markdown string's quotation marks and
    /// backticks.
    func contentRange(of token: Int) -> MermaidTextRange {
        let trim = tokens.kinds[token] == .markdownString ? 2 : tokens.kinds[token] == .plainString ? 1 : 0
        return MermaidTextRange(start: tokens.starts[token] + trim, end: max(tokens.starts[token] + trim, tokens.ends[token] - trim))
    }

    func tokenLabel(_ token: Int) -> UseCaseLabelText {
        UseCaseLabelText(text: contentRange(of: token), type: tokens.kinds[token] == .markdownString ? .markdown : .text)
    }

    /// A string, or unquoted text taken from the source as written up to the next delimiter.
    mutating func label() throws(MermaidDiagramReadError) -> UseCaseLabelText {
        if current == .plainString || current == .markdownString {
            index += 1
            return tokenLabel(index - 1)
        }
        guard current.isLabelText else { throw unexpected(.label) }
        let first = index
        while current.isLabelText { index += 1 }
        return UseCaseLabelText(text: MermaidTextRange(start: tokens.starts[first], end: tokens.ends[index - 1]), type: .text)
    }

    /// An id with an optional label in parentheses (or, with `brackets`, brackets), or a string that stands for both.
    mutating func name(allowingBrackets brackets: Bool) throws(MermaidDiagramReadError) -> UseCaseParsedItem {
        let first = index
        let kind = current
        let start = Int32(contentRange(of: first).lowerBound)
        switch kind {
        case .identifier:
            index += 1
            let open = current
            let name = name(of: first)
            guard open == .leftParenthesis || (brackets && open == .leftBracket) else {
                return UseCaseParsedItem(name: UseCaseDraftName(name: name, label: tokenLabel(first), start: start, isGenerated: false))
            }
            index += 1
            let label = try label()
            _ = try expect(open == .leftParenthesis ? .rightParenthesis : .rightBracket)
            return UseCaseParsedItem(name: UseCaseDraftName(name: name, label: label, start: start, isGenerated: false),
                                     shape: open == .leftParenthesis ? .ellipse : .rectangle)
        case .plainString, .markdownString:
            index += 1
            let label = tokenLabel(first)
            return UseCaseParsedItem(name: UseCaseDraftName(name: generatedName(label.text), label: label, start: start, isGenerated: true))
        default: throw unexpected(.name)
        }
    }

    /// A name and what may follow it: metadata, a stereotype and classes, in that order.
    mutating func element(isActor: Bool) throws(MermaidDiagramReadError) -> UseCaseParsedItem {
        var item = try name(allowingBrackets: !isActor)
        if isActor { item.shape = nil }
        if current == .metadataStart {
            item.metadata = try metadata()
            item.hasMetadata = true
        }
        if current == .stereotypeStart {
            index += 1
            let stereotype = try expect(.stereotypeText)
            _ = try expect(.stereotypeEnd)
            let bytes = text.bytes
            item.stereotype = bytes.withUnsafeBufferPointer { buffer in UseCaseCharacters.trimmed(range(of: stereotype), in: buffer) }
            item.hasStereotype = true
        }
        if current == .classSeparator { item.classes = try classSuffix() }
        item.isExplicit = item.shape != nil || item.hasMetadata || item.hasStereotype
        return item
    }

    /// `:::` and its comma-separated classes, added to the drafts' name pool.
    mutating func classSuffix() throws(MermaidDiagramReadError) -> UseCaseListSpan {
        let start = drafts.names.count
        repeat {
            index += 1
            let token = try expect(.identifier)
            drafts.names.append(name(of: token))
        } while current == .comma
        return UseCaseListSpan(start: Int32(start), count: Int32(drafts.names.count - start))
    }

    private func isKey(_ kind: UseCaseTokenKind) -> Bool { kind == .identifier || kind == .plainString }

    private mutating func property() throws(MermaidDiagramReadError) -> UseCaseDraftProperty {
        let key = index
        guard isKey(current) else { throw unexpected(.metadataKey) }
        index += 1
        _ = try expect(.colon)
        let value = index
        let kind = current
        guard isKey(kind) || kind == .trueKeyword || kind == .falseKeyword else { throw unexpected(.metadataValue) }
        index += 1
        let keyContent = contentRange(of: key)
        let written = kind == .trueKeyword || kind == .falseKeyword
            ? UseCaseMetadataValue(kind: .boolean, text: .empty, boolean: kind == .trueKeyword)
            : UseCaseMetadataValue(kind: .text, text: contentRange(of: value), boolean: false)
        return UseCaseDraftProperty(key: keyContent, value: written, keyStart: Int32(keyContent.lowerBound))
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

    /// `@{ key: value, … }`, its properties separated by commas or line breaks, added to the drafts' property pool.
    mutating func metadata() throws(MermaidDiagramReadError) -> UseCaseListSpan {
        _ = try expect(.metadataStart)
        let start = drafts.properties.count
        skipLineBreaks()
        if isKey(current) {
            drafts.properties.append(try property())
            while separatorAhead() {
                if current == .comma {
                    index += 1
                } else {
                    skipLineBreaks()
                    if current == .comma { index += 1 }
                }
                skipLineBreaks()
                drafts.properties.append(try property())
            }
            if current == .comma { index += 1 }
            skipLineBreaks()
        }
        _ = try expect(.rightBrace)
        return UseCaseListSpan(start: Int32(start), count: Int32(drafts.properties.count - start))
    }

    private mutating func skipLineBreaks() {
        while current == .newline { index += 1 }
    }

    /// Comma-separated identifiers, by their tokens.
    mutating func identifierList() throws(MermaidDiagramReadError) -> [Int] {
        var identifiers = [try expect(.identifier)]
        while current == .comma {
            index += 1
            identifiers.append(try expect(.identifier))
        }
        return identifiers
    }

    /// Comma-separated `property: value` styles, each taken from the source as written, `\,` read as a comma, added
    /// to the drafts' style pool.
    mutating func styles() throws(MermaidDiagramReadError) -> UseCaseListSpan {
        let start = drafts.styleTexts.count
        drafts.styleTexts.append(try style())
        while current == .comma {
            index += 1
            drafts.styleTexts.append(try style())
        }
        return UseCaseListSpan(start: Int32(start), count: Int32(drafts.styleTexts.count - start))
    }

    private mutating func style() throws(MermaidDiagramReadError) -> MermaidTextRange {
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
        let written = MermaidTextRange(start: tokens.starts[first], end: tokens.ends[index - 1])
        let bytes = text.bytes
        var isASCII = true
        var hasEscapedComma = false
        for position in written.lowerBound..<written.upperBound {
            if bytes[position] >= 0x80 { isASCII = false }
            if bytes[position] == 0x5C, position + 1 < written.upperBound, bytes[position + 1] == UInt8(ascii: ",") { hasEscapedComma = true }
        }
        // Only a style holding `\,` is written again. Beyond ASCII it is replaced as 0.7.0 replaced it, by Foundation.
        guard hasEscapedComma else { return written }
        guard isASCII else { return text.append(Array(text.string(written).replacingOccurrences(of: "\\,", with: ",").utf8)) }
        var unescaped: [UInt8] = []
        unescaped.reserveCapacity(written.count)
        var position = written.lowerBound
        while position < written.upperBound {
            if bytes[position] == 0x5C, position + 1 < written.upperBound, bytes[position + 1] == UInt8(ascii: ",") {
                unescaped.append(UInt8(ascii: ","))
                position += 2
            } else {
                unescaped.append(bytes[position])
                position += 1
            }
        }
        return text.append(unescaped)
    }
}
