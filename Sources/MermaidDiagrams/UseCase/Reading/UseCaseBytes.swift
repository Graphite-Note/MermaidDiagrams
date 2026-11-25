/**
 * File: UseCaseBytes.swift
 * ------------------------
 * Layer: Core
 * Description: A use case diagram's text as its reader and its model hold it: the UTF-8 bytes its lexer reads, then
 *              the bytes the reading makes (ids made from labels, styles with `\,` read as a comma); where a line is,
 *              and a UTF-16 column made only for an error.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

/// The bytes a use case diagram is read from, made ready as Pele's `parse` makes its text ready
/// (`UseCaseSourcePreparation`), followed by the bytes the reading makes. A range of the model is a range of these.
struct UseCaseBytes: Sendable {
    /// The text, then the bytes made while reading it.
    private(set) var bytes: [UInt8]
    /// The length of the text: what the lexer reads.
    let count: Int
    /// The line breaks taken out with comment lines before the text was read, so that a line is named as written.
    let removedLineBreaks: [UseCaseRemovedLineBreaks]

    init(text: [UInt8], removedLineBreaks: [UseCaseRemovedLineBreaks]) {
        bytes = text
        count = text.count
        self.removedLineBreaks = removedLineBreaks
    }

    /// The byte at `index` of the text, nil outside it.
    @inline(__always) subscript(index: Int) -> UInt8? { index >= 0 && index < count ? bytes[index] : nil }

    /// The bytes of `range` (of the text or of what the reading made) as a String.
    func string(_ range: MermaidTextRange) -> String {
        let start = max(0, min(range.lowerBound, bytes.count))
        let end = max(start, min(range.upperBound, bytes.count))
        return bytes.withUnsafeBufferPointer { buffer in String(decoding: UnsafeBufferPointer(rebasing: buffer[start..<end]), as: UTF8.self) }
    }

    /// `bytes` added after what the reading made so far, and where they are.
    mutating func append<Bytes: Sequence>(_ added: Bytes) -> MermaidTextRange where Bytes.Element == UInt8 {
        let start = bytes.count
        bytes.append(contentsOf: added)
        return MermaidTextRange(start: start, end: bytes.count)
    }

    /// Whether the bytes of two ranges spell one text as Swift compares Strings: byte for byte in ASCII, and beyond it
    /// by canonical equivalence, so that a composed letter and its decomposed spelling are one.
    func spellSame(_ first: MermaidTextRange, _ second: MermaidTextRange) -> Bool {
        bytes.withUnsafeBufferPointer { buffer in
            var isASCII = true
            if first.count == second.count {
                var index = 0
                var isSame = true
                while index < first.count {
                    let byte = buffer[first.lowerBound + index]
                    if byte != buffer[second.lowerBound + index] {
                        isSame = false
                        break
                    }
                    if byte >= 0x80 { isASCII = false }
                    index += 1
                }
                if isSame { return true }
            }
            guard isASCII, Self.isASCII(buffer, first), Self.isASCII(buffer, second) else { return string(first) == string(second) }
            return false
        }
    }

    /// Whether the bytes of `range` spell `word`, an ASCII text.
    func spells(_ range: MermaidTextRange, _ word: StaticString) -> Bool {
        guard range.count == word.utf8CodeUnitCount else { return false }
        return bytes.withUnsafeBufferPointer { buffer in
            let expected = word.utf8Start
            for index in 0..<range.count where buffer[range.lowerBound + index] != expected[index] { return false }
            return true
        }
    }

    /// Whether the bytes of `range` spell `word`, ASCII's lowercase letters, in any case.
    func spellsIgnoringCase(_ range: MermaidTextRange, _ word: StaticString) -> Bool {
        guard range.count == word.utf8CodeUnitCount else { return false }
        return bytes.withUnsafeBufferPointer { buffer in
            let expected = word.utf8Start
            for index in 0..<range.count where buffer[range.lowerBound + index] | 0x20 != expected[index] { return false }
            return true
        }
    }

    private static func isASCII(_ buffer: UnsafeBufferPointer<UInt8>, _ range: MermaidTextRange) -> Bool {
        var index = range.lowerBound
        while index < range.upperBound {
            if buffer[index] >= 0x80 { return false }
            index += 1
        }
        return true
    }

    /// The 1-based line of `offset` in the text as written: counting a line feed, a carriage return, or both together,
    /// as one line break, and the line breaks taken out with comment lines before it.
    func line(of offset: Int) -> Int {
        var line = 1
        var index = 0
        let end = min(offset, count)
        while index < end {
            let byte = bytes[index]
            if byte == 0x0D, index + 1 < end, bytes[index + 1] == 0x0A { index += 1 }
            if byte == 0x0A || byte == 0x0D { line += 1 }
            index += 1
        }
        return line + (removedLineBreaks.last { removal in removal.line <= line }?.count ?? 0)
    }

    /// The 1-based column of `offset` on its line, in UTF-16 code units as Pele counts them: a character of four bytes
    /// counts two, one of fewer bytes one.
    func utf16Column(of offset: Int) -> Int {
        var start = min(offset, count)
        while start > 0, !UseCaseCharacters.isLineBreak(bytes[start - 1]) { start -= 1 }
        var column = 1
        var index = start
        while index < min(offset, count) {
            let byte = bytes[index]
            if byte & 0xC0 != 0x80 { column += byte >= 0xF0 ? 2 : 1 }
            index += 1
        }
        return column
    }
}

/// The text the lexer reads, borrowed: a read past its end is nil, which is in no class.
struct UseCaseLexerText {
    let bytes: UnsafeBufferPointer<UInt8>

    @inline(__always) var count: Int { bytes.count }

    @inline(__always) subscript(index: Int) -> UInt8? { index >= 0 && index < bytes.count ? bytes[index] : nil }

    /// Whether the text at `index` starts with `word`, exactly or, for `include` and `extend`, in any case.
    @inline(__always) func starts(with word: StaticString, at index: Int, ignoringCase: Bool = false) -> Bool {
        let length = word.utf8CodeUnitCount
        guard index >= 0, index + length <= bytes.count else { return false }
        let expected = word.utf8Start
        for offset in 0..<length {
            let byte = bytes[index + offset]
            if ignoringCase ? byte | 0x20 != expected[offset] : byte != expected[offset] { return false }
        }
        return true
    }

    /// The first offset from `index` where the line ends, or the end of the text.
    func lineEnd(from index: Int) -> Int {
        var position = index
        while position < bytes.count, !UseCaseCharacters.isLineBreak(bytes[position]) { position += 1 }
        return position
    }

    /// Whether `start..<end` holds JavaScript's whitespace alone.
    func isWhitespace(from start: Int, to end: Int) -> Bool {
        let range = MermaidTextRange(start: start, end: max(start, end))
        return UseCaseCharacters.trimmed(range, in: bytes).isEmpty
    }

    /// The keyword the text at `index` starts with, tried in the order of Mermaid's token list; `.end` for none.
    func keyword(at index: Int) -> UseCaseTokenKind {
        switch self[index] {
        case UInt8(ascii: "a"): starts(with: "actor", at: index) ? .actor : .end
        case UInt8(ascii: "s"): starts(with: "systemBoundary", at: index) ? .systemBoundary : starts(with: "style", at: index) ? .style : .end
        case UInt8(ascii: "e"): starts(with: "end", at: index) ? .endKeyword : starts(with: "extend", at: index, ignoringCase: true) ? .extend : .end
        case UInt8(ascii: "E"): starts(with: "extend", at: index, ignoringCase: true) ? .extend : .end
        case UInt8(ascii: "d"): starts(with: "direction", at: index) ? .direction : .end
        case UInt8(ascii: "T"): starts(with: "TD", at: index) ? .topDown : starts(with: "TB", at: index) ? .topBottom : .end
        case UInt8(ascii: "B"): starts(with: "BT", at: index) ? .bottomTop : .end
        case UInt8(ascii: "L"): starts(with: "LR", at: index) ? .leftRight : .end
        case UInt8(ascii: "R"): starts(with: "RL", at: index) ? .rightLeft : .end
        case UInt8(ascii: "n"): starts(with: "note", at: index) ? .note : .end
        case UInt8(ascii: "f"): starts(with: "for", at: index) ? .forKeyword : starts(with: "false", at: index) ? .falseKeyword : .end
        case UInt8(ascii: "j"): starts(with: "json", at: index) ? .json : .end
        case UInt8(ascii: "c"): starts(with: "classDef", at: index) ? .classDefinition : starts(with: "class", at: index) ? .classKeyword : .end
        case UInt8(ascii: "i"), UInt8(ascii: "I"): starts(with: "include", at: index, ignoringCase: true) ? .include : .end
        case UInt8(ascii: "t"): starts(with: "true", at: index) ? .trueKeyword : .end
        case UInt8(ascii: "u"): starts(with: "usecase-beta", at: index) ? .useCase : .end
        default: .end
        }
    }
}
