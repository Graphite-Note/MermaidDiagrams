/**
 * File: MermaidPreprocessing.swift
 * --------------------------------
 * Layer: Core
 * Description: What Pele does to a diagram's text before its type reads it (preprocess.ts): line breaks made line
 *              feeds, directives taken out wherever they stand, and the semicolon a style's colour loses.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

/// Pele's preprocessing of a diagram's text, over its UTF-8 bytes. Where Pele removes a directive the package blanks it
/// with spaces and keeps its line breaks, so that a statement's line stays the one the text shows; the readers skip
/// blank space as they skip a removed directive's absence.
enum MermaidPreprocessing {
    /// `normalizeLineBreaks`: every carriage return and line feed pair, and every carriage return alone, a line feed.
    static func normalizedLineBreaks(_ bytes: [UInt8]) -> [UInt8] {
        guard bytes.contains(MermaidByte.carriageReturn) else { return bytes }
        var normalized: [UInt8] = []
        normalized.reserveCapacity(bytes.count)
        var index = 0
        while index < bytes.count {
            if bytes[index] == MermaidByte.carriageReturn {
                normalized.append(MermaidByte.newline)
                index += index + 1 < bytes.count && bytes[index + 1] == MermaidByte.newline ? 2 : 1
            } else {
                normalized.append(bytes[index])
                index += 1
            }
        }
        return normalized
    }

    /// `bytes` with every directive from `start` on blanked, as Pele's `directives` removes each match of Mermaid's
    /// directive pattern (`MermaidDirectiveConfiguration.nextDirective`) wherever it stands: within a line, over several
    /// lines, or unclosed to the end of the text. Line breaks are kept.
    static func blankingDirectives(in bytes: [UInt8], from start: Int) -> [UInt8] {
        guard containsDirectiveStart(bytes, from: start) else { return bytes }
        var blanked = bytes
        var position = start
        while let match = MermaidDirectiveConfiguration.nextDirective(in: bytes, from: position) {
            for index in match.start..<match.end where blanked[index] != MermaidByte.newline { blanked[index] = MermaidByte.space }
            position = max(match.end, match.start + 1)
        }
        return blanked
    }

    /// Mermaid's `text.replace(/keyword.*:\S*#.*;/g, …)` as Pele does it (`dropColorSemicolons`), for `style` and then
    /// `classDef` from `start` on: on a line where the keyword is followed by a colon, a `#` right after it with no white
    /// space between, and later a semicolon, the line's last semicolon goes, so that `style A fill:#f00;B-->C` reads
    /// `style A fill:#f00B-->C`.
    static func droppingColorSemicolons(_ bytes: [UInt8], from start: Int) -> [UInt8] {
        guard bytes[min(start, bytes.count)...].contains(UInt8(ascii: "#")) else { return bytes }
        return droppingColorSemicolons(droppingColorSemicolons(bytes, after: Array("style".utf8), from: start), after: Array("classDef".utf8), from: start)
    }

    private static func droppingColorSemicolons(_ bytes: [UInt8], after keyword: [UInt8], from start: Int) -> [UInt8] {
        var dropped: Set<Int> = []
        var from = firstIndex(of: keyword, in: bytes, from: start)
        while let keywordStart = from {
            let lineEnd = endOfLine(in: bytes, from: keywordStart)
            var isAfterColon = false
            var hash: Int?
            var index = keywordStart + keyword.count
            while index < lineEnd {
                let byte = bytes[index]
                if byte == MermaidByte.colon {
                    isAfterColon = true
                } else if byte == UInt8(ascii: "#") {
                    if isAfterColon {
                        hash = index
                        break
                    }
                } else if JavaScriptWhitespace.length(in: bytes, at: index) > 0 {
                    isAfterColon = false
                }
                index += 1
            }
            if let hash, let semicolon = bytes[hash..<lineEnd].lastIndex(of: MermaidByte.semicolon), semicolon > hash { dropped.insert(semicolon) }
            from = lineEnd >= bytes.count ? nil : firstIndex(of: keyword, in: bytes, from: lineEnd + 1)
        }
        guard !dropped.isEmpty else { return bytes }
        return bytes.indices.compactMap { index in dropped.contains(index) ? nil : bytes[index] }
    }

    /// The first line terminator from `start` (a line feed, a carriage return, a line or paragraph separator), or the end.
    private static func endOfLine(in bytes: [UInt8], from start: Int) -> Int {
        var index = start
        while index < bytes.count {
            let byte = bytes[index]
            if byte == MermaidByte.newline || byte == MermaidByte.carriageReturn { return index }
            if byte == 0xE2, index + 2 < bytes.count, bytes[index + 1] == 0x80, bytes[index + 2] == 0xA8 || bytes[index + 2] == 0xA9 { return index }
            index += 1
        }
        return bytes.count
    }

    private static func firstIndex(of literal: [UInt8], in bytes: [UInt8], from start: Int) -> Int? {
        var index = start
        while index + literal.count <= bytes.count {
            if bytes[index] == literal[0], bytes[index..<index + literal.count].elementsEqual(literal) { return index }
            index += 1
        }
        return nil
    }

    private static func containsDirectiveStart(_ bytes: [UInt8], from start: Int) -> Bool {
        firstIndex(of: Array("%%{".utf8), in: bytes, from: start) != nil
    }
}
