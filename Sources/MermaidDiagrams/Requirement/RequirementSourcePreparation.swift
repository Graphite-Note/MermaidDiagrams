/**
 * File: RequirementSourcePreparation.swift
 * ----------------------------------------
 * Layer: Core
 * Description: A requirement diagram's text made ready for its lexer as Pele's `parse` makes every diagram's text ready:
 *              its line breaks made `\n`, comment lines taken out, the last semicolon of a colored style statement
 *              dropped, a line break added.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// A requirement diagram's text as its lexer reads it, and the line breaks taken out with comment lines, by where they
/// were, so that an error still names the line it is on in the text as written.
struct RequirementPreparedSource {
    let bytes: [UInt8]
    /// Where the keyword starts.
    let start: Int
    /// For each place comment lines were taken out, in order: the position after it, and how many line breaks were taken
    /// out up to there.
    let removedLineBreaks: [(position: Int, count: Int)]

    /// How many line breaks were taken out before `position`.
    func removedLineBreakCount(before position: Int) -> Int {
        removedLineBreaks.last { removal in removal.position <= position }?.count ?? 0
    }
}

/// What Pele's `parse` (`core.ts`) does to a diagram's text before its parser reads it, for a requirement diagram: every
/// `\r\n` and every lone `\r` becomes `\n` (`normalizeLineBreaks`); a line that holds only a comment, `%%` and more, goes
/// with the blank lines before it (`cleanupComments`); on a line where `style` or `classDef` is followed by a colon and
/// then a `#`, the line's last semicolon after that `#` goes, as Mermaid's `text.replace(/keyword.*:\S*#.*;/g)` drops it
/// (`dropColorSemicolons`); and a line break ends the text, so that a statement on the last line ends as one on any other.
/// Mermaid's entity codes (`#name;`) stay, the lexer reading them as Pele reads the placeholders it hides them behind;
/// directives (`%%{…}%%`) after the keyword stay too.
enum RequirementSourcePreparation {
    /// The text with the keyword at `start`, prepared from `start` on; what comes before only has its line breaks made
    /// `\n`, so that lines are counted as Pele counts them.
    static func prepared(_ bytes: [UInt8], from start: Int) -> RequirementPreparedSource {
        let prefix = withLineBreaksNormalized(bytes[..<start])
        var body = Array(String(decoding: withLineBreaksNormalized(bytes[start...]), as: UTF8.self).unicodeScalars)
        if body.contains("#") {
            body = withoutColorSemicolons(body, keyword: Array("style".unicodeScalars))
            body = withoutColorSemicolons(body, keyword: Array("classDef".unicodeScalars))
        }
        let comments = withoutCommentLines(body)
        var text = String.UnicodeScalarView()
        var removals: [(position: Int, count: Int)] = []
        var byteCount = prefix.count
        var removalIndex = 0
        for (index, scalar) in comments.text.enumerated() {
            while removalIndex < comments.removals.count, comments.removals[removalIndex].index == index {
                removals.append((byteCount, comments.removals[removalIndex].count))
                removalIndex += 1
            }
            text.append(scalar)
            byteCount += UTF8.width(scalar)
        }
        for removal in comments.removals[removalIndex...] { removals.append((byteCount, removal.count)) }
        text.append("\n")
        return RequirementPreparedSource(bytes: prefix + Array(String(text).utf8), start: prefix.count, removedLineBreaks: removals)
    }

    /// Pele's `cleanupComments`, `/^\s*%%(?!{)[^\n]+\n?/gm` taken out: from the start of a line, whitespace and line
    /// breaks, then `%%` not before `{`, at least one more character on its line, and its line break. Returns the text and,
    /// for each place something was taken out, its index in the text left and how many line breaks were taken out so far.
    static func withoutCommentLines(_ text: [Unicode.Scalar]) -> (text: [Unicode.Scalar], removals: [(index: Int, count: Int)]) {
        guard text.indices.contains(where: { index in text[index] == "%" && index + 1 < text.count && text[index + 1] == "%" }) else { return (text, []) }
        var kept: [Unicode.Scalar] = []
        kept.reserveCapacity(text.count)
        var removals: [(index: Int, count: Int)] = []
        var removedLineBreaks = 0
        var index = 0
        var isLineStart = true
        while index < text.count {
            if isLineStart {
                let whitespaceEnd = text[index...].firstIndex { scalar in !isWhitespace(scalar) } ?? text.count
                if let end = commentLineEnd(in: text, at: whitespaceEnd) {
                    removedLineBreaks += text[index..<end].filter { scalar in scalar == "\n" }.count
                    removals.append((kept.count, removedLineBreaks))
                    index = end
                    continue
                }
                // No line start up to the first character that is not whitespace starts a comment line either.
                kept += text[index..<whitespaceEnd]
                index = whitespaceEnd
                isLineStart = false
                continue
            }
            isLineStart = isLineBreak(text[index])
            kept.append(text[index])
            index += 1
        }
        return (kept, removals)
    }

    /// Where a comment line whose `%%` is at `index` ends, past its line break; nil when no comment line starts there.
    private static func commentLineEnd(in text: [Unicode.Scalar], at index: Int) -> Int? {
        guard index + 2 < text.count, text[index] == "%", text[index + 1] == "%", text[index + 2] != "{", text[index + 2] != "\n" else { return nil }
        var end = index + 2
        while end < text.count, text[end] != "\n" { end += 1 }
        return end < text.count ? end + 1 : end
    }

    /// `\r\n` and a lone `\r` as `\n`.
    static func withLineBreaksNormalized(_ bytes: ArraySlice<UInt8>) -> [UInt8] {
        guard bytes.contains(MermaidByte.carriageReturn) else { return Array(bytes) }
        var normalized: [UInt8] = []
        normalized.reserveCapacity(bytes.count)
        var index = bytes.startIndex
        while index < bytes.endIndex {
            let byte = bytes[index]
            if byte == MermaidByte.carriageReturn {
                normalized.append(MermaidByte.newline)
                if index + 1 < bytes.endIndex, bytes[index + 1] == MermaidByte.newline { index += 1 }
            } else {
                normalized.append(byte)
            }
            index += 1
        }
        return normalized
    }

    /// Pele's `dropColorSemicolons`, in one pass: for the first `keyword` on each line, when a colon comes after it and then
    /// a `#` with no whitespace between them, the line's last semicolon goes if it comes after that `#`.
    static func withoutColorSemicolons(_ text: [Unicode.Scalar], keyword: [Unicode.Scalar]) -> [Unicode.Scalar] {
        var dropped: [Int] = []
        var from = firstIndex(of: keyword, in: text, from: 0)
        while let keywordStart = from {
            let lineEnd = text[keywordStart...].firstIndex(where: isLineBreak) ?? text.count
            var isAfterColon = false
            var hash: Int?
            var index = keywordStart + keyword.count
            while index < lineEnd {
                let scalar = text[index]
                if scalar == ":" {
                    isAfterColon = true
                } else if scalar == "#" {
                    if isAfterColon {
                        hash = index
                        break
                    }
                } else if isWhitespace(scalar) {
                    isAfterColon = false
                }
                index += 1
            }
            if let hash, let semicolon = text[(hash + 1)..<lineEnd].lastIndex(of: ";") { dropped.append(semicolon) }
            from = lineEnd >= text.count ? nil : firstIndex(of: keyword, in: text, from: lineEnd + 1)
        }
        guard !dropped.isEmpty else { return text }
        var kept = text
        for index in dropped.reversed() { kept.remove(at: index) }
        return kept
    }

    private static func firstIndex(of keyword: [Unicode.Scalar], in text: [Unicode.Scalar], from start: Int) -> Int? {
        guard keyword.count <= text.count, start <= text.count - keyword.count else { return nil }
        var index = start
        while index <= text.count - keyword.count {
            if text[index] == keyword[0], text[index..<(index + keyword.count)].elementsEqual(keyword) { return index }
            index += 1
        }
        return nil
    }

    /// The line breaks of JavaScript's regular expressions, as Pele's `RE_LINE_BREAK` holds them.
    private static func isLineBreak(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "\n" || scalar == "\r" || scalar == "\u{2028}" || scalar == "\u{2029}"
    }

    /// Pele's `isSpace` (`util/chars.ts`): ASCII's tab to carriage return and space, and Unicode's spaces.
    private static func isWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 9...13, 32, 0xa0, 0x1680, 0x2000...0x200a, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000, 0xfeff: true
        default: false
        }
    }
}
