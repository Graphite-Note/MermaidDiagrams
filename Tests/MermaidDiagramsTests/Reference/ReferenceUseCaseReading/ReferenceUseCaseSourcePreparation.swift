/**
 * File: ReferenceUseCaseSourcePreparation.swift
 * ---------------------------------------------
 * Layer: Tests
 * Description: A use case diagram's text made ready for its lexer as Pele's `parse` makes it ready: line breaks made
 *              `\n`, comment lines taken out, the last semicolon of a colored style dropped, a line break added at the
 *              end; the line breaks taken out are kept count of, so that an error names its line as written.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

@testable import MermaidDiagrams

/// What Pele's `parse` (`core.ts`) does to the text before its use case parser reads it: every `\r\n` and lone `\r`
/// becomes `\n` (`normalizeLineBreaks`); a line holding only a comment, `%%` and more but not `%%{`, goes with the
/// blank lines before it (`cleanupComments`, `/^\s*%%(?!{)[^\n]+\n?/gm`); and a line break ends the text, so that text
/// cut off at the end breaks on it and the end of the text is on the line after the last one written. The last semicolon
/// of a colored `style` or `classDef` line (`dropColorSemicolons`) is dropped before, for every type.
/// Line breaks taken out with comment lines: from `line` of the text left on, `count` of them in all went before it.
struct ReferenceUseCaseRemovedLineBreaks: Equatable {
    let line: Int
    let count: Int
}

enum ReferenceUseCaseSourcePreparation {
    static func prepared(_ written: [UInt16]) -> ReferenceUseCaseCharacters {
        let comments = withoutCommentLines(withLineBreaksNormalized(written))
        // The semicolon a colored `style` or `classDef` loses is dropped before, for every type (`MermaidPreprocessing`).
        var units = comments.units
        units.append(ReferenceUseCaseCharacters.lineFeed)
        return ReferenceUseCaseCharacters(units: units, removedLineBreaks: comments.removals)
    }

    /// `\r\n` and a lone `\r` as `\n`.
    static func withLineBreaksNormalized(_ units: [UInt16]) -> [UInt16] {
        let carriageReturn: UInt16 = 0x0D
        guard units.contains(carriageReturn) else { return units }
        var normalized: [UInt16] = []
        normalized.reserveCapacity(units.count)
        var index = 0
        while index < units.count {
            if units[index] == carriageReturn {
                normalized.append(ReferenceUseCaseCharacters.lineFeed)
                if index + 1 < units.count, units[index + 1] == ReferenceUseCaseCharacters.lineFeed { index += 1 }
            } else {
                normalized.append(units[index])
            }
            index += 1
        }
        return normalized
    }

    /// The text without its comment lines: from the start of a line, whitespace and line breaks, then `%%` not before
    /// `{`, at least one more character on its line, and its line break. Each place something went is given by the
    /// line of the text left it is at the start of, and how many line breaks went up to there.
    static func withoutCommentLines(_ units: [UInt16]) -> (units: [UInt16], removals: [ReferenceUseCaseRemovedLineBreaks]) {
        let percent = UInt16(ascii: "%")
        guard units.indices.contains(where: { index in units[index] == percent && index + 1 < units.count && units[index + 1] == percent }) else {
            return (units, [])
        }
        var kept: [UInt16] = []
        kept.reserveCapacity(units.count)
        var removals: [ReferenceUseCaseRemovedLineBreaks] = []
        var removedLineBreaks = 0
        var keptLine = 1
        var index = 0
        var isLineStart = true
        while index < units.count {
            guard isLineStart else {
                // JavaScript's `^` also matches after a line or paragraph separator.
                isLineStart = [ReferenceUseCaseCharacters.lineFeed, 0x2028, 0x2029].contains(units[index])
                if units[index] == ReferenceUseCaseCharacters.lineFeed { keptLine += 1 }
                kept.append(units[index])
                index += 1
                continue
            }
            let whitespaceEnd = units[index...].firstIndex { unit in !ReferenceUseCaseCharacters.isJavaScriptWhitespace(unit) } ?? units.count
            if let end = commentLineEnd(in: units, at: whitespaceEnd) {
                removedLineBreaks += units[index..<end].filter { unit in unit == ReferenceUseCaseCharacters.lineFeed }.count
                removals.append(ReferenceUseCaseRemovedLineBreaks(line: keptLine, count: removedLineBreaks))
                index = end
                continue
            }
            // No line start up to the first character that is not whitespace starts a comment line either.
            kept += units[index..<whitespaceEnd]
            keptLine += units[index..<whitespaceEnd].filter { unit in unit == ReferenceUseCaseCharacters.lineFeed }.count
            index = whitespaceEnd
            isLineStart = false
        }
        return (kept, removals)
    }

    /// Where a comment line whose `%%` is at `index` ends, past its line break; nil when no comment line starts there.
    private static func commentLineEnd(in units: [UInt16], at index: Int) -> Int? {
        guard index + 2 < units.count, units[index] == UInt16(ascii: "%"), units[index + 1] == UInt16(ascii: "%"),
              units[index + 2] != UInt16(ascii: "{"), units[index + 2] != ReferenceUseCaseCharacters.lineFeed else { return nil }
        var end = index + 2
        while end < units.count, units[end] != ReferenceUseCaseCharacters.lineFeed { end += 1 }
        return end < units.count ? end + 1 : end
    }
}
