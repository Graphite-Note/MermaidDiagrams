/**
 * File: MermaidPreprocessing.swift
 * --------------------------------
 * Layer: Core
 * Description: What Pele does to a diagram's text before its type reads it (preprocess.ts): line breaks made line
 *              feeds, an HTML tag's attributes single-quoted, directives taken out wherever they stand, and the
 *              semicolon a style's colour loses.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 24/11/2026
 */

/// Pele's preprocessing of a diagram's text, over its UTF-8 bytes. Each pass gives back its input itself, uncopied, when
/// it finds nothing to change.
enum MermaidPreprocessing {
    /// The bytes a pass changes or looks for that a text holds, found in one scan (`bytesFound`), so that the reader
    /// runs no pass that would find none of them. The passes change none of these bytes but the carriage return (and a
    /// directive's `%`), so the set found before any pass holds for the passes after it.
    struct FoundBytes: OptionSet {
        let rawValue: UInt8

        static let carriageReturn = FoundBytes(rawValue: 1)
        static let lessThan = FoundBytes(rawValue: 2)
        static let greaterThan = FoundBytes(rawValue: 4)
        static let percent = FoundBytes(rawValue: 8)
        static let hash = FoundBytes(rawValue: 16)
    }

    /// Which of a carriage return, `<`, `>`, `%` and `#` the bytes hold, looked for sixteen bytes at a time.
    static func bytesFound(in bytes: [UInt8]) -> FoundBytes {
        bytes.withUnsafeBufferPointer { buffer in bytesFound(in: buffer) }
    }

