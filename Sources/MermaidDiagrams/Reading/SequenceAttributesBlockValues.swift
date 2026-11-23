/**
 * File: SequenceAttributesBlockValues.swift
 * -----------------------------------------
 * Layer: Core
 * Description: The values on a YAML block line (a flow value that may run over several lines, a `|` or `>` scalar, a
 *              plain scalar continued on deeper lines), a line's key and its comment, as Pele's YAML reader reads them.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 23/11/2026
 */

extension SequenceAttributesBlockSyntax {
    /// The value written after a key or a list item's dash, on the line already passed and maybe on later ones.
    mutating func inlineValue(_ rest: Text, indent: Int) throws(SequenceAttributesYAMLFailure) -> SequenceAttributeValue {
        guard let first = rest.first else { return .null }
        if first == "|" || first == ">", Self.isBlockScalarHeader(rest) { return blockScalar(header: rest, parentIndent: indent) }
        if first == "{" || first == "[" || first == "\"" || first == "'" { return try flowValue(rest) }
        var text = Self.trimmed(Self.withoutComment(rest))
        while lineIndex < lines.count {
            let line = lines[lineIndex]
            if SequenceAttributesFlowSyntax.trimmedBounds(line).isEmpty {
                var next = lineIndex
                while next < lines.count, SequenceAttributesFlowSyntax.trimmedBounds(lines[next]).isEmpty { next += 1 }
                if next >= lines.count || Self.leadingWhitespace(of: lines[next]) <= indent { break }
                text += Array(repeating: "\n", count: next - lineIndex)
                lineIndex = next
                continue
            }
            if Self.leadingWhitespace(of: line) <= indent { break }
            if text.last != "\n" { text.append(" ") }
            text += Self.trimmed(Self.withoutComment(line))
            lineIndex += 1
        }
        return SequenceAttributesScalarSyntax.scalar(SequenceAttributesFlowSyntax.string(text))
    }

    /// A flow value that may continue on later lines: read again with more lines, in growing batches, until it closes.
    private mutating func flowValue(_ rest: Text) throws(SequenceAttributesYAMLFailure) -> SequenceAttributeValue {
        let start = lineIndex
        var text = rest
        var takenLineCount = 0
        var batchSize = 1
        while true {
            do throws(SequenceAttributesYAMLFailure) {
                let (value, end) = try SequenceAttributesFlowSyntax.value(in: text, at: 0, stops: [])
                let usedLineCount = text[..<end].count { scalar in scalar == "\n" }
                let lineEnd = text[end...].firstIndex(of: "\n") ?? text.count
                guard Self.isBlankBeforeComment(Array(text[end..<lineEnd])) else { throw .invalid }
                lineIndex = start + usedLineCount
                return value
            } catch {
                guard error == .incomplete, start + takenLineCount < lines.count else { throw .invalid }
                let more = lines[(start + takenLineCount)..<min(lines.count, start + takenLineCount + batchSize)]
                for line in more { text += ["\n"] + line }
                takenLineCount += more.count
                batchSize *= 2
            }
        }
    }

    /// `|` or `>`, then chomping and indentation indicators, then maybe a comment.
    private static func isBlockScalarHeader(_ header: Text) -> Bool {
        var rest = header.dropFirst()
        while let scalar = rest.first, scalar == "-" || scalar == "+" || ("0"..."9").contains(scalar) { rest = rest.dropFirst() }
        while let scalar = rest.first, SequenceAttributesFlowSyntax.isWhitespace(scalar) { rest = rest.dropFirst() }
        return rest.isEmpty || rest.first == "#"
    }

    /// A `|` (literal) or `>` (folded) scalar: the lines deeper than its parent, chomped as its header says.
    private mutating func blockScalar(header: Text, parentIndent: Int) -> SequenceAttributeValue {
        let isFolded = header[0] == ">"
        let chomping: Unicode.Scalar? = header.contains("-") ? "-" : header.contains("+") ? "+" : nil
        var indent = header.first { scalar in ("1"..."9").contains(scalar) }.map { digit in parentIndent + Int(digit.value - 48) } ?? -1
        var body: [Text] = []
        while lineIndex < lines.count {
            let line = lines[lineIndex]
            if Self.trimmed(line).isEmpty {
                body.append([])
                lineIndex += 1
                continue
            }
            let lineIndent = Self.leadingWhitespace(of: line)
            if indent == -1 {
                if lineIndent <= parentIndent { break }
                indent = lineIndent
            }
            if lineIndent < indent { break }
            body.append(Array(line.dropFirst(indent)))
            lineIndex += 1
        }
        var trailingEmptyCount = 0
        while body.last?.isEmpty == true {
            body.removeLast()
            trailingEmptyCount += 1
        }
        if body.isEmpty { return .text(chomping == "+" ? String(repeating: "\n", count: trailingEmptyCount) : "") }
        let text = SequenceAttributesFlowSyntax.string(isFolded ? Self.folded(body) : Array(body.joined(separator: ["\n"])))
        switch chomping {
        case "-": return .text(text)
        case "+": return .text(text + String(repeating: "\n", count: trailingEmptyCount + 1))
        default: return .text(text + "\n")
        }
    }

