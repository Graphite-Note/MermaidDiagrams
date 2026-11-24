/**
 * File: ReferenceTreeViewReader.swift
 * -----------------------------------
 * Layer: Tests
 * Description: 0.7.0's tree view reader, frozen as main 2a0cc65 read it: the parser, the tree builder, the box-drawing
 *              preprocessing and the icon maps, which the tree view reader is compared with.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import Foundation
@testable import MermaidDiagrams

/// Reads a tree view after its `treeView-beta` keyword, which ends its line, as Pele's tree view parser reads it: the
/// text drawn with box-drawing characters turned into indentation first (`ReferenceTreeViewBoxDrawingReader`), then `title`,
/// `accTitle` and `accDescr` before the entries, then each entry: its indentation, its name (quoted, or bare to the end
/// of its line or the annotations), and its annotations (`:::class`, `icon(name)`, `## description`). A name ending
/// with `/` is a folder. An entry's parent is the last entry before it indented less.
enum ReferenceTreeViewParser {
    static func parse(_ cursor: MermaidTextCursor, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> TreeViewDiagram {
        // Mermaid's lexer takes a keyword with anything after it on its line, blanks too, as a name.
        if let byte = cursor.peek(), byte != MermaidByte.newline, !(byte == MermaidByte.carriageReturn && cursor.peek(1) == MermaidByte.newline) {
            throw .invalidSyntax(line: cursor.line, problem: .treeViewExpectedName(cursor.excerpt()))
        }
        let text = cursor.text(from: cursor.position, to: cursor.bytes.count)
        let lines = try ReferenceTreeViewBoxDrawingReader.lines(after: cursor.line, in: text).dropFirst()
        let source = ReferenceTreeViewTokenSource(lines: Array(lines))
        var tokenizer = ReferenceTreeViewTokenizer(bytes: source.bytes)
        let tokens: [ReferenceTreeViewToken]
        switch tokenizer.tokens() {
        case .success(let read): tokens = read
        case .failure(let failure): throw .invalidSyntax(line: source.writtenLine(at: failure.offset), problem: .unexpectedText(source.excerpt(at: failure.offset)))
        }
        var diagram = TreeViewDiagram()
        diagram.options = TreeViewOptions(MermaidConfigurationOptions(section: "treeView", in: cursor))
        let iconMaps = ReferenceTreeViewIconMaps(frontMatterOf: cursor.sourceBytes)
        diagram.options.iconMaps = TreeViewIconMaps(filenameIcons: iconMaps.filenameIcons, extensionIcons: iconMaps.extensionIcons)
        var index = 0
        while index < tokens.count, let statement = source.headerStatement(tokens[index]) {
            switch statement {
            case .title(let title): diagram.title = title
            case .accessibilityTitle(let title): diagram.accessibilityTitle = title
            case .accessibilityDescription(let description): diagram.accessibilityDescription = description
            }
            index += 1
        }
        var tree = ReferenceTreeViewTreeBuilder(limits: limits)
        // An entry takes a token or more: room for one per token left is made once.
        tree.reserveCapacity(min(tokens.count - index, limits.maximumNodeCount))
        while index < tokens.count {
            let entry = try source.entry(in: tokens, from: &index)
            try tree.add(entry)
        }
        diagram.entries = tree.entries
        diagram.topLevelIndices = tree.topLevelIndices
        return diagram
    }
}

/// An entry as written: its indentation, its name and its annotations.
struct ReferenceTreeViewWrittenEntry {
    var indentation = 0
    var name = ""
    var classes: String?
    var icon: String?
    var description: String?
}

/// Builds the tree as Mermaid's database does: an entry's parent is the last entry before it indented less.
struct ReferenceTreeViewTreeBuilder {
    private(set) var entries: [TreeViewEntry] = []
    private(set) var topLevelIndices: [Int] = []
    private let limits: MermaidDiagramLimits
    /// The entries that can still take children, by strictly increasing indentation.
    private var openEntries: [(index: Int, indentation: Int)] = []

    init(limits: MermaidDiagramLimits) {
        self.limits = limits
    }

    mutating func reserveCapacity(_ entryCount: Int) {
        entries.reserveCapacity(entryCount)
        openEntries.reserveCapacity(min(entryCount, Self.typicalDepth))
    }

    /// Deeper than most trees are written.
    private static let typicalDepth = 16

    mutating func add(_ written: ReferenceTreeViewWrittenEntry) throws(MermaidDiagramReadError) {
        guard entries.count < limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
        while let last = openEntries.last, written.indentation <= last.indentation { openEntries.removeLast() }
        let parentIndex = openEntries.last?.index
        let isFolder = written.name.hasSuffix("/")
        let index = entries.count
        entries.append(TreeViewEntry(name: isFolder ? String(written.name.dropLast()) : written.name, isFolder: isFolder, depth: openEntries.count,
                                     parentIndex: parentIndex, icon: written.icon.map { icon in icon.isEmpty ? "none" : icon },
                                     classes: written.classes.flatMap { classes in classes.isEmpty ? nil : classes },
                                     description: written.description.flatMap { description in description.isEmpty ? nil : description }))
        if let parentIndex { entries[parentIndex].childIndices.append(index) } else { topLevelIndices.append(index) }
        openEntries.append((index, written.indentation))
    }
}


/// A line of a tree view's text after its keyword, as its grammar reads it, with the line it was written on.
struct ReferenceTreeViewSourceLine {
    let text: String
    let writtenLine: Int
}

/// Mermaid's box-drawing preprocessor (Pele's `treeview/boxDrawing.ts`): when a line after the keyword holds `├`, `└`, `│`
/// or `─` (or their heavy forms), each line with a branch (`├──`, `└──`) becomes its name set in four spaces per level,
/// the level its branch's column over the width of the first indented branch, plus one; lines of `│` alone and lines of
/// box characters alone go; a name holding a box character by chance stays a top-level entry; and an indented line
/// without one is refused. Blank lines, comments and the title and accessibility lines pass unchanged. Before that, comment
/// lines go with the blank lines before them, as Mermaid's preprocessing removes them.
enum ReferenceTreeViewBoxDrawingReader {
    static func lines(after keywordLine: Int, in text: String) throws(MermaidDiagramReadError) -> [ReferenceTreeViewSourceLine] {
        let written = withoutCommentLines(MermaidByte.lines(of: text).enumerated().map { offset, line in
            ReferenceTreeViewSourceLine(text: line, writtenLine: keywordLine + offset)
        })
        // A text without a box character's bytes has no line to convert.
        guard containsBoxCharacter(text) else { return written }
        let unchanged = written.map { line in passesUnchanged(line.text) }
        let content = written.indices.dropFirst().filter { index in !unchanged[index] && !isDecorationOnly(written[index].text) }
            .map { index in expandingTabs(written[index].text) }
        guard content.contains(where: containsBoxCharacter) else { return written }
        let segmentWidth = content.lazy.compactMap { line in branchColumn(in: Array(line.utf16)) }.first { column in column > 0 } ?? 4
        var converted = [written[0]]
        for (index, line) in written.enumerated().dropFirst() {
            if unchanged[index] {
                converted.append(line)
                continue
            }
            if isDecorationOnly(line.text) { continue }
            let normalized = Array(expandingTabs(line.text).utf16)
            if let column = branchColumn(in: normalized) {
                let depth = Int((Double(column) / Double(segmentWidth)).rounded()) + 1
                var start = column + 1
                while start < normalized.count, isDash(normalized[start]) { start += 1 }
                while start < normalized.count, normalized[start] == space { start += 1 }
                let name = withoutTrailingWhitespace(UnicodeScalarText.string(utf16: normalized[start...]))
                guard !name.isEmpty else { throw .invalidSyntax(line: line.writtenLine, problem: .treeViewEntryWithoutName) }
                converted.append(ReferenceTreeViewSourceLine(text: String(repeating: "    ", count: depth) + name, writtenLine: line.writtenLine))
            } else if normalized.allSatisfy({ unit in isBoxCharacter(unit) || isWhitespace(unit) }) {
                continue
            } else if normalized.contains(where: isBoxCharacter) {
                converted.append(line)
            } else if let first = normalized.first, isWhitespace(first) {
                throw .invalidSyntax(line: line.writtenLine, problem: .treeViewIndentationWithoutBoxDrawing)
            } else {
                converted.append(line)
            }
        }
        return converted
    }

    /// The lines without those Mermaid's preprocessing removes: a comment line (`%%` and text after blanks, not a
    /// directive's `%%{`), with the lines of blanks just before it.
    private static func withoutCommentLines(_ lines: [ReferenceTreeViewSourceLine]) -> [ReferenceTreeViewSourceLine] {
        var kept: [ReferenceTreeViewSourceLine] = []
        kept.reserveCapacity(lines.count)
        for line in lines {
            if let first = firstScalarAfterBlanks(line.text), isOwnCharacter(first), first != "%" {
                kept.append(line)
                continue
            }
            let content = line.text.drop { character in character.isWhitespace }
            guard content.hasPrefix("%%"), !content.hasPrefix("%%{"), content.count > 2, kept.count > 0 else {
                kept.append(line)
                continue
            }
            while let last = kept.last, kept.count > 1, last.text.allSatisfy(\.isWhitespace) { kept.removeLast() }
        }
        return kept
    }

    static func passesUnchanged(_ line: String) -> Bool {
        // A line led by a character that starts none of the lines that pass: told from its first scalar after the blanks.
        if let first = firstScalarAfterBlanks(line), isOwnCharacter(first), first != "%", first != "t", first != "a" {
            return false
        }
        return passesUnchangedReadingCharacters(line)
    }

    /// `passesUnchanged` read from the line's characters, for any line.
    static func passesUnchangedReadingCharacters(_ line: String) -> Bool {
        let content = line.drop { character in character == " " || character == "\t" }
        if content.isEmpty || content.allSatisfy(\.isWhitespace) || content.hasPrefix("%%") { return true }
        if content.hasPrefix("title ") || content.hasPrefix("title\t") { return true }
        for keyword in ["accTitle", "accDescr"] where content.hasPrefix(keyword) {
            let rest = content.dropFirst(keyword.count).drop { character in character == " " || character == "\t" }
            if rest.hasPrefix(":") || (keyword == "accDescr" && rest.hasPrefix("{")) { return true }
        }
        return false
    }

    /// The first scalar after the spaces and tabs a line starts with, nil when there is none.
    private static func firstScalarAfterBlanks(_ line: String) -> Unicode.Scalar? {
        line.unicodeScalars.first { scalar in scalar != " " && scalar != "\t" }
    }

    /// Whether a scalar is white space for no one and starts a character of its own after a space or a tab: a printable
    /// ASCII character or a box-drawing one. The blanks before it are then each a character of their own and the line's
    /// first character after them starts with it, so the checks on the line's characters can be made on its scalars.
    private static func isOwnCharacter(_ scalar: Unicode.Scalar) -> Bool {
        (0x21...0x7E).contains(scalar.value) || (0x2500...0x257F).contains(scalar.value)
    }

    /// A line of blanks and vertical bars only, which carries no entry.
    private static func isDecorationOnly(_ line: String) -> Bool {
        !line.isEmpty && line.utf16.allSatisfy { unit in isWhitespace(unit) || unit == lightVertical || unit == heavyVertical }
    }

    /// Whether the text holds a dash, a branch or a vertical bar, light or heavy: read on its bytes, as each of them is
    /// written `E2 94` and a last byte in UTF-8.
    private static func containsBoxCharacter(_ text: String) -> Bool {
        var beforePrevious: UInt8 = 0
        var previous: UInt8 = 0
        for byte in text.utf8 {
            if beforePrevious == 0xE2, previous == 0x94, boxCharacterLastBytes.contains(byte) { return true }
            beforePrevious = previous
            previous = byte
        }
        return false
    }

    /// The last bytes of `─`, `━`, `│`, `┃`, `└`, `┗`, `├` and `┣` in UTF-8, after `E2 94`.
    private static let boxCharacterLastBytes: [UInt8] = [0x80, 0x81, 0x82, 0x83, 0x94, 0x97, 0x9C, 0xA3]

    /// The column of the line's first branch character, `├`, `└` or their heavy forms, in UTF-16 units as JavaScript counts.
    private static func branchColumn(in units: [UInt16]) -> Int? {
        units.firstIndex(where: isBranch)
    }

    private static func withoutTrailingWhitespace(_ text: String) -> String {
        var end = text.endIndex
        while end > text.startIndex, case let before = text.index(before: end), text[before].isWhitespace { end = before }
        return String(text[..<end])
    }

    private static func expandingTabs(_ line: String) -> String {
        guard line.utf8.contains(0x09) else { return line }
        return line.replacing("\t", with: "    ")
    }

    private static func isWhitespace(_ unit: UInt16) -> Bool {
        unit == space || unit == 0x09 || unit == 0x0A || unit == 0x0D || unit == 0x0B || unit == 0x0C || unit == 0xA0 || unit == 0xFEFF
            || unit == 0x1680 || (0x2000...0x200A).contains(unit) || unit == 0x2028 || unit == 0x2029 || unit == 0x202F || unit == 0x205F
            || unit == 0x3000
    }

    private static let space: UInt16 = 0x20
    private static let lightVertical: UInt16 = 0x2502
    private static let heavyVertical: UInt16 = 0x2503
    /// `─` and `━`.
    private static func isDash(_ unit: UInt16) -> Bool {
        unit == 0x2500 || unit == 0x2501
    }

    /// `└`, `┗`, `├` and `┣`.
    private static func isBranch(_ unit: UInt16) -> Bool {
        unit == 0x2514 || unit == 0x2517 || unit == 0x251C || unit == 0x2523
    }

    /// The dashes, the branches and the vertical bars, light and heavy.
    private static func isBoxCharacter(_ unit: UInt16) -> Bool {
        isDash(unit) || isBranch(unit) || unit == lightVertical || unit == heavyVertical
    }
}

/// The icons a tree view's options give files by name and by extension, as Pele's `iconConfig` keeps them: only the
/// values that are text. They are read from the front matter's block mappings (`config:`, `treeView:`, then
/// `extensionIcons:` and a `.ts: typescript` line per extension); a map written as a flow mapping or in a directive is
/// not read.
struct ReferenceTreeViewIconMaps: Equatable, Sendable {
    var filenameIcons: [String: String] = [:]
    var extensionIcons: [String: String] = [:]

    init() {}

    init(filenameIcons: [String: String], extensionIcons: [String: String]) {
        self.filenameIcons = filenameIcons
        self.extensionIcons = extensionIcons
    }

    /// The maps in the front matter at the start of `bytes`, none without one.
    init(frontMatterOf bytes: [UInt8]) {
        // A text without `Icons` or a backslash anywhere has none in its front matter's lines either.
        guard Self.mayNameAnIconMap(bytes[...]) else { return }
        var keys: [(indentation: Int, key: String)] = []
        let lines = Self.frontMatterLines(of: bytes)
        // The two maps' keys can only be written with `Icons` in them, or with an escape, which takes a backslash.
        guard lines.contains(where: { line in Self.mayNameAnIconMap(ArraySlice(line.utf8)) }) else { return }
        for line in lines {
            let indentation = line.prefix { character in character == " " }.count
            let content = FoundationTextOnBytes.trimmed(line, includingLineBreaks: false)
            guard !content.isEmpty, !content.hasPrefix("#"), let (key, value) = Self.keyAndValue(content) else { continue }
            while let last = keys.last, last.indentation >= indentation { keys.removeLast() }
            let path = keys.map(\.key)
            if value.isEmpty {
                keys.append((indentation, key))
            } else if let text = Self.text(value) {
                if path == ["config", "treeView", "filenameIcons"] { filenameIcons[key] = text }
                if path == ["config", "treeView", "extensionIcons"] { extensionIcons[key] = text }
            }
        }
    }

    /// Whether bytes hold `Icons` or a backslash, without which no key of them is `filenameIcons` or `extensionIcons`.
    private static func mayNameAnIconMap(_ bytes: ArraySlice<UInt8>) -> Bool {
        guard !bytes.contains(UInt8(ascii: "\\")) else { return true }
        var searchStart = bytes.startIndex
        while let candidate = bytes[searchStart...].firstIndex(of: iconsWord[0]) {
            if bytes[candidate...].starts(with: iconsWord) { return true }
            searchStart = candidate + 1
        }
        return false
    }

    private static let iconsWord = Array("Icons".utf8)

    /// The icon a file is mapped to, or nil: by its whole name first, else by its last extension in lower case, with or
    /// without its dot. A name starting with its only dot (`.env`) has no extension. An empty icon is none found.
    func icon(forFileNamed name: String) -> String? {
        if let icon = filenameIcons[name], !icon.isEmpty { return icon }
        guard let dot = name.lastIndex(of: "."), dot > name.startIndex else { return nil }
        let fileExtension = name[dot...].lowercased()
        let icon = extensionIcons[fileExtension] ?? extensionIcons[String(fileExtension.dropFirst())]
        return icon?.isEmpty == false ? icon : nil
    }

    /// The lines between the opening `---` and the closing one, none when the front matter is missing or never closed.
    private static func frontMatterLines(of bytes: [UInt8]) -> [String] {
        var cursor = MermaidTextCursor(bytes: bytes)
        if cursor.hasPrefix([0xEF, 0xBB, 0xBF]) { cursor.advance(by: 3) }
        cursor.skipWhitespace()
        guard cursor.hasPrefix(Array("---".utf8)), cursor.readRestOfLine() == "---" else { return [] }
        var lines: [String] = []
        while !cursor.isAtEnd {
            cursor.advance()
            let line = cursor.readRestOfLine()
            if FoundationTextOnBytes.trimmed(line, includingLineBreaks: false) == "---" { return lines }
            lines.append(line)
        }
        return []
    }

    /// `key: value` or `key:`, the key plain or quoted, the value without a comment after it.
    private static func keyAndValue(_ content: String) -> (String, String)? {
        var reader = KanbanFlowReader(bytes: Array(content.utf8))
        guard let key = try? reader.readKey(), reader.skipsColonBeforeValue() else { return nil }
        let rest = FoundationTextOnBytes.trimmed(reader.rest, includingLineBreaks: false)
        if let first = rest.first, first == "\"" || first == "'" { return (key, rest) }
        // Without a space and a number sign in its bytes the value holds no comment, which is looked for only then.
        let mayHoldComment = rest.utf8.indices.contains { index in
            rest.utf8[index] == MermaidByte.space && rest.utf8.index(after: index) < rest.utf8.endIndex
                && rest.utf8[rest.utf8.index(after: index)] == UInt8(ascii: "#")
        }
        let withoutComment = mayHoldComment ? rest.range(of: " #").map { comment in String(rest[..<comment.lowerBound]) } ?? rest : rest
        return (key, FoundationTextOnBytes.trimmed(withoutComment, includingLineBreaks: false))
    }

    /// A value that YAML's JSON schema reads as text, or nil for null, a Boolean, a number or a collection.
    private static func text(_ written: String) -> String? {
        var reader = KanbanFlowReader(bytes: Array(written.utf8))
        guard let first = written.first, first != "{", first != "[" else { return nil }
        if first == "\"" || first == "'" {
            guard case .text(let text) = try? reader.readDocument() else { return nil }
            return text
        }
        guard case .text(let text) = KanbanYAMLValue(plainScalar: written) else { return nil }
        return text
    }
}
