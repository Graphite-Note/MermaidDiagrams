/**
 * File: UseCaseSourcePreparation.swift
 * ------------------------------------
 * Layer: Core
 * Description: A use case diagram's text made ready for its lexer as Pele's `parse` makes it ready, on its UTF-8
 *              bytes: line breaks made `\n`, comment lines taken out, a line break added at the end; the line breaks
 *              taken out are kept count of, so that an error names its line as written.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 25/11/2026
 */

/// What Pele's `parse` (`core.ts`) does to the text before its use case parser reads it: every `\r\n` and lone `\r`
/// becomes `\n` (`normalizeLineBreaks`); a line holding only a comment, `%%` and more but not `%%{`, goes with the
/// blank lines before it (`cleanupComments`, `/^\s*%%(?!{)[^\n]+\n?/gm`); and a line break ends the text, so that text
/// cut off at the end breaks on it and the end of the text is on the line after the last one written. The last semicolon
/// of a colored `style` or `classDef` line (`dropColorSemicolons`) is dropped before, for every type.
/// Line breaks taken out with comment lines: from `line` of the text left on, `count` of them in all went before it.
struct UseCaseRemovedLineBreaks: Equatable, Sendable {
    let line: Int
    let count: Int
}

enum UseCaseSourcePreparation {
    /// The text from the keyword on, made ready. JavaScript's whitespace and its line and paragraph separators, which
    /// take two or three bytes in UTF-8, are read as the characters they are, as Pele reads code units.
    static func prepared(_ written: ArraySlice<UInt8>) -> UseCaseBytes {
        var units = withLineBreaksNormalized(written)
        let removals = removeCommentLines(&units)
        units.append(UseCaseCharacters.lineFeed)
        return UseCaseBytes(text: units, removedLineBreaks: removals)
    }

    /// `\r\n` and a lone `\r` as `\n`.
    static func withLineBreaksNormalized(_ written: ArraySlice<UInt8>) -> [UInt8] {
        let carriageReturn: UInt8 = 0x0D
        var normalized: [UInt8] = []
        normalized.reserveCapacity(written.count + 1)
        guard written.contains(carriageReturn) else {
            normalized.append(contentsOf: written)
            return normalized
        }
        var index = written.startIndex
        while index < written.endIndex {
            if written[index] == carriageReturn {
                normalized.append(UseCaseCharacters.lineFeed)
                if index + 1 < written.endIndex, written[index + 1] == UseCaseCharacters.lineFeed { index += 1 }
            } else {
                normalized.append(written[index])
            }
            index += 1
        }
        return normalized
    }

    /// The text without its comment lines: from the start of a line, whitespace and line breaks, then `%%` not before
    /// `{`, at least one more character on its line, and its line break. Each place something went is given by the
    /// line of the text left it is at the start of, and how many line breaks went up to there.
    static func removeCommentLines(_ units: inout [UInt8]) -> [UseCaseRemovedLineBreaks] {
        guard hasTwoPercentSigns(units) else { return [] }
        var kept: [UInt8] = []
        kept.reserveCapacity(units.count + 1)
        var removals: [UseCaseRemovedLineBreaks] = []
        units.withUnsafeBufferPointer { buffer in
            let count = buffer.count
            var removedLineBreaks = 0
            var keptLine = 1
            var index = 0
            var isLineStart = true
            while index < count {
                guard isLineStart else {
                    index = copyLine(of: buffer, from: index, into: &kept, keptLine: &keptLine)
                    isLineStart = true
                    continue
                }
                let (whitespaceEnd, leadingLineBreaks) = Self.whitespaceEnd(in: buffer, from: index)
                var lineBreaks = leadingLineBreaks
                if let end = commentLineEnd(in: buffer, at: whitespaceEnd) {
                    for position in whitespaceEnd..<end where buffer[position] == UseCaseCharacters.lineFeed { lineBreaks += 1 }
                    removedLineBreaks += lineBreaks
                    removals.append(UseCaseRemovedLineBreaks(line: keptLine, count: removedLineBreaks))
                    index = end
                    continue
                }
                // No line start up to the first character that is not whitespace starts a comment line either.
                kept.append(contentsOf: UnsafeBufferPointer(rebasing: buffer[index..<whitespaceEnd]))
                keptLine += lineBreaks
                index = whitespaceEnd
                isLineStart = false
            }
        }
        units = kept
        return removals
    }

    /// The bytes from `index` copied to `kept` up to the next line start (after a line feed, or after a line or
    /// paragraph separator, where JavaScript's `^` also matches) or the end; where that is.
    private static func copyLine(of buffer: UnsafeBufferPointer<UInt8>, from index: Int, into kept: inout [UInt8], keptLine: inout Int) -> Int {
        var position = index
        while position < buffer.count {
            if UseCaseCharacters.isLineOrParagraphSeparator(in: buffer, at: position, end: buffer.count) {
                kept.append(contentsOf: UnsafeBufferPointer(rebasing: buffer[position..<position + 3]))
                return position + 3
            }
            kept.append(buffer[position])
            position += 1
            if buffer[position - 1] == UseCaseCharacters.lineFeed {
                keptLine += 1
                return position
            }
        }
        return position
    }

    /// Where the JavaScript whitespace from `index` ends, and how many line feeds it holds.
    private static func whitespaceEnd(in buffer: UnsafeBufferPointer<UInt8>, from index: Int) -> (end: Int, lineBreaks: Int) {
        var end = index
        var lineBreaks = 0
        while end < buffer.count {
            let length = UseCaseCharacters.javaScriptWhitespaceLength(in: buffer, at: end, end: buffer.count)
            guard length > 0 else { break }
            if buffer[end] == UseCaseCharacters.lineFeed { lineBreaks += 1 }
            end += length
        }
        return (end, lineBreaks)
    }

    private static func hasTwoPercentSigns(_ units: [UInt8]) -> Bool {
        let percent = UInt8(ascii: "%")
        var index = 0
        while index + 1 < units.count {
            if units[index] == percent {
                if units[index + 1] == percent { return true }
            }
            index += 1
        }
        return false
    }

    /// Where a comment line whose `%%` is at `index` ends, past its line break; nil when no comment line starts there.
    private static func commentLineEnd(in units: UnsafeBufferPointer<UInt8>, at index: Int) -> Int? {
        guard index + 2 < units.count, units[index] == UInt8(ascii: "%"), units[index + 1] == UInt8(ascii: "%"),
              units[index + 2] != UInt8(ascii: "{"), units[index + 2] != UseCaseCharacters.lineFeed else { return nil }
        var end = index + 2
        while end < units.count, units[end] != UseCaseCharacters.lineFeed { end += 1 }
        return end < units.count ? end + 1 : end
    }
}