    /// A `>` scalar's lines joined: a space between two lines of text, a line break for each empty line, and the breaks
    /// kept around lines that start with a blank.
    private static func folded(_ body: [Text]) -> Text {
        var text: Text = []
        for (index, line) in body.enumerated() {
            if index > 0 {
                let previous = body[index - 1]
                if line.isEmpty {
                    text.append("\n")
                } else if !previous.isEmpty {
                    let startsWithBlank = { (text: Text) in text.first == " " || text.first == "\t" }
                    text.append(startsWithBlank(previous) || startsWithBlank(line) ? "\n" : " ")
                }
            }
            text += line
        }
        return text
    }

    /// `key: rest` at the start of a line: the key as written and where its value starts; nil when the line holds none.
    static func splitKey(_ line: Text) -> (key: Text, valueStart: Int)? {
        guard let first = line.first else { return nil }
        let keyEnd: Int
        var colon: Int
        if first == "\"" || first == "'" {
            var index = 1
            while true {
                guard index < line.count else { return nil }
                if first == "\"", line[index] == "\\" {
                    index += 2
                } else if line[index] == first {
                    if first == "\"" || index + 1 >= line.count || line[index + 1] != "'" { break }
                    index += 2
                } else {
                    index += 1
                }
            }
            keyEnd = index + 1
            colon = keyEnd
            while colon < line.count, isBlank(line[colon]) { colon += 1 }
            guard colon < line.count, line[colon] == ":" else { return nil }
        } else {
            guard !SequenceAttributesFlowSyntax.isWhitespace(first), !"#:,[]{}&*!|>'\"%@`".unicodeScalars.contains(first) else { return nil }
            if first == "-", line.count < 2 || isBlank(line[1]) || line[1] == ":" || line[1] == "#" { return nil }
            colon = 1
            while colon < line.count, line[colon] != ":", line[colon] != "#" { colon += 1 }
            guard colon < line.count, line[colon] == ":" else { return nil }
            var end = colon
            while end > 0, isBlank(line[end - 1]) { end -= 1 }
            keyEnd = end
        }
        var valueStart = colon + 1
        if valueStart < line.count, !isBlank(line[valueStart]) { return nil }
        while valueStart < line.count, isBlank(line[valueStart]) { valueStart += 1 }
        return (Array(line[..<keyEnd]), valueStart)
    }

    /// The line up to a comment: a `#` at its start or after a space or a tab, outside quotation marks.
    static func withoutComment(_ line: Text) -> Text {
        let end = commentStart(in: line)
        return end == line.count ? line : Array(line[..<end])
    }

    /// Whether the line holds nothing but white space before its comment, found without copying it.
    static func isBlankBeforeComment(_ line: Text) -> Bool {
        SequenceAttributesFlowSyntax.trimmedBounds(line[..<commentStart(in: line)]).isEmpty
    }

    /// Where the line's comment starts, its length when it has none.
    private static func commentStart(in line: Text) -> Int {
        var quote: Unicode.Scalar?
        var index = 0
        while index < line.count {
            let scalar = line[index]
            if let open = quote {
                if scalar == "\\", open == "\"" { index += 1 } else if scalar == open { quote = nil }
            } else if scalar == "\"" || scalar == "'" {
                quote = scalar
            } else if scalar == "#", index == 0 || line[index - 1] == " " || line[index - 1] == "\t" {
                return index
            }
            index += 1
        }
        return line.count
    }

    private static func isBlank(_ scalar: Unicode.Scalar) -> Bool {
        scalar == " " || scalar == "\t" || scalar == "\n" || scalar == "\r"
    }

    /// How many white-space scalars a line starts with, as JavaScript's `trimStart` counts them.
    private static func leadingWhitespace(of line: Text) -> Int {
        line.prefix { scalar in SequenceAttributesFlowSyntax.isWhitespace(scalar) || scalar == "\u{FEFF}" }.count
    }
}
