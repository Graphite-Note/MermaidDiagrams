/**
 * File: TreeViewTokenSource.swift
 * -------------------------------
 * Layer: Core
 * Description: A tree view's text as its grammar reads it, with the line each byte was written on, and the values of
 *              its tokens: an entry's name and annotations, the title and the accessibility text.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 23/11/2026
 */

import Foundation

/// A statement before a tree view's entries.
enum TreeViewHeaderStatement {
    case title(String)
    case accessibilityTitle(String)
    case accessibilityDescription(String)
}

/// The lines after a tree view's keyword joined into the text its tokens are read from, with where each line starts and
/// the line it was written on, so that an error names the line the writer sees.
struct TreeViewTokenSource {
    let bytes: [UInt8]
    private let lineStarts: [Int]
    private let writtenLines: [Int]

    init(lines: [TreeViewSourceLine]) {
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

    private func text(of token: TreeViewToken) -> String {
        String(decoding: bytes[token.start..<token.end], as: UTF8.self)
    }

    /// The token's statement when it is a title or accessibility text, else nil.
    func headerStatement(_ token: TreeViewToken) -> TreeViewHeaderStatement? {
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
    func entry(in tokens: [TreeViewToken], from index: inout Int) throws(MermaidDiagramReadError) -> TreeViewWrittenEntry {
        var entry = TreeViewWrittenEntry()
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