    /// Which of a carriage return, `<`, `>`, `%` and `#` the bytes hold, looked for sixteen bytes at a time.
    static func bytesFound(in buffer: UnsafeBufferPointer<UInt8>) -> FoundBytes {
        var carriageReturns = SIMDMask<SIMD16<Int8>>(repeating: false)
        var tagOpenings = carriageReturns
        var tagClosings = carriageReturns
        var percents = carriageReturns
        var hashes = carriageReturns
        var index = 0
        if let base = buffer.baseAddress {
            let raw = UnsafeRawPointer(base)
            while index + 16 <= buffer.count {
                let chunk = raw.loadUnaligned(fromByteOffset: index, as: SIMD16<UInt8>.self)
                carriageReturns .|= chunk .== SIMD16(repeating: MermaidByte.carriageReturn)
                tagOpenings .|= chunk .== SIMD16(repeating: MermaidByte.lessThan)
                tagClosings .|= chunk .== SIMD16(repeating: MermaidByte.greaterThan)
                percents .|= chunk .== SIMD16(repeating: MermaidByte.percent)
                hashes .|= chunk .== SIMD16(repeating: hash)
                index += 16
            }
        }
        var found: FoundBytes = []
        if any(carriageReturns) { found.insert(.carriageReturn) }
        if any(tagOpenings) { found.insert(.lessThan) }
        if any(tagClosings) { found.insert(.greaterThan) }
        if any(percents) { found.insert(.percent) }
        if any(hashes) { found.insert(.hash) }
        while index < buffer.count {
            switch buffer[index] {
            case MermaidByte.carriageReturn: found.insert(.carriageReturn)
            case MermaidByte.lessThan: found.insert(.lessThan)
            case MermaidByte.greaterThan: found.insert(.greaterThan)
            case MermaidByte.percent: found.insert(.percent)
            case hash: found.insert(.hash)
            default: break
            }
            index += 1
        }
        return found
    }

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
        let quotationMarks = bytes.withUnsafeBufferPointer { buffer in tagAttributeQuotationMarks(in: buffer, stoppingAtFirst: false) }
        guard !quotationMarks.isEmpty else { return bytes }
        var quoted = bytes
        for position in quotationMarks { quoted[position] = UInt8(ascii: "'") }
        return quoted
    }

    /// Whether `singleQuotingTagAttributes` would change a byte of `bytes`.
    static func hasTagAttributesToQuote(in bytes: UnsafeBufferPointer<UInt8>) -> Bool {
        !tagAttributeQuotationMarks(in: bytes, stoppingAtFirst: true).isEmpty
    }

    /// The positions of the double quotation marks `singleQuotingTagAttributes` makes single, in order; only the first
    /// pair when `stoppingAtFirst`. Once a `="` finds no closing quotation mark in its tag, no later one in the tag can
    /// (its own `"` would be that mark), so each tag is read once.
    private static func tagAttributeQuotationMarks(in bytes: UnsafeBufferPointer<UInt8>, stoppingAtFirst: Bool) -> [Int] {
        guard let lastClose = bytes.lastIndex(of: MermaidByte.greaterThan), lastClose > 0, bytes.contains(MermaidByte.lessThan) else { return [] }
        var positions: [Int] = []
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
                guard bytes[attribute] == MermaidByte.equals, bytes[attribute + 1] == MermaidByte.quotationMark else {
                    attribute += 1
                    continue
                }
                guard let closing = bytes[(attribute + 2)..<tagEnd].firstIndex(of: MermaidByte.quotationMark) else { break }
                positions.append(attribute + 1)
                positions.append(closing)
                if stoppingAtFirst { return positions }
                attribute = closing + 1
            }
            index = tagEnd + 1
        }
        return positions
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
        guard firstIndex(of: hash, in: bytes, from: min(start, bytes.count)) != nil else { return bytes }
        return droppingColorSemicolons(droppingColorSemicolons(bytes, after: styleKeyword, from: start), after: classDefinitionKeyword, from: start)
    }

    private static func droppingColorSemicolons(_ bytes: [UInt8], after keyword: [UInt8], from start: Int) -> [UInt8] {
        let dropped = bytes.withUnsafeBufferPointer { buffer in droppedColorSemicolons(in: buffer, after: keyword, from: start) }
        guard !dropped.isEmpty else { return bytes }
        var kept: [UInt8] = []
        kept.reserveCapacity(bytes.count - dropped.count)
        var keptFrom = 0
        for semicolon in dropped {
            kept.append(contentsOf: bytes[keptFrom..<semicolon])
            keptFrom = semicolon + 1
        }
        kept.append(contentsOf: bytes[keptFrom...])
        return kept
    }

    /// Whether `droppingColorSemicolons` would drop a semicolon of `bytes` from `start` on: a semicolon after `style` is
    /// found on the text as written, and when there is none `classDef`'s are looked for on that same text.
    static func hasColorSemicolonsToDrop(in bytes: UnsafeBufferPointer<UInt8>, from start: Int) -> Bool {
        guard firstIndex(of: hash, in: bytes, from: min(start, bytes.count)) != nil else { return false }
        return !droppedColorSemicolons(in: bytes, after: styleKeyword, from: start).isEmpty
            || !droppedColorSemicolons(in: bytes, after: classDefinitionKeyword, from: start).isEmpty
    }

    /// The semicolons `droppingColorSemicolons` drops after `keyword`, in the order they stand: one a line at most, each
    /// line after the one before.
    private static func droppedColorSemicolons(in bytes: UnsafeBufferPointer<UInt8>, after keyword: [UInt8], from start: Int) -> [Int] {
        var dropped: [Int] = []
        var from = firstIndex(of: keyword, in: bytes, from: start)
        while let keywordStart = from {
            let lineEnd = endOfLine(in: bytes, from: keywordStart)
            var isAfterColon = false
            var hashIndex: Int?
            var index = keywordStart + keyword.count
            while index < lineEnd {
                let byte = bytes[index]
                if byte == MermaidByte.colon {
                    isAfterColon = true
                } else if byte == hash {
                    if isAfterColon {
                        hashIndex = index
                        break
                    }
                } else if JavaScriptWhitespace.length(in: bytes, at: index) > 0 {
                    isAfterColon = false
                }
                index += 1
            }
            if let hashIndex, let semicolon = bytes[hashIndex..<lineEnd].lastIndex(of: MermaidByte.semicolon), semicolon > hashIndex {
                dropped.append(semicolon)
            }
            from = lineEnd >= bytes.count ? nil : firstIndex(of: keyword, in: bytes, from: lineEnd + 1)
        }
        return dropped
    }

    /// The first line terminator from `start` (a line feed, a carriage return, a line or paragraph separator), or the end.
    private static func endOfLine(in bytes: UnsafeBufferPointer<UInt8>, from start: Int) -> Int {
        var index = start
        while index < bytes.count {
            let byte = bytes[index]
            if byte == MermaidByte.newline || byte == MermaidByte.carriageReturn { return index }
            if byte == 0xE2, index + 2 < bytes.count, bytes[index + 1] == 0x80, bytes[index + 2] == 0xA8 || bytes[index + 2] == 0xA9 { return index }
            index += 1
        }
        return bytes.count
    }

    /// The first place from `start` where `literal` stands: its first byte looked for sixteen bytes at a time, then
    /// the rest compared.
    static func firstIndex(of literal: [UInt8], in bytes: [UInt8], from start: Int) -> Int? {
        bytes.withUnsafeBufferPointer { buffer in firstIndex(of: literal, in: buffer, from: start) }
    }

    /// The first place from `start` where `literal` stands, in a buffer.
    static func firstIndex(of literal: [UInt8], in bytes: UnsafeBufferPointer<UInt8>, from start: Int) -> Int? {
        guard let first = literal.first else { return nil }
        var index = start
        while let candidate = firstIndex(of: first, in: bytes, from: index), candidate + literal.count <= bytes.count {
            var offset = 1
            while offset < literal.count, bytes[candidate + offset] == literal[offset] { offset += 1 }
            if offset == literal.count { return candidate }
            index = candidate + 1
        }
        return nil
    }

    /// The first `byte` from `start`, looked for sixteen bytes at a time.
    static func firstIndex(of byte: UInt8, in bytes: [UInt8], from start: Int) -> Int? {
        bytes.withUnsafeBufferPointer { buffer in firstIndex(of: byte, in: buffer, from: start) }
    }

    /// The first `byte` from `start` in a buffer, looked for sixteen bytes at a time.
    static func firstIndex(of byte: UInt8, in buffer: UnsafeBufferPointer<UInt8>, from start: Int) -> Int? {
        guard start >= 0 else { return nil }
        var index = start
        if let base = buffer.baseAddress {
            let raw = UnsafeRawPointer(base)
            let target = SIMD16(repeating: byte)
            while index + 16 <= buffer.count, !any(raw.loadUnaligned(fromByteOffset: index, as: SIMD16<UInt8>.self) .== target) { index += 16 }
        }
        while index < buffer.count {
            if buffer[index] == byte { return index }
            index += 1
        }
        return nil
    }

    private static func containsDirectiveStart(_ bytes: [UInt8], from start: Int) -> Bool {
        firstIndex(of: directiveStart, in: bytes, from: start) != nil
    }

    /// Whether `removingDirectives` would find a directive to remove from `start` on: a `%%{`.
    static func containsDirectiveStart(_ bytes: UnsafeBufferPointer<UInt8>, from start: Int) -> Bool {
        firstIndex(of: directiveStart, in: bytes, from: start) != nil
    }

    private static let hash = UInt8(ascii: "#")
    private static let styleKeyword = Array("style".utf8)
    private static let classDefinitionKeyword = Array("classDef".utf8)
    private static let directiveStart = Array("%%{".utf8)
}
