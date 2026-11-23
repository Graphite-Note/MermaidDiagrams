/**
 * File: PeleDrawnText.swift
 * -------------------------
 * Layer: Tests
 * Description: The lines Pele draws for a label its flowchart database holds, as its text layout makes them, for the
 *              spec comparison to set beside the package's label.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import Foundation

/// The lines Pele draws for a label (text/label.ts `layoutLines` and `inline`): a Markdown string dedented and trimmed,
/// any text broken at `<br>`, a written `\n` and line breaks, each line trimmed, and a Markdown line without the `*`, `**`,
/// `_` and `__` that open or close emphasis by Pele's rules. Tags and entity codes are left as they are: the specs' texts
/// that hold them read the same either way.
enum PeleDrawnText {
    static func lines(_ text: String, labelType: String) -> String {
        let isMarkdown = labelType == "markdown"
        let source = (isMarkdown ? dedented(text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")) : text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return parts(of: source).map { part in
            let line = part.trimmingCharacters(in: .whitespacesAndNewlines)
            return isMarkdown ? withoutEmphasisMarkers(line) : line
        }.joined(separator: "\n")
    }

    /// The text split as `RE_BREAK` (`/<br\s*\/?>|\\n|\n/gi`) splits it.
    private static func parts(of text: String) -> [String] {
        let pattern = try? NSRegularExpression(pattern: #"<br\s*/?>|\\n|\n"#, options: [.caseInsensitive])
        let whole = NSRange(text.startIndex..., in: text)
        var parts: [String] = []
        var start = text.startIndex
        for match in pattern?.matches(in: text, range: whole) ?? [] {
            guard let range = Range(match.range, in: text) else { continue }
            parts.append(String(text[start..<range.lowerBound]))
            start = range.upperBound
        }
        parts.append(String(text[start...]))
        return parts
    }

    /// The lines without the indent they all share, as `dedent` does.
    private static func dedented(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        let indents = lines.filter { line in !line.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { line in line.prefix { character in character == " " || character == "\t" }.count }
        guard let shared = indents.min(), shared > 0 else { return text }
        return lines.map { line in
            let indent = line.prefix { character in character == " " || character == "\t" }.count
            return String(line.dropFirst(min(shared, indent)))
        }.joined(separator: "\n")
    }

    /// `inline`'s Markdown emphasis: a `*` or `_` (doubled for bold) opens where text follows it and its like comes
    /// later, closes an open one where text precedes it, and a `_` between word characters stays.
    private static func withoutEmphasisMarkers(_ line: String) -> String {
        let characters = Array(line)
        var isOpen = (bold: false, italic: false)
        var result = ""
        var index = 0
        while index < characters.count {
            let character = characters[index]
            guard character == "*" || character == "_" else {
                result.append(character)
                index += 1
                continue
            }
            let isDouble = index + 1 < characters.count && characters[index + 1] == character
            let length = isDouble ? 2 : 1
            let opens = !(isDouble ? isOpen.bold : isOpen.italic)
            let previous = index > 0 ? characters[index - 1] : " "
            let next = index + length < characters.count ? characters[index + length] : " "
            let marker = String(repeating: character, count: length)
            let comesLater = String(characters[(index + length)...]).contains(marker)
            let canOpen = opens && !next.isWhitespace && comesLater
            let canClose = !opens && !previous.isWhitespace
            let isWordy = character == "_" && isWordCharacter(previous) && isWordCharacter(next)
            if (canOpen || canClose) && !isWordy {
                if isDouble { isOpen.bold = canOpen } else { isOpen.italic = canOpen }
                index += length
                continue
            }
            result.append(character)
            index += 1
        }
        return result
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber || character == "_")
    }
}
