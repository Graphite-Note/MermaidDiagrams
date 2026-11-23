/**
 * File: MermaidPreprocessing.swift
 * --------------------------------
 * Layer: Core
 * Description: What Pele does to a diagram's text before its type reads it (preprocess.ts): line breaks made line
 *              feeds, an HTML tag's attributes single-quoted, directives taken out wherever they stand, and the
 *              semicolon a style's colour loses.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

/// Pele's preprocessing of a diagram's text, over its UTF-8 bytes.
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

    /// `preprocess`'s first step after the line breaks: in every tag up to the text's last `>` (`<(\w+)([^>]*)>`), each
    /// attribute value in double quotation marks (`="([^"]*)"`) put in single ones, so that `<span style="color:red">`
    /// reads `<span style='color:red'>` and a flowchart's plain text, which takes no `"`, takes the tag. The length stays.
    static func singleQuotingTagAttributes(_ bytes: [UInt8]) -> [UInt8] {
        guard let lastClose = bytes.lastIndex(of: MermaidByte.greaterThan), lastClose > 0, bytes.contains(MermaidByte.lessThan) else { return bytes }
        var quoted = bytes
        var index = 0
        while index < lastClose {
            guard bytes[index] == MermaidByte.lessThan, FlowchartLexerText.isWord(bytes[index + 1]) else {
                index += 1
                continue
            }
            var attributesStart = index + 1
            while FlowchartLexerText.isWord(bytes[attributesStart]) { attributesStart += 1 }
            // A `>` is at `lastClose` at the latest, so the tag closes.
            var tagEnd = attributesStart
            while bytes[tagEnd] != MermaidByte.greaterThan { tagEnd += 1 }
            var attribute = attributesStart
            while attribute + 1 < tagEnd {
                guard bytes[attribute] == MermaidByte.equals, bytes[attribute + 1] == MermaidByte.quotationMark,
                      let closing = bytes[(attribute + 2)..<tagEnd].firstIndex(of: MermaidByte.quotationMark) else {
                    attribute += 1
                    continue
                }
                quoted[attribute + 1] = UInt8(ascii: "'")
                quoted[closing] = UInt8(ascii: "'")
                attribute = closing + 1
            }
            index = tagEnd + 1
        }
        return quoted
    }

    /// `bytes` without the directives from `start` on, as Pele's `directives` removes each match of Mermaid's directive
    /// pattern (`MermaidDirectiveConfiguration.nextDirective`) wherever it stands: within a line, over several lines, or
    /// unclosed to the end of the text, so that the text on either side of it joins (`A-->%%{…}%%B` reads `A-->B`). The
    /// line breaks a directive held are put back before the line break that ends the joined line, so that every later
    /// line keeps the number the text shows, as Pele's errors name the line as written; a blank line is what any reader
    /// skips.
    static func removingDirectives(from bytes: [UInt8], from start: Int) -> [UInt8] {
        guard containsDirectiveStart(bytes, from: start) else { return bytes }
        var kept = Array(bytes[..<start])
        kept.reserveCapacity(bytes.count)
        var heldLineBreaks = 0
        func keep(_ range: Range<Int>) {
            if heldLineBreaks > 0, let lineBreak = bytes[range].firstIndex(of: MermaidByte.newline) {
                kept.append(contentsOf: bytes[range.lowerBound..<lineBreak])
                kept.append(contentsOf: repeatElement(MermaidByte.newline, count: heldLineBreaks))
                heldLineBreaks = 0
                kept.append(contentsOf: bytes[lineBreak..<range.upperBound])
            } else {
                kept.append(contentsOf: bytes[range])
            }
        }
        var position = start
        var keptUpTo = start
        while let match = MermaidDirectiveConfiguration.nextDirective(in: bytes, from: position) {
            keep(keptUpTo..<match.start)
            heldLineBreaks += bytes[match.start..<match.end].reduce(0) { count, byte in byte == MermaidByte.newline ? count + 1 : count }
            keptUpTo = match.end
            position = max(match.end, match.start + 1)
        }
        keep(keptUpTo..<bytes.count)
        kept.append(contentsOf: repeatElement(MermaidByte.newline, count: heldLineBreaks))
        return kept
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
