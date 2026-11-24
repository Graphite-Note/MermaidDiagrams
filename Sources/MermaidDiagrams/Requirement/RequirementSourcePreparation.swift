/**
 * File: RequirementSourcePreparation.swift
 * ----------------------------------------
 * Layer: Core
 * Description: A requirement diagram's text made ready for its lexer as Pele's `parse` makes every diagram's text ready:
 *              its line breaks made `\n`, comment lines taken out, the last semicolon of a colored style statement
 *              dropped, a line break added.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 23/11/2026
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
/// with the blank lines before it (`cleanupComments`); and a line break ends the text, so that a statement on the last
/// line ends as one on any other. The semicolon a colored `style` or `classDef` loses (`dropColorSemicolons`) and the
/// directives are dealt with before, for every type (`MermaidPreprocessing`). Mermaid's entity codes (`#name;`) stay,
/// the lexer reading them as Pele reads the placeholders it hides them behind.
enum RequirementSourcePreparation {
    /// The text with the keyword at `start`, prepared from `start` on; what comes before only has its line breaks made
    /// `\n`, so that lines are counted as Pele counts them.
    static func prepared(_ bytes: [UInt8], from start: Int) -> RequirementPreparedSource {
        let prefix = withLineBreaksNormalized(bytes[..<start])
        let normalizedBody = withLineBreaksNormalized(bytes[start...])
        // Without `%%` no comment line is taken out, and the bytes, a string's and so well formed, are the text as kept.
        if !holdsTwoPercentSigns(normalizedBody) {
            var text = prefix
            text.reserveCapacity(prefix.count + normalizedBody.count + 1)
            text.append(contentsOf: normalizedBody)
            text.append(MermaidByte.newline)
            return RequirementPreparedSource(bytes: text, start: prefix.count, removedLineBreaks: [])
        }
        let body = Array(String(decoding: normalizedBody, as: UTF8.self).unicodeScalars)
        let comments = withoutCommentLines(body)
        // The text kept is written to UTF-8 a scalar at a time, as appending scalars to a string costs more.
        var text = prefix
        text.reserveCapacity(prefix.count + comments.text.count + 1)
        var removals: [(position: Int, count: Int)] = []
        var removalIndex = 0
        for (index, scalar) in comments.text.enumerated() {
            while removalIndex < comments.removals.count, comments.removals[removalIndex].index == index {
                removals.append((text.count, comments.removals[removalIndex].count))
                removalIndex += 1
            }
            if scalar.value < 0x80 {
                text.append(UInt8(truncatingIfNeeded: scalar.value))
            } else if let encoded = UTF8.encode(scalar) {
                text.append(contentsOf: encoded)
            }
        }
        for removal in comments.removals[removalIndex...] { removals.append((text.count, removal.count)) }
        text.append(MermaidByte.newline)
        return RequirementPreparedSource(bytes: text, start: prefix.count, removedLineBreaks: removals)
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

    /// Whether `%%` is written anywhere: a comment line needs it.
    private static func holdsTwoPercentSigns(_ bytes: [UInt8]) -> Bool {
        var previousIsPercentSign = false
        for byte in bytes {
            let isPercentSign = byte == MermaidByte.percent
            if isPercentSign, previousIsPercentSign { return true }
            previousIsPercentSign = isPercentSign
        }
        return false
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
