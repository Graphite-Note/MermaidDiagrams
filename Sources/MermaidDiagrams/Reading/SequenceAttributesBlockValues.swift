/**
 * File: SequenceAttributesBlockValues.swift
 * -----------------------------------------
 * Layer: Core
 * Description: The values on a YAML block line (a flow value that may run over several lines, a `|` or `>` scalar, a
 *              plain scalar continued on deeper lines), a line's key and its comment, as Pele's YAML reader reads them.
 *
 * Authors: Bahey Shalash
 * Version: 0.6
 * Date: 23/11/2026
 */

extension SequenceAttributesBlockSyntax {
    /// The value written after a key or a list item's dash (`rest`, of a line already passed), maybe continued on later
    /// lines.
    mutating func inlineValue<Value: MermaidYAMLValue>(_ rest: Range<Int>, indent: Int) throws(SequenceAttributesYAMLFailure) -> Value {
        guard let first = rest.first.map({ index in bytes[index] }) else { return .null }
        if first == UInt8(ascii: "|") || first == UInt8(ascii: ">"), isBlockScalarHeader(rest) { return blockScalar(header: rest, parentIndent: indent) }
        if first == YAMLBytes.openingBrace || first == YAMLBytes.openingBracket || first == YAMLBytes.quotationMark || first == YAMLBytes.apostrophe {
            return try flowValue(rest)
        }
        let firstLine = YAMLBytes.trimmedBounds(in: bytes, rest.lowerBound..<commentStart(in: rest))
        // The text is copied only when a later line continues it.
        var text: [UInt8] = []
        var isContinued = false
        while lineIndex < lines.count {
            let line = lines[lineIndex]
            if YAMLBytes.isBlank(in: bytes, line) {
                var next = lineIndex
                while next < lines.count, YAMLBytes.isBlank(in: bytes, lines[next]) { next += 1 }
                if next >= lines.count || leadingWhitespaceCount(of: lines[next]) <= indent { break }
                if !isContinued { text = Array(bytes[firstLine]) }
                isContinued = true
                text.append(contentsOf: repeatElement(YAMLBytes.newline, count: next - lineIndex))
                lineIndex = next
                continue
            }
            if leadingWhitespaceCount(of: line) <= indent { break }
            if !isContinued { text = Array(bytes[firstLine]) }
            isContinued = true
            if text.last != YAMLBytes.newline { text.append(YAMLBytes.space) }
            text.append(contentsOf: bytes[YAMLBytes.trimmedBounds(in: bytes, line.lowerBound..<commentStart(in: line))])
            lineIndex += 1
        }
        return SequenceAttributesScalarSyntax.scalar(isContinued ? text[...] : bytes[firstLine])
    }

    /// A flow value that may continue on later lines: read on its own line, then again with more lines, in growing
    /// batches, until it closes.
    private mutating func flowValue<Value: MermaidYAMLValue>(_ rest: Range<Int>) throws(SequenceAttributesYAMLFailure) -> Value {
        let start = lineIndex
        do throws(SequenceAttributesYAMLFailure) {
            let (value, end): (Value, Int) = try SequenceAttributesFlowSyntax.value(in: bytes, within: rest, at: rest.lowerBound, stops: .none)
            guard isBlankBeforeComment(end..<rest.upperBound) else { throw .invalid }
            return value
        } catch {
            guard error == .incomplete, start < lines.count else { throw .invalid }
        }
        var text = Array(bytes[rest])
        var takenLineCount = 0
        var batchSize = 1
        while true {
            let more = lines[(start + takenLineCount)..<min(lines.count, start + takenLineCount + batchSize)]
            for line in more {
                text.append(YAMLBytes.newline)
                text.append(contentsOf: bytes[line])
            }
            takenLineCount += more.count
            batchSize *= 2
            do throws(SequenceAttributesYAMLFailure) {
                let (value, end): (Value, Int) = try SequenceAttributesFlowSyntax.value(in: text, within: text.indices, at: 0, stops: .none)
                let usedLineCount = text[..<end].count { byte in byte == YAMLBytes.newline }
                let lineEnd = YAMLBytes.firstIndex(of: YAMLBytes.newline, in: text, end..<text.count)
                guard Self.isBlankBeforeComment(in: text, end..<lineEnd) else { throw .invalid }
                lineIndex = start + usedLineCount
                return value
            } catch {
                guard error == .incomplete, start + takenLineCount < lines.count else { throw .invalid }
            }
        }
    }

    /// `|` or `>`, then chomping and indentation indicators, then maybe a comment.
    private func isBlockScalarHeader(_ header: Range<Int>) -> Bool {
        var index = header.lowerBound + 1
        while index < header.upperBound, bytes[index] == UInt8(ascii: "-") || bytes[index] == UInt8(ascii: "+") || isDigit(bytes[index]) { index += 1 }
        while index < header.upperBound, case let length = YAMLBytes.whitespaceLength(in: bytes, at: index, end: header.upperBound), length > 0 {
            index += length
        }
        return index == header.upperBound || bytes[index] == YAMLBytes.hash
    }

