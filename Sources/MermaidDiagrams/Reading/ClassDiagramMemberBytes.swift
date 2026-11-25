/**
 * File: ClassDiagramMemberBytes.swift
 * -----------------------------------
 * Layer: Core
 * Description: A class member's text of ASCII bytes read as ClassDiagramMemberSyntax reads it, on its bytes: the
 *              text shown written into one list of bytes and made a String once, where the String reading makes one for
 *              each piece.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

/// `ClassDiagramMemberSyntax.member(from:)` for a text of ASCII bytes, where each byte is a character, so that every
/// search, trim, split and drop on characters is one on bytes. The shown text is decoded for entity codes only when it
/// holds a semicolon, without which `DiagramLabelDecoder.decodingEntities` leaves text as it is.
enum ClassDiagramMemberBytes {
    static func member(from bytes: UnsafeBufferPointer<UInt8>) -> (member: ClassDiagramMember, isMethod: Bool) {
        var shown: [UInt8] = []
        shown.reserveCapacity(bytes.count + 8)
        if let classifier = appendMethod(bytes, to: &shown) { return (ClassDiagramMember(text: displayed(shown), classifier: classifier), true) }
        shown.removeAll(keepingCapacity: true)
        guard let first = bytes.first, let last = bytes.last else { return (ClassDiagramMember(text: ""), false) }
        let classifier = classifierMarked(by: last) ?? .plain
        let start = isVisibility(first) ? 1 : 0
        if start == 1 { shown.append(first) }
        let end = max(start, classifier == .plain ? bytes.count : bytes.count - 1)
        appendAngleBracketed(normalizedName(bytes, start..<end), to: &shown)
        return (ClassDiagramMember(text: displayed(shown), classifier: classifier), false)
    }

    /// Writes a method's shown text and returns its classifier, or returns nil when the text is no method.
    private static func appendMethod(_ bytes: UnsafeBufferPointer<UInt8>, to shown: inout [UInt8]) -> ClassDiagramMemberClassifier? {
        guard let close = bytes.lastIndex(of: closingParenthesis), close > 0,
              let open = UnsafeBufferPointer(rebasing: bytes[..<close]).lastIndex(of: openingParenthesis), open > 0 else { return nil }
        let hasVisibility = isVisibility(bytes[0]) && open > 1
        if hasVisibility { shown.append(bytes[0]) }
        let name = normalizedName(bytes, (hasVisibility ? 1 : 0)..<open)
        let parameters = trimmed(bytes, (open + 1)..<close)
        var rest = close + 1
        var classifier = ClassDiagramMemberClassifier.plain
        if rest < bytes.count {
            let next = bytes[rest]
            if let marked = classifierMarked(by: next) { classifier = marked }
            if classifier != .plain || MermaidByte.isWhitespace(next) { rest += 1 }
        }
        var returnType = trimmed(bytes, rest..<bytes.count)
        if classifier == .plain, !returnType.isEmpty, let marked = classifierMarked(by: bytes[returnType.upperBound - 1]) {
            classifier = marked
            returnType = returnType.lowerBound..<(returnType.upperBound - 1)
        }
        appendAngleBracketed(name, to: &shown)
        shown.append(openingParenthesis)
        appendAngleBracketed(Array(bytes[parameters]), to: &shown)
        shown.append(closingParenthesis)
        if !returnType.isEmpty {
            shown.append(contentsOf: [MermaidByte.space, MermaidByte.colon, MermaidByte.space])
            appendAngleBracketed(Array(bytes[returnType]), to: &shown)
        }
        return classifier
    }

    /// `ClassDiagramMemberSyntax.angleBracketed`: pairs of tildes written as angle brackets, in each part between
    /// commas, two parts with one tilde each joined across their comma.
    private static func appendAngleBracketed(_ text: [UInt8], to shown: inout [UInt8]) {
        guard text.contains(MermaidByte.tilde) else { return shown.append(contentsOf: text) }
        var parts: [Range<Int>] = []
        var partStart = 0
        for index in text.indices where text[index] == MermaidByte.comma {
            parts.append(partStart..<index)
            parts.append(index..<(index + 1))
            partStart = index + 1
        }
        parts.append(partStart..<text.count)
        func isComma(_ part: Range<Int>) -> Bool { part.count == 1 && text[part.lowerBound] == MermaidByte.comma }
        func tildeCount(_ part: Range<Int>) -> Int { text[part].reduce(0) { count, byte in byte == MermaidByte.tilde ? count + 1 : count } }
        var lastShownStart = shown.count
        var index = 0
        while index < parts.count {
            var part = Array(text[parts[index]])
            if isComma(parts[index]), index > 0, index + 1 < parts.count, tildeCount(parts[index - 1]) == 1, tildeCount(parts[index + 1]) == 1 {
                part = Array(text[parts[index - 1]]) + [MermaidByte.comma] + Array(text[parts[index + 1]])
                index += 1
                shown.removeSubrange(lastShownStart...)
            }
            lastShownStart = shown.count
            appendPairingTildes(part, to: &shown)
            index += 1
        }
    }

    /// `ClassDiagramMemberSyntax.pairingTildes`: the outermost tildes paired inwards as `<` and `>`, a leading one left
    /// when their count is odd.
    private static func appendPairingTildes(_ text: [UInt8], to shown: inout [UInt8]) {
        let start = shown.count
        shown.append(contentsOf: text)
        let count = text.reduce(0) { count, byte in byte == MermaidByte.tilde ? count + 1 : count }
        guard count > 1 else { return }
        let skipsLeading = !count.isMultiple(of: 2) && text.first == MermaidByte.tilde
        let positions = text.indices.dropFirst(skipsLeading ? 1 : 0).filter { index in text[index] == MermaidByte.tilde }
        var low = 0
        var high = positions.count - 1
        while low < high {
            shown[start + positions[low]] = MermaidByte.lessThan
            shown[start + positions[high]] = MermaidByte.greaterThan
            low += 1
            high -= 1
        }
    }

    /// The name of `range`, trimmed, with one space before it when it started with one.
    private static func normalizedName(_ bytes: UnsafeBufferPointer<UInt8>, _ range: Range<Int>) -> [UInt8] {
        let name = Array(bytes[trimmed(bytes, range)])
        return range.lowerBound < range.upperBound && bytes[range.lowerBound] == MermaidByte.space ? [MermaidByte.space] + name : name
    }

    /// `range` without spaces, tabs and line breaks at its ends (`ClassDiagramMemberSyntax.trimmed`).
    private static func trimmed(_ bytes: UnsafeBufferPointer<UInt8>, _ range: Range<Int>) -> Range<Int> {
        var start = range.lowerBound
        var end = range.upperBound
        while start < end, MermaidByte.isWhitespace(bytes[start]) { start += 1 }
        while end > start, MermaidByte.isWhitespace(bytes[end - 1]) { end -= 1 }
        return start..<end
    }

    /// `ClassDiagramMemberSyntax.displayed`: trimmed, entity codes read, trimmed again.
    private static func displayed(_ shown: [UInt8]) -> String {
        shown.withUnsafeBufferPointer { shown in
            let kept = trimmed(shown, 0..<shown.count)
            let text = String(decoding: UnsafeBufferPointer(rebasing: shown[kept]), as: UTF8.self)
            guard shown[kept].contains(semicolon) else { return text }
            return ClassDiagramMemberSyntax.trimmed(DiagramLabelDecoder.decodingEntities(text))
        }
    }

    private static func isVisibility(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: "+") || byte == UInt8(ascii: "-") || byte == UInt8(ascii: "#") || byte == MermaidByte.tilde
    }

    private static func classifierMarked(by byte: UInt8) -> ClassDiagramMemberClassifier? {
        switch byte {
        case UInt8(ascii: "$"): .static
        case UInt8(ascii: "*"): .abstract
        default: nil
        }
    }

    private static let openingParenthesis = UInt8(ascii: "(")
    private static let closingParenthesis = UInt8(ascii: ")")
    private static let semicolon = UInt8(ascii: ";")
}
