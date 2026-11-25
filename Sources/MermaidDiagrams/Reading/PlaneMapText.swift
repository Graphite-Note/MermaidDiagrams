/**
 * File: PlaneMapText.swift
 * ------------------------
 * Layer: Core
 * Description: The string operations of JavaScript the readers of Venn diagrams, Cynefin frameworks and Wardley maps
 *              repeat: `trim`, the order of `sort`, the replacement of runs of blanks, and a search for an ASCII text.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

/// JavaScript's string operations as Pele's readers of the diagrams drawn on a fixed plane use them.
enum PlaneMapText {
    /// `text` without the white space at its ends, as JavaScript's `trim` leaves it.
    static func trimmed(_ text: String) -> String {
        let bytes = Array(text.utf8)
        return String(decoding: JavaScriptWhitespace.trimmed(bytes[...]), as: UTF8.self)
    }

    /// Whether `text` holds `literal`, printable ASCII, as Foundation's `contains` finds it: on the bytes when `text` is
    /// ASCII, whose characters are then its bytes, else by Foundation, which compares characters.
    static func contains(_ text: String, _ literal: StaticString) -> Bool {
        let needle = UnsafeBufferPointer(start: literal.utf8Start, count: literal.utf8CodeUnitCount)
        guard text.utf8.allSatisfy({ byte in byte < 0x80 }) else { return text.contains(String(decoding: needle, as: UTF8.self)) }
        let bytes = text.utf8
        guard bytes.count >= needle.count else { return false }
        var start = bytes.startIndex
        while let end = bytes.index(start, offsetBy: needle.count, limitedBy: bytes.endIndex) {
            if bytes[start..<end].elementsEqual(needle) { return true }
            start = bytes.index(after: start)
        }
        return false
    }

    /// Whether `first` sorts before `second` in JavaScript's default order: by UTF-16 code units.
    static func isOrderedBeforeByCodeUnits(_ first: String, _ second: String) -> Bool {
        first.utf16.lexicographicallyPrecedes(second.utf16)
    }

    /// `text` trimmed, its runs of two or more spaces and tabs made one space, as Langium's title and accessibility
    /// statements are (`single` in Pele's `common/tokens.ts`).
    static func singleSpaced(_ text: String) -> String {
        var result = ""
        var blankRun = ""
        for character in trimmed(text) {
            if character == " " || character == "\t" {
                blankRun.append(character)
                continue
            }
            if !blankRun.isEmpty { result += blankRun.count >= 2 ? " " : blankRun }
            blankRun = ""
            result.append(character)
        }
        return result + (blankRun.count >= 2 ? " " : blankRun)
    }
}