    /// A `|` (literal) or `>` (folded) scalar: the lines deeper than its parent, chomped as its header says.
    private mutating func blockScalar<Value: MermaidYAMLValue>(header: Range<Int>, parentIndent: Int) -> Value {
        let isFolded = bytes[header.lowerBound] == UInt8(ascii: ">")
        let headerBytes = bytes[header]
        let chomping: UInt8? = headerBytes.contains(UInt8(ascii: "-")) ? UInt8(ascii: "-")
            : headerBytes.contains(UInt8(ascii: "+")) ? UInt8(ascii: "+") : nil
        var indent = headerBytes.first { byte in byte >= UInt8(ascii: "1") && byte <= UInt8(ascii: "9") }
            .map { digit in parentIndent + Int(digit - UInt8(ascii: "0")) } ?? -1
        // A blank line is an empty range.
        var body: [Range<Int>] = []
        while lineIndex < lines.count {
            let line = lines[lineIndex]
            if YAMLBytes.isBlank(in: bytes, line) {
                body.append(0..<0)
                lineIndex += 1
                continue
            }
            let lineIndent = leadingWhitespaceCount(of: line)
            if indent == -1 {
                if lineIndent <= parentIndent { break }
                indent = lineIndent
            }
            if lineIndent < indent { break }
            body.append(YAMLBytes.passingLeadingWhitespace(indent, in: bytes, line)..<line.upperBound)
            lineIndex += 1
        }
        var trailingEmptyCount = 0
        while body.last?.isEmpty == true {
            body.removeLast()
            trailingEmptyCount += 1
        }
        if body.isEmpty { return .text(chomping == UInt8(ascii: "+") ? String(repeating: "\n", count: trailingEmptyCount) : "") }
        let text = String(decoding: isFolded ? folded(body) : joined(body), as: UTF8.self)
        switch chomping {
        case UInt8(ascii: "-"): return .text(text)
        case UInt8(ascii: "+"): return .text(text + String(repeating: "\n", count: trailingEmptyCount + 1))
        default: return .text(text + "\n")
        }
    }

    /// A `|` scalar's lines joined by line breaks.
    private func joined(_ body: [Range<Int>]) -> [UInt8] {
        var text: [UInt8] = []
        for (index, line) in body.enumerated() {
            if index > 0 { text.append(YAMLBytes.newline) }
            text.append(contentsOf: bytes[line])
        }
        return text
    }

    /// A `>` scalar's lines joined: a space between two lines of text, a line break for each empty line, and the breaks
    /// kept around lines that start with a blank.
    private func folded(_ body: [Range<Int>]) -> [UInt8] {
        let startsWithBlank = { (line: Range<Int>) in
            !line.isEmpty && (bytes[line.lowerBound] == YAMLBytes.space || bytes[line.lowerBound] == YAMLBytes.tab)
        }
        var text: [UInt8] = []
        for (index, line) in body.enumerated() {
            if index > 0 {
                let previous = body[index - 1]
                if line.isEmpty {
                    text.append(YAMLBytes.newline)
                } else if !previous.isEmpty {
                    text.append(startsWithBlank(previous) || startsWithBlank(line) ? YAMLBytes.newline : YAMLBytes.space)
                }
            }
            text.append(contentsOf: bytes[line])
        }
        return text
    }

    /// `key: rest` at the start of a line: the key as written and where its value starts; nil when the line holds none.
    func splitKey(_ line: Range<Int>) -> (key: Range<Int>, valueStart: Int)? {
        guard let start = line.first else { return nil }
        let first = bytes[start]
        let keyEnd: Int
        var colon: Int
        if first == YAMLBytes.quotationMark || first == YAMLBytes.apostrophe {
            // A backslash takes the byte after it; the rest of a scalar it escapes is never a quotation mark.
            var index = start + 1
            while true {
                guard index < line.upperBound else { return nil }
                if first == YAMLBytes.quotationMark, bytes[index] == YAMLBytes.backslash {
                    index += 2
                } else if bytes[index] == first {
                    if first == YAMLBytes.quotationMark || index + 1 >= line.upperBound || bytes[index + 1] != YAMLBytes.apostrophe { break }
                    index += 2
                } else {
                    index += 1
                }
            }
            keyEnd = index + 1
            colon = keyEnd
            while colon < line.upperBound, Self.isBlank(bytes[colon]) { colon += 1 }
            guard colon < line.upperBound, bytes[colon] == YAMLBytes.colon else { return nil }
        } else {
            guard !YAMLBytes.isWhitespace(in: bytes, at: start, end: line.upperBound), !Self.keyRefusingFirstBytes.contains(first) else { return nil }
            if first == YAMLBytes.hyphen, line.count < 2 || Self.isBlank(bytes[start + 1]) || bytes[start + 1] == YAMLBytes.colon
                || bytes[start + 1] == YAMLBytes.hash { return nil }
            colon = start + 1
            while colon < line.upperBound, bytes[colon] != YAMLBytes.colon, bytes[colon] != YAMLBytes.hash { colon += 1 }
            guard colon < line.upperBound, bytes[colon] == YAMLBytes.colon else { return nil }
            var end = colon
            while end > start, Self.isBlank(bytes[end - 1]) { end -= 1 }
            keyEnd = end
        }
        var valueStart = colon + 1
        if valueStart < line.upperBound, !Self.isBlank(bytes[valueStart]) { return nil }
        while valueStart < line.upperBound, Self.isBlank(bytes[valueStart]) { valueStart += 1 }
        return (start..<keyEnd, valueStart)
    }

