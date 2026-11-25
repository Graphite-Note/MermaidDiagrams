/**
 * File: TreeViewBoxDrawingReader.swift
 * ------------------------------------
 * Layer: Core
 * Description: Turns a tree view drawn with box-drawing characters into the indentation its grammar reads, as Mermaid's
 *              preprocessor does, and drops the comment lines Mermaid removes before parsing.
 *
 * Authors: Bahey Shalash
 * Version: 0.8
 * Date: 24/11/2026
 */

/// A line of a tree view's text after its keyword, as its grammar reads it, with the line it was written on.
struct TreeViewSourceLine {
    let text: String
    let writtenLine: Int
}

/// Mermaid's box-drawing preprocessor (Pele's `treeview/boxDrawing.ts`): when a line after the keyword holds `├`, `└`, `│`
/// or `─` (or their heavy forms), each line with a branch (`├──`, `└──`) becomes its name set in four spaces per level,
/// the level its branch's column over the width of the first indented branch, plus one; lines of `│` alone and lines of
/// box characters alone go; a name holding a box character by chance stays a top-level entry; and an indented line
/// without one is refused. Blank lines, comments and the title and accessibility lines pass unchanged. Before that, comment
/// lines go with the blank lines before them, as Mermaid's preprocessing removes them.
enum TreeViewBoxDrawingReader {
    static func lines(after keywordLine: Int, in text: String) throws(MermaidDiagramReadError) -> [TreeViewSourceLine] {
        let written = withoutCommentLines(MermaidByte.lines(of: text).enumerated().map { offset, line in
            TreeViewSourceLine(text: line, writtenLine: keywordLine + offset)
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
                converted.append(TreeViewSourceLine(text: String(repeating: "    ", count: depth) + name, writtenLine: line.writtenLine))
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
    private static func withoutCommentLines(_ lines: [TreeViewSourceLine]) -> [TreeViewSourceLine] {
        var kept: [TreeViewSourceLine] = []
        kept.reserveCapacity(lines.count)
        for line in lines {
            guard isCommentLine(line.text), kept.count > 0 else {
                kept.append(line)
                continue
            }
            while let last = kept.last, kept.count > 1, last.text.allSatisfy(\.isWhitespace) { kept.removeLast() }
        }
        return kept
    }

    /// Whether a line is a comment line Mermaid's preprocessing removes (with the blank lines before it, unless it is the
    /// first): `%%` and a character more after white space, not a directive's `%%{`.
    static func isCommentLine(_ line: String) -> Bool {
        if let first = firstScalarAfterBlanks(line), isOwnCharacter(first), first != "%" { return false }
        let content = line.drop { character in character.isWhitespace }
        return content.hasPrefix("%%") && !content.hasPrefix("%%{") && content.count > 2
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
    static func isDecorationOnly(_ line: String) -> Bool {
        !line.isEmpty && line.utf16.allSatisfy { unit in isWhitespace(unit) || unit == lightVertical || unit == heavyVertical }
    }

    /// Whether the text holds a dash, a branch or a vertical bar, light or heavy: read on its bytes, as each of them is
    /// written `E2 94` and a last byte in UTF-8.
    private static func containsBoxCharacter(_ text: String) -> Bool {
        containsBoxCharacter(text.utf8)
    }

    /// `containsBoxCharacter(_:)` on a text's bytes.
    static func containsBoxCharacter(_ bytes: some Sequence<UInt8>) -> Bool {
        var beforePrevious: UInt8 = 0
        var previous: UInt8 = 0
        for byte in bytes {
            if beforePrevious == 0xE2, previous == 0x94, boxCharacterLastBytes.contains(byte) { return true }
            beforePrevious = previous
            previous = byte
        }
        return false
    }

    /// The last bytes of `─`, `━`, `│`, `┃`, `└`, `┗`, `├` and `┣` in UTF-8, after `E2 94`.
    private static let boxCharacterLastBytes: [UInt8] = [0x80, 0x81, 0x82, 0x83, 0x94, 0x97, 0x9C, 0xA3]

    /// The column of the line's first branch character, `├`, `└` or their heavy forms, in UTF-16 units as JavaScript counts.
    static func branchColumn(in units: [UInt16]) -> Int? {
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

    static func isWhitespace(_ unit: UInt16) -> Bool {
        unit == space || unit == 0x09 || unit == 0x0A || unit == 0x0D || unit == 0x0B || unit == 0x0C || unit == 0xA0 || unit == 0xFEFF
            || unit == 0x1680 || (0x2000...0x200A).contains(unit) || unit == 0x2028 || unit == 0x2029 || unit == 0x202F || unit == 0x205F
            || unit == 0x3000
    }

    static let space: UInt16 = 0x20
    static let lightVertical: UInt16 = 0x2502
    static let heavyVertical: UInt16 = 0x2503
    /// `─` and `━`.
    static func isDash(_ unit: UInt16) -> Bool {
        unit == 0x2500 || unit == 0x2501
    }

    /// `└`, `┗`, `├` and `┣`.
    static func isBranch(_ unit: UInt16) -> Bool {
        unit == 0x2514 || unit == 0x2517 || unit == 0x251C || unit == 0x2523
    }

    /// The dashes, the branches and the vertical bars, light and heavy.
    static func isBoxCharacter(_ unit: UInt16) -> Bool {
        isDash(unit) || isBranch(unit) || unit == lightVertical || unit == heavyVertical
    }
}
