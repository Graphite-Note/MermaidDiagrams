/**
 * File: TreeViewEntryText.swift
 * -----------------------------
 * Layer: Core
 * Description: A tree view entry's name and annotations read on the bytes of their tokens, as the String reading of
 *              0.7.0 reads them: a quoted name without its quotation marks, a bare one without its trailing blanks, a
 *              folder's without its `/`, an annotation trimmed of Foundation's white space and its marker. Where a
 *              character past ASCII could make Swift's characters differ from the bytes, the field is read from its
 *              String as before.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import Foundation

/// The reading of an entry's fields on the token source's bytes.
enum TreeViewEntryText {
    /// The name of a quoted or bare name token `start..<end`, and whether it is a folder's.
    static func name(_ bytes: [UInt8], from start: Int, to end: Int, isQuoted: Bool) -> (TreeViewFieldText, isFolder: Bool) {
        var nameStart = start
        var nameEnd = end
        if isQuoted {
            // The quotation marks are characters of their own when the bytes beside them are ASCII: no mark past ASCII
            // joins the first, and no prepended character the last.
            guard end - start >= 2, end - start == 2 || (bytes[start + 1] < 0x80 && bytes[end - 2] < 0x80) else {
                return folder(of: String(String(decoding: bytes[start..<end], as: UTF8.self).dropFirst().dropLast()))
            }
            nameStart += 1
            nameEnd -= 1
        } else {
            while nameEnd > nameStart, MermaidByte.isSpace(bytes[nameEnd - 1]) { nameEnd -= 1 }
            // A blank after a character past ASCII may be part of that character: the String reading decides.
            if nameEnd < end, nameEnd > nameStart, bytes[nameEnd - 1] >= 0x80 {
                return folder(of: withoutTrailingBlanks(String(decoding: bytes[start..<end], as: UTF8.self)))
            }
        }
        guard nameEnd > nameStart, bytes[nameEnd - 1] == slash else {
            return (TreeViewFieldText(range: MermaidTextRange(start: nameStart, end: nameEnd)), false)
        }
        guard nameEnd - nameStart == 1 || bytes[nameEnd - 2] < 0x80 else {
            return folder(of: String(decoding: bytes[nameStart..<nameEnd], as: UTF8.self))
        }
        return (TreeViewFieldText(range: MermaidTextRange(start: nameStart, end: nameEnd - 1)), true)
    }

    /// A name read as a String, a folder's when its last character is `/`, which is then left out.
    private static func folder(of name: String) -> (TreeViewFieldText, isFolder: Bool) {
        let isFolder = name.hasSuffix("/")
        return (TreeViewFieldText(written: isFolder ? String(name.dropLast()) : name), isFolder)
    }

    /// The name without the spaces and tabs at its end, its characters compared as the reversed name's were.
    static func withoutTrailingBlanks(_ name: String) -> String {
        var end = name.endIndex
        while end > name.startIndex, case let before = name.index(before: end), name[before] == " " || name[before] == "\t" { end = before }
        return String(name[..<end])
    }

    /// An annotation token's value: the token trimmed of spaces and tabs, its `markerLength` bytes of marker
    /// (`:::`, `##`, `icon(`) and `closingLength` bytes at its end (`icon`'s `)`) taken off, and trimmed again when
    /// `trimsValue`, as Foundation trims. Read from its String when a byte past ASCII stands where trimming or taking
    /// off a character looks.
    static func annotation(_ bytes: [UInt8], from start: Int, to end: Int, markerLength: Int, closingLength: Int, trimsValue: Bool) -> TreeViewFieldText {
        var valueStart = start
        var valueEnd = end
        while valueStart < valueEnd, MermaidByte.isSpace(bytes[valueStart]) { valueStart += 1 }
        while valueEnd > valueStart, MermaidByte.isSpace(bytes[valueEnd - 1]) { valueEnd -= 1 }
        let isPlain = valueEnd - valueStart >= markerLength + closingLength && bytes[valueEnd - 1] < 0x80
            && (valueEnd - valueStart == markerLength + closingLength
                || (bytes[valueStart + markerLength] < 0x80 && bytes[valueEnd - 1 - closingLength] < 0x80))
        guard isPlain else {
            return TreeViewFieldText(written: writtenAnnotation(bytes, from: start, to: end, markerLength: markerLength, closingLength: closingLength,
                                                                trimsValue: trimsValue))
        }
        valueStart += markerLength
        valueEnd -= closingLength
        if trimsValue {
            while valueStart < valueEnd, MermaidByte.isSpace(bytes[valueStart]) { valueStart += 1 }
            while valueEnd > valueStart, MermaidByte.isSpace(bytes[valueEnd - 1]) { valueEnd -= 1 }
            if valueStart < valueEnd, bytes[valueStart] >= 0x80 || bytes[valueEnd - 1] >= 0x80 {
                return TreeViewFieldText(written: writtenAnnotation(bytes, from: start, to: end, markerLength: markerLength,
                                                                    closingLength: closingLength, trimsValue: trimsValue))
            }
        }
        return TreeViewFieldText(range: MermaidTextRange(start: valueStart, end: valueEnd))
    }

    /// The annotation read as 0.7.0 read it, from its token's String.
    private static func writtenAnnotation(_ bytes: [UInt8], from start: Int, to end: Int, markerLength: Int, closingLength: Int, trimsValue: Bool) -> String {
        let written = FoundationTextOnBytes.trimmed(String(decoding: bytes[start..<end], as: UTF8.self), includingLineBreaks: false)
        let value = String(written.dropFirst(markerLength).dropLast(closingLength))
        return trimsValue ? FoundationTextOnBytes.trimmed(value, includingLineBreaks: false) : value
    }

    /// Whether `highlight` is among the classes `text[range]`, split at white space as Swift's characters tell it.
    static func namesHighlight(_ text: [UInt8], _ range: MermaidTextRange) -> Bool {
        let classes = text[range.lowerBound..<range.upperBound]
        guard !classes.contains(where: { byte in byte >= 0x80 }) else {
            return String(decoding: classes, as: UTF8.self).split(whereSeparator: \.isWhitespace).contains("highlight")
        }
        var wordStart = classes.startIndex
        for index in classes.indices where isASCIIWhitespace(classes[index]) {
            if isHighlight(classes[wordStart..<index]) { return true }
            wordStart = index + 1
        }
        return isHighlight(classes[wordStart...])
    }

    private static func isHighlight(_ word: ArraySlice<UInt8>) -> Bool {
        word.elementsEqual(highlight)
    }

    /// White space among ASCII's characters as `Character.isWhitespace` tells it: tab to carriage return, and the space.
    private static func isASCIIWhitespace(_ byte: UInt8) -> Bool {
        byte == MermaidByte.space || (byte >= 0x09 && byte <= 0x0D)
    }

    private static let slash = UInt8(ascii: "/")
    private static let highlight = Array("highlight".utf8)
}