    /// What a plain key cannot start with: white space aside, YAML's indicators.
    private static let keyRefusingFirstBytes = YAMLBytes.ASCIISet(Array("#:,[]{}&*!|>'\"%@`".unicodeScalars))

    /// The text of a key written as an ASCII word, a letter or an underscore then letters, digits, underscores and
    /// hyphens, read as the JSON schema reads a plain scalar: its own text, but for the spellings of null and the
    /// Booleans. Nil for any other key, which is read as a flow value.
    static func plainKeyText(_ key: Text) -> String? {
        let bytes = Array(UnicodeScalarText.string(key).utf8)
        return plainKeyText(in: bytes, bytes.indices)
    }

    func plainKeyText(_ key: Range<Int>) -> String? {
        Self.plainKeyText(in: bytes, key)
    }

    private static func plainKeyText(in bytes: [UInt8], _ key: Range<Int>) -> String? {
        guard let first = key.first, isWordStart(bytes[first]), bytes[key].allSatisfy(isWordByte) else { return nil }
        if key.count == 4 || key.count == 5, nullAndBooleanSpellings.contains(where: { spelling in spelling.elementsEqual(bytes[key]) }) { return nil }
        return YAMLBytes.string(bytes, key)
    }

    private static func isWordByte(_ byte: UInt8) -> Bool {
        isWordStart(byte) || byte == YAMLBytes.hyphen || (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9"))
    }

    private static func isWordStart(_ byte: UInt8) -> Bool {
        (byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z")) || (byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z")) || byte == UInt8(ascii: "_")
    }

    private func isDigit(_ byte: UInt8) -> Bool {
        byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9")
    }

    private static let nullAndBooleanSpellings = ["null", "Null", "NULL", "true", "True", "TRUE", "false", "False", "FALSE"].map { spelling in
        Array(spelling.utf8)
    }

    /// Whether the line holds nothing but white space before its comment.
    func isBlankBeforeComment(_ line: Range<Int>) -> Bool {
        Self.isBlankBeforeComment(in: bytes, line)
    }

    private static func isBlankBeforeComment(in bytes: [UInt8], _ line: Range<Int>) -> Bool {
        YAMLBytes.isBlank(in: bytes, line.lowerBound..<commentStart(in: bytes, line))
    }

    /// Where the line's comment starts, its end when it has none: a `#` at its start or after a space or a tab, outside
    /// quotation marks.
    func commentStart(in line: Range<Int>) -> Int {
        Self.commentStart(in: bytes, line)
    }

    private static func commentStart(in bytes: [UInt8], _ line: Range<Int>) -> Int {
        var quote: UInt8?
        var index = line.lowerBound
        while index < line.upperBound {
            let byte = bytes[index]
            if let open = quote {
                if byte == YAMLBytes.backslash, open == YAMLBytes.quotationMark { index += 1 } else if byte == open { quote = nil }
            } else if byte == YAMLBytes.quotationMark || byte == YAMLBytes.apostrophe {
                quote = byte
            } else if byte == YAMLBytes.hash, index == line.lowerBound || bytes[index - 1] == YAMLBytes.space || bytes[index - 1] == YAMLBytes.tab {
                return index
            }
            index += 1
        }
        return line.upperBound
    }

    private static func isBlank(_ byte: UInt8) -> Bool {
        byte == YAMLBytes.space || byte == YAMLBytes.tab || byte == YAMLBytes.newline || byte == YAMLBytes.carriageReturn
    }

    /// How many white-space scalars a line starts with, as JavaScript's `trimStart` counts them.
    private func leadingWhitespaceCount(of line: Range<Int>) -> Int {
        YAMLBytes.leadingWhitespace(in: bytes, line, orByteOrderMark: true).scalarCount
    }
}
