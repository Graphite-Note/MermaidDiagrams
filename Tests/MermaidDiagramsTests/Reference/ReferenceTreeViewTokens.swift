/**
 * File: ReferenceTreeViewTokens.swift
 * -----------------------------------
 * Layer: Tests
 * Description: 0.7.0's tree view token source and tokenizer, frozen as main 2a0cc65 read them, for the frozen
 *              tree view reader.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import Foundation
@testable import MermaidDiagrams

/// A statement before a tree view's entries.
enum ReferenceTreeViewHeaderStatement {
    case title(String)
    case accessibilityTitle(String)
    case accessibilityDescription(String)
}

/// The lines after a tree view's keyword joined into the text its tokens are read from, with where each line starts and
/// the line it was written on, so that an error names the line the writer sees.
struct ReferenceTreeViewTokenSource {
    let bytes: [UInt8]
    private let lineStarts: [Int]
    private let writtenLines: [Int]

    init(lines: [ReferenceTreeViewSourceLine]) {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(lines.reduce(lines.count) { count, line in count + line.text.utf8.count })
        var lineStarts: [Int] = []
        lineStarts.reserveCapacity(lines.count)
        for (index, line) in lines.enumerated() {
            if index > 0 { bytes.append(MermaidByte.newline) }
            lineStarts.append(bytes.count)
            bytes.append(contentsOf: line.text.utf8)
        }
        self.bytes = bytes
        self.lineStarts = lineStarts
        writtenLines = lines.map(\.writtenLine)
    }

    /// The written line of the byte at `offset`.
    func writtenLine(at offset: Int) -> Int {
        var low = 0
        var high = lineStarts.count - 1
        guard high >= 0 else { return 1 }
        while low < high {
            let middle = (low + high + 1) / 2
            if lineStarts[middle] <= offset { low = middle } else { high = middle - 1 }
        }
        return writtenLines[low]
    }

    /// The first characters at `offset`, to its line's end.
    func excerpt(at offset: Int) -> String {
        var cursor = MermaidTextCursor(bytes: bytes)
        cursor.advance(by: offset)
        return cursor.excerpt()
    }

    private func text(of token: ReferenceTreeViewToken) -> String {
        String(decoding: bytes[token.start..<token.end], as: UTF8.self)
    }

    /// The token's statement when it is a title or accessibility text, else nil.
    func headerStatement(_ token: ReferenceTreeViewToken) -> ReferenceTreeViewHeaderStatement? {
        let written = text(of: token).drop { character in character == " " || character == "\t" }
        switch token.kind {
        case .title: return .title(Self.oneLine(written.dropFirst("title".count)))
        case .accessibilityTitle:
            let afterColon = written.drop { character in character != ":" }.dropFirst()
            return .accessibilityTitle(Self.oneLine(afterColon))
        case .accessibilityDescription:
            let afterKeyword = written.dropFirst("accDescr".count).drop { character in character.isWhitespace }
            if afterKeyword.first == ":" { return .accessibilityDescription(Self.oneLine(afterKeyword.dropFirst())) }
            return .accessibilityDescription(Self.lines(afterKeyword.dropFirst().dropLast()))
        default: return nil
        }
    }

    /// The entry whose tokens start at `index`, which moves past them: an indentation, a name, then annotations.
    func entry(in tokens: [ReferenceTreeViewToken], from index: inout Int) throws(MermaidDiagramReadError) -> ReferenceTreeViewWrittenEntry {
        var entry = ReferenceTreeViewWrittenEntry()
        if tokens[index].kind == .indentation {
            entry.indentation = tokens[index].end - tokens[index].start
            index += 1
        }
        guard index < tokens.count, tokens[index].kind == .quotedName || tokens[index].kind == .bareName else {
            let offset = index < tokens.count ? tokens[index].start : bytes.count
            throw .invalidSyntax(line: writtenLine(at: offset), problem: .treeViewExpectedName(excerpt(at: offset)))
        }
        let name = text(of: tokens[index])
        entry.name = tokens[index].kind == .quotedName ? String(name.dropFirst().dropLast())
            : Self.withoutTrailingBlanks(name)
        index += 1
        while index < tokens.count {
            let written = FoundationTextOnBytes.trimmed(text(of: tokens[index]), includingLineBreaks: false)
            switch tokens[index].kind {
            case .classAnnotation: entry.classes = FoundationTextOnBytes.trimmed(String(written.dropFirst(3)), includingLineBreaks: false)
            case .iconAnnotation: entry.icon = String(written.dropFirst("icon(".count).dropLast())
            case .descriptionAnnotation: entry.description = FoundationTextOnBytes.trimmed(String(written.dropFirst(2)), includingLineBreaks: false)
            default: return entry
            }
            index += 1
        }
        return entry
    }

    /// The name without the spaces and tabs at its end, its characters compared as the reversed name's were.
    private static func withoutTrailingBlanks(_ name: String) -> String {
        var end = name.endIndex
        while end > name.startIndex, case let before = name.index(before: end), name[before] == " " || name[before] == "\t" { end = before }
        return String(name[..<end])
    }

    /// Text of one line as Mermaid keeps it: trimmed, each run of blanks one space.
    private static func oneLine(_ text: Substring) -> String {
        text.split(whereSeparator: { character in character == " " || character == "\t" }).joined(separator: " ")
    }

    /// `accDescr { … }`'s lines, each trimmed and its runs of blanks one space, without blank lines.
    private static func lines(_ text: Substring) -> String {
        text.split(whereSeparator: \.isNewline).map { line in oneLine(line) }.filter { line in !line.isEmpty }.joined(separator: "\n")
    }
}


/// A token of a tree view's text, by the byte range it covers.
struct ReferenceTreeViewToken {
    enum Kind {
        case accessibilityDescription
        case accessibilityTitle
        case title
        case classAnnotation
        case iconAnnotation
        case descriptionAnnotation
        case indentation
        case quotedName
        case bareName
        /// `treeView-beta` again, which no statement after the first line takes.
        case keyword
    }

    let kind: Kind
    let start: Int
    let end: Int
}

/// Mermaid's tree view tokens (Pele's `TREEVIEW_TOKENS`), tried at each place in this order: `accDescr`, `accTitle` and
/// `title` with the blanks before them, `:::class`, `icon(name)` and `## description` with the blanks before them, a run
/// of blanks (indentation), a quoted name, then hidden `%%` comments and line breaks, then a bare name, which runs to the
/// end of its line or to the blanks before an annotation, unless it is exactly the keyword `treeView-beta`, whose token
/// Pele tries first and keeps when no longer token matches. A place no token matches is a syntax error.
struct ReferenceTreeViewTokenizer {
    private let bytes: [UInt8]
    private var position = 0
    /// The last closing brace and quotation marks of the text: an opening one past its last closer has none, which is
    /// known without scanning the rest of the text again, as Pele marks such a token dead.
    private let lastClosingBrace: Int
    private let lastQuotationMark: Int
    private let lastApostrophe: Int

    init(bytes: [UInt8]) {
        self.bytes = bytes
        lastClosingBrace = bytes.lastIndex(of: MermaidByte.closingBrace) ?? -1
        lastQuotationMark = bytes.lastIndex(of: MermaidByte.quotationMark) ?? -1
        lastApostrophe = bytes.lastIndex(of: Self.apostrophe) ?? -1
    }

    /// The tokens, or the byte offset of the first place no token matches.
    mutating func tokens() -> Result<[ReferenceTreeViewToken], ReferenceTreeViewLexingFailure> {
        var tokens: [ReferenceTreeViewToken] = []
        // About one token for every eight bytes: room for them is made once.
        tokens.reserveCapacity(bytes.count / 8 + 4)
        while position < bytes.count {
            let start = position
            if let (kind, end) = visibleToken(at: start) {
                tokens.append(ReferenceTreeViewToken(kind: kind, start: start, end: end))
                position = end
            } else if let end = hiddenToken(at: start) {
                position = end
            } else if let end = bareNameEnd(at: start) {
                // Pele's keyword token, tried first, wins unless the bare name is longer.
                let isKeyword = end == start + Self.keyword.count && hasPrefix(Self.keyword, at: start)
                tokens.append(ReferenceTreeViewToken(kind: isKeyword ? .keyword : .bareName, start: start, end: end))
                position = end
            } else {
                return .failure(ReferenceTreeViewLexingFailure(offset: start))
            }
        }
        return .success(tokens)
    }

    private func byte(_ index: Int) -> UInt8? {
        index < bytes.count ? bytes[index] : nil
    }

    private func hasPrefix(_ literal: String, at index: Int) -> Bool {
        var offset = index
        for expected in literal.utf8 {
            guard offset < bytes.count, bytes[offset] == expected else { return false }
            offset += 1
        }
        return true
    }

    private func blanksEnd(from index: Int) -> Int {
        var end = index
        while let current = byte(end), MermaidByte.isSpace(current) { end += 1 }
        return end
    }

    private func lineEnd(from index: Int) -> Int {
        var end = index
        while let current = byte(end), current != MermaidByte.newline, current != MermaidByte.carriageReturn { end += 1 }
        return end
    }

    /// The end of the line, or the start of a `%%` comment on it: where a title or accessibility text written on one line ends.
    private func lineEndBeforeComment(from index: Int) -> Int {
        var end = index
        while let current = byte(end), current != MermaidByte.newline, current != MermaidByte.carriageReturn, !hasPrefix("%%", at: end) { end += 1 }
        return end
    }

    private func visibleToken(at start: Int) -> (ReferenceTreeViewToken.Kind, Int)? {
        let afterBlanks = blanksEnd(from: start)
        if let end = accessibilityDescriptionEnd(at: afterBlanks) { return (.accessibilityDescription, end) }
        if hasPrefix("accTitle", at: afterBlanks) {
            let colon = blanksEnd(from: afterBlanks + 8)
            if byte(colon) == MermaidByte.colon { return (.accessibilityTitle, lineEndBeforeComment(from: colon)) }
        }
        if hasPrefix("title", at: afterBlanks) {
            let next = byte(afterBlanks + 5)
            if let next, MermaidByte.isSpace(next) { return (.title, lineEndBeforeComment(from: afterBlanks + 5)) }
            if next == nil || next == MermaidByte.newline || next == MermaidByte.carriageReturn || hasPrefix("%%", at: afterBlanks + 5) {
                return (.title, afterBlanks + 5)
            }
        }
        guard afterBlanks > start else { return quotedNameEnd(at: start).map { end in (.quotedName, end) } }
        if let end = annotationEnd(at: afterBlanks) { return end }
        return (.indentation, afterBlanks)
    }

    /// `accDescr: …` to the end of its line, or `accDescr { … }` to its closing brace, across lines.
    private func accessibilityDescriptionEnd(at index: Int) -> Int? {
        guard hasPrefix("accDescr", at: index) else { return nil }
        let colon = blanksEnd(from: index + 8)
        if byte(colon) == MermaidByte.colon { return lineEndBeforeComment(from: colon) }
        var brace = index + 8
        while let current = byte(brace), MermaidByte.isWhitespace(current) { brace += 1 }
        guard byte(brace) == MermaidByte.openingBrace, brace < lastClosingBrace,
              let closing = bytes[brace...].firstIndex(of: MermaidByte.closingBrace) else { return nil }
        return closing + 1
    }

    /// The annotation after blanks at `index`: `:::` and a class name, `icon(` and a name (`pack:name`) and `)`, or `##` and
    /// the rest of the line.
    private func annotationEnd(at index: Int) -> (ReferenceTreeViewToken.Kind, Int)? {
        if hasPrefix(":::", at: index) {
            let nameStart = blanksEnd(from: index + 3)
            guard let first = byte(nameStart), MermaidByte.isLetter(first) || first == MermaidByte.underscore else { return nil }
            return (.classAnnotation, wordEnd(from: nameStart + 1, allowsHyphen: true))
        }
        if hasPrefix("icon(", at: index) {
            var end = wordEnd(from: index + 5, allowsHyphen: true)
            if byte(end) == MermaidByte.colon {
                let packEnd = wordEnd(from: end + 1, allowsHyphen: true)
                guard packEnd > end + 1 else { return nil }
                end = packEnd
            }
            return byte(end) == UInt8(ascii: ")") ? (.iconAnnotation, end + 1) : nil
        }
        if hasPrefix("##", at: index) { return (.descriptionAnnotation, lineEnd(from: index)) }
        return nil
    }

    private func wordEnd(from index: Int, allowsHyphen: Bool) -> Int {
        var end = index
        while let current = byte(end), MermaidByte.isLetter(current) || MermaidByte.isDigit(current) || current == MermaidByte.underscore
            || (allowsHyphen && current == MermaidByte.hyphen) { end += 1 }
        return end
    }

    /// `"…"` or `'…'`, which may cross lines.
    private func quotedNameEnd(at index: Int) -> Int? {
        guard let quote = byte(index), quote == MermaidByte.quotationMark || quote == Self.apostrophe,
              index < (quote == MermaidByte.quotationMark ? lastQuotationMark : lastApostrophe),
              let closing = bytes[(index + 1)...].firstIndex(of: quote) else { return nil }
        return closing + 1
    }

    /// A `%%` comment to the end of its line, or a line break.
    private func hiddenToken(at index: Int) -> Int? {
        if hasPrefix("%%", at: index) {
            var end = index
            while let current = byte(end), current != MermaidByte.newline { end += 1 }
            return end
        }
        if byte(index) == MermaidByte.carriageReturn, byte(index + 1) == MermaidByte.newline { return index + 2 }
        return byte(index) == MermaidByte.newline ? index + 1 : nil
    }

    /// A bare name: it starts with neither a blank, a quotation mark, nor an annotation, and runs to the end of its line,
    /// or to the blanks before an annotation. Each run of blanks is looked past once.
    private func bareNameEnd(at index: Int) -> Int? {
        guard let first = byte(index), !MermaidByte.isWhitespace(first), first != MermaidByte.quotationMark, first != Self.apostrophe,
              !hasPrefix(":::", at: index), !hasPrefix("icon(", at: index), !hasPrefix("##", at: index) else { return nil }
        var end = index + 1
        while let current = byte(end), current != MermaidByte.newline, current != MermaidByte.carriageReturn {
            guard MermaidByte.isSpace(current) else {
                end += 1
                continue
            }
            let next = blanksEnd(from: end)
            if startsAnnotation(at: next) { break }
            end = next
        }
        return end
    }

    private func startsAnnotation(at index: Int) -> Bool {
        if hasPrefix("##", at: index) || hasPrefix("icon(", at: index) { return true }
        guard hasPrefix(":::", at: index), let first = byte(blanksEnd(from: index + 3)) else { return false }
        return MermaidByte.isLetter(first) || first == MermaidByte.underscore
    }

    private static let apostrophe = UInt8(ascii: "'")
    private static let keyword = "treeView-beta"
}

/// The byte offset where no token of the tree view's grammar matches.
struct ReferenceTreeViewLexingFailure: Error {
    let offset: Int
}
