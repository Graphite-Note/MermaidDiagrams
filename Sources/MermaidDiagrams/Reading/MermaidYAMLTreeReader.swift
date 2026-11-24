/**
 * File: MermaidYAMLTreeReader.swift
 * ---------------------------------
 * Layer: Core
 * Description: Reads the YAML front matter is commonly written in, block mappings of plain and quoted scalars, on its
 *              bytes into a flat tree, as Pele's reader reads it; any other YAML is left to that reader.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

/// Reads block mappings of block mappings and single-line scalars on the YAML's bytes, line by line, into the nodes of a
/// `MermaidYAMLTree`, each rule the one `SequenceAttributesBlockSyntax` applies: keys at one indentation, a key with no
/// value on its line taking the deeper lines below it or null, comments and blank lines skipped, plain scalars read with
/// the JSON schema, quoted scalars without an escape or a doubled apostrophe. Gives nil, and so leaves the text to
/// that reference reader, for anything else: a byte that is not printable ASCII or a line feed (a tab, a carriage
/// return, text beyond ASCII), a list, a flow collection, a block scalar, a scalar continued on a later line, an escape,
/// a key written twice, a key that is no plain word and reads as other text than its bytes, a line at an indentation no
/// mapping has, more than `largestMappingCount` entries in a mapping or mappings nested deeper than `deepestNesting`.
/// What it reads is what the reference reads (`MermaidYAMLTreeEquivalenceTests`); what it leaves, the reference reads
/// or refuses.
struct MermaidYAMLTreeReader {
    static let deepestNesting = 32
    static let largestMappingCount = 128

    /// A line of the YAML: where it starts, where its text starts after its spaces, and where its line feed stands.
    private struct Line {
        let start: Int
        let contentStart: Int
        let end: Int

        var indent: Int { contentStart - start }
    }

    private let bytes: UnsafeBufferPointer<UInt8>
    private var nodes: [MermaidYAMLNode] = []
    /// The start of the first line not yet read.
    private var position = 0

    private init(bytes: UnsafeBufferPointer<UInt8>) {
        self.bytes = bytes
    }

    /// The tree `yaml` holds, its ranges into `yaml`; nil when it is not read here.
    static func tree(of yaml: [UInt8]) -> MermaidYAMLTree? {
        let nodes: [MermaidYAMLNode]? = yaml.withUnsafeBufferPointer { buffer in
            guard isPrintableASCII(buffer) else { return nil }
            var reader = MermaidYAMLTreeReader(bytes: buffer)
            return reader.document()
        }
        return nodes.map { nodes in MermaidYAMLTree(bytes: yaml, nodes: nodes) }
    }

    /// Whether every byte is printable ASCII or a line feed, looked at sixteen at a time.
    private static func isPrintableASCII(_ bytes: UnsafeBufferPointer<UInt8>) -> Bool {
        var index = 0
        if let base = bytes.baseAddress {
            let raw = UnsafeRawPointer(base)
            let lowest = SIMD16<UInt8>(repeating: 0x20)
            let highest = SIMD16<UInt8>(repeating: 0x7E)
            let lineFeed = SIMD16<UInt8>(repeating: MermaidByte.newline)
            while index + 16 <= bytes.count {
                let chunk = raw.loadUnaligned(fromByteOffset: index, as: SIMD16<UInt8>.self)
                let outside = ((chunk .< lowest) .& (chunk .!= lineFeed)) .| (chunk .> highest)
                if any(outside) { return false }
                index += 16
            }
        }
        while index < bytes.count {
            let byte = bytes[index]
            if (byte < 0x20 && byte != MermaidByte.newline) || byte > 0x7E { return false }
            index += 1
        }
        return true
    }

    private mutating func document() -> [MermaidYAMLNode]? {
        guard let first = contentLine(from: 0) else { return nil }
        let firstByte = bytes[first.contentStart]
        guard firstByte != MermaidByte.openingBrace, firstByte != MermaidByte.openingBracket else { return nil }
        nodes.reserveCapacity(16)
        nodes.append(MermaidYAMLNode(kind: .mapping, key: MermaidTextRange(start: 0, end: 0)))
        guard mapping(indent: first.indent, depth: 0, parent: MermaidYAMLTree.root), contentLine(from: position) == nil else { return nil }
        return nodes
    }

    /// The first line from `start` that the reference does not skip: one that is not blank, not a comment and not `---`.
    private func contentLine(from start: Int) -> Line? {
        var lineStart = start
        while lineStart < bytes.count {
            let end = MermaidPreprocessing.firstIndex(of: MermaidByte.newline, in: bytes, from: lineStart) ?? bytes.count
            var contentStart = lineStart
            while contentStart < end, bytes[contentStart] == MermaidByte.space { contentStart += 1 }
            if contentStart < end, bytes[contentStart] != Self.hash, !isDocumentStart(contentStart..<end) {
                return Line(start: lineStart, contentStart: contentStart, end: end)
            }
            lineStart = end + 1
        }
        return nil
    }

    /// Whether the text, without its trailing spaces, is `---`.
    private func isDocumentStart(_ content: Range<Int>) -> Bool {
        var end = content.upperBound
        while end > content.lowerBound, bytes[end - 1] == MermaidByte.space { end -= 1 }
        return end - content.lowerBound == 3 && bytes[content.lowerBound] == MermaidByte.hyphen && bytes[content.lowerBound + 1] == MermaidByte.hyphen
            && bytes[content.lowerBound + 2] == MermaidByte.hyphen
    }

    /// The entries at `indent`, children of `parent`: false when a line is not read here.
    private mutating func mapping(indent: Int, depth: Int, parent: Int) -> Bool {
        guard depth <= Self.deepestNesting else { return false }
        var previous = -1
        var count = 0
        while let line = contentLine(from: position) {
            if line.indent < indent { break }
            guard line.indent == indent, let (key, valueStart) = splitKey(line) else { return false }
            position = line.end + 1
            count += 1
            guard count <= Self.largestMappingCount, !hasKey(key, among: parent) else { return false }
            let node = nodes.count
            nodes.append(MermaidYAMLNode(kind: .null, key: MermaidTextRange(start: key.lowerBound, end: key.upperBound)))
            if previous < 0 { nodes[parent].firstChild = Int32(node) } else { nodes[previous].nextSibling = Int32(node) }
            previous = node
            let rest = valueStart..<line.end
            let comment = commentStart(in: rest)
            if isBlank(rest.lowerBound..<comment) {
                guard valueBelow(keyIndent: indent, depth: depth, node: node) else { return false }
            } else {
                guard inlineValue(rest, beforeComment: comment, keyIndent: indent, node: node) else { return false }
            }
        }
        return true
    }

    /// Whether a child of `parent` has the key `key`'s bytes.
    private func hasKey(_ key: Range<Int>, among parent: Int) -> Bool {
        var child = Int(nodes[parent].firstChild)
        while child >= 0 {
            let other = nodes[child].key
            if other.count == key.count, bytes[other.lowerBound..<other.upperBound].elementsEqual(bytes[key]) { return true }
            child = Int(nodes[child].nextSibling)
        }
        return false
    }

    /// The value of a key with nothing on its line: the deeper mapping below it, or null.
    private mutating func valueBelow(keyIndent: Int, depth: Int, node: Int) -> Bool {
        guard let next = contentLine(from: position) else { return true }
        if isListItem(next) { return next.indent < keyIndent }
        guard next.indent > keyIndent else { return true }
        nodes[node].kind = .mapping
        return mapping(indent: next.indent, depth: depth + 1, parent: node)
    }

    /// Whether the line is a list item: `-` alone, or `-` and a space.
    private func isListItem(_ line: Line) -> Bool {
        bytes[line.contentStart] == MermaidByte.hyphen && (line.contentStart + 1 == line.end || bytes[line.contentStart + 1] == MermaidByte.space)
    }

    /// The scalar after a key, alone on its line: quoted, or plain and read with the JSON schema.
    private mutating func inlineValue(_ rest: Range<Int>, beforeComment comment: Int, keyIndent: Int, node: Int) -> Bool {
        let first = bytes[rest.lowerBound]
        switch first {
        case Self.verticalBar, MermaidByte.greaterThan, MermaidByte.openingBrace, MermaidByte.openingBracket: return false
        case MermaidByte.quotationMark, Self.apostrophe:
            var close = rest.lowerBound + 1
            while close < rest.upperBound, bytes[close] != first {
                if bytes[close] == Self.backslash, first == MermaidByte.quotationMark { return false }
                close += 1
            }
            guard close < rest.upperBound else { return false }
            if first == Self.apostrophe, close + 1 < rest.upperBound, bytes[close + 1] == Self.apostrophe { return false }
            let after = (close + 1)..<rest.upperBound
            guard isBlank(after.lowerBound..<commentStart(in: after)) else { return false }
            nodes[node].kind = .text
            nodes[node].text = MermaidTextRange(start: rest.lowerBound + 1, end: close)
            return true
        default:
            guard !continuesOnLaterLine(keyIndent: keyIndent) else { return false }
            var end = comment
            while end > rest.lowerBound, bytes[end - 1] == MermaidByte.space { end -= 1 }
            return plainScalar(rest.lowerBound..<end, node: node)
        }
    }

    /// Whether the next line that is not blank is deeper than the key, which makes it part of a plain scalar.
    private func continuesOnLaterLine(keyIndent: Int) -> Bool {
        var lineStart = position
        while lineStart < bytes.count {
            let end = MermaidPreprocessing.firstIndex(of: MermaidByte.newline, in: bytes, from: lineStart) ?? bytes.count
            var contentStart = lineStart
            while contentStart < end, bytes[contentStart] == MermaidByte.space { contentStart += 1 }
            if contentStart < end { return contentStart - lineStart > keyIndent }
            lineStart = end + 1
        }
        return false
    }

    /// A plain scalar's node, as `SequenceAttributesScalarSyntax.scalar` reads it: null, a Boolean, a number, or text.
    private mutating func plainScalar(_ range: Range<Int>, node: Int) -> Bool {
        let first = bytes[range.lowerBound]
        if first == MermaidByte.hyphen || first == Self.plus || first == MermaidByte.period || MermaidByte.isDigit(first) || isSpelledWord(range) {
            let value: DirectiveValue = SequenceAttributesScalarSyntax.scalar(Array(bytes[range])[...])
            switch value {
            case .null: return true
            case .boolean(let boolean):
                nodes[node].kind = boolean ? .trueBoolean : .falseBoolean
                return true
            case .number(let number):
                nodes[node].kind = .number
                nodes[node].number = number
                return true
            case .array, .object: return false
            // Its text is its bytes, trimmed already.
            case .text: break
            }
        }
        nodes[node].kind = .text
        nodes[node].text = MermaidTextRange(start: range.lowerBound, end: range.upperBound)
        return true
    }

    /// Whether the range may be a spelling the JSON schema reads as no text: `~`, or a four or five letter word that
    /// starts as `null`, `true` or `false` do.
    private func isSpelledWord(_ range: Range<Int>) -> Bool {
        switch range.count {
        case 1: bytes[range.lowerBound] == MermaidByte.tilde
        case 4: [UInt8(ascii: "n"), UInt8(ascii: "N"), UInt8(ascii: "t"), UInt8(ascii: "T")].contains(bytes[range.lowerBound])
        case 5: bytes[range.lowerBound] == UInt8(ascii: "f") || bytes[range.lowerBound] == UInt8(ascii: "F")
        default: false
        }
    }

    /// `key: rest` as the reference splits it: the key's text range (inside its quotation marks when quoted) and where
    /// its value starts; nil when the line is not read here.
    private func splitKey(_ line: Line) -> (key: Range<Int>, valueStart: Int)? {
        let start = line.contentStart
        let first = bytes[start]
        let key: Range<Int>
        var colon: Int
        if first == MermaidByte.quotationMark || first == Self.apostrophe {
            var close = start + 1
            while close < line.end, bytes[close] != first {
                if bytes[close] == Self.backslash, first == MermaidByte.quotationMark { return nil }
                close += 1
            }
            guard close < line.end else { return nil }
            if first == Self.apostrophe, close + 1 < line.end, bytes[close + 1] == Self.apostrophe { return nil }
            key = (start + 1)..<close
            colon = close + 1
            while colon < line.end, bytes[colon] == MermaidByte.space { colon += 1 }
            guard colon < line.end, bytes[colon] == MermaidByte.colon else { return nil }
        } else {
            guard !Self.keyRefusingFirstBytes.contains(first), first != MermaidByte.hyphen else { return nil }
            colon = start + 1
            while colon < line.end, bytes[colon] != MermaidByte.colon, bytes[colon] != Self.hash { colon += 1 }
            guard colon < line.end, bytes[colon] == MermaidByte.colon else { return nil }
            var end = colon
            while end > start, bytes[end - 1] == MermaidByte.space { end -= 1 }
            key = start..<end
            guard isWordKey(key) || readsAsItsBytes(key) else { return nil }
        }
        var valueStart = colon + 1
        if valueStart < line.end, bytes[valueStart] != MermaidByte.space { return nil }
        while valueStart < line.end, bytes[valueStart] == MermaidByte.space { valueStart += 1 }
        return (key, valueStart)
    }

    /// A key the reference keeps as written: a letter or an underscore, then letters, digits, underscores and hyphens,
    /// and not a spelling of null or a Boolean.
    private func isWordKey(_ key: Range<Int>) -> Bool {
        let first = bytes[key.lowerBound]
        guard MermaidByte.isLetter(first) || first == MermaidByte.underscore else { return false }
        for index in key where !(MermaidByte.isLetter(bytes[index]) || MermaidByte.isDigit(bytes[index]) || bytes[index] == MermaidByte.underscore
                                 || bytes[index] == MermaidByte.hyphen) { return false }
        return !isSpelledWord(key)
    }

    /// Whether another plain key reads, as the reference reads it (a plain scalar written as JavaScript writes it), as
    /// its own bytes: `Electricity grid`, `.ts`, but not `1.0` or `null`.
    private func readsAsItsBytes(_ key: Range<Int>) -> Bool {
        let value: SequenceAttributeValue = SequenceAttributesScalarSyntax.scalar(Array(bytes[key])[...])
        guard case .text(let text) = value else { return false }
        return text.utf8.elementsEqual(bytes[key])
    }

    /// Where the comment of `range` starts, its end when it has none: a `#` at its start or after a space, outside
    /// quotation marks, as the reference finds it.
    private func commentStart(in range: Range<Int>) -> Int {
        var quote: UInt8?
        var index = range.lowerBound
        while index < range.upperBound {
            let byte = bytes[index]
            if let open = quote {
                if byte == Self.backslash, open == MermaidByte.quotationMark { index += 1 } else if byte == open { quote = nil }
            } else if byte == MermaidByte.quotationMark || byte == Self.apostrophe {
                quote = byte
            } else if byte == Self.hash, index == range.lowerBound || bytes[index - 1] == MermaidByte.space {
                return index
            }
            index += 1
        }
        return range.upperBound
    }

    private func isBlank(_ range: Range<Int>) -> Bool {
        for index in range where bytes[index] != MermaidByte.space { return false }
        return true
    }

    /// What a plain key cannot start with, as the reference refuses it: YAML's indicators.
    private static let keyRefusingFirstBytes = YAMLBytes.ASCIISet(Array("#:,[]{}&*!|>'\"%@`".unicodeScalars))
    private static let hash = UInt8(ascii: "#")
    private static let apostrophe = UInt8(ascii: "'")
    private static let backslash = UInt8(ascii: "\\")
    private static let verticalBar = UInt8(ascii: "|")
    private static let plus = UInt8(ascii: "+")
}
