/**
 * File: PlaneMapText.swift
 * ------------------------
 * Layer: Core
 * Description: The string operations of JavaScript the readers of Venn diagrams, Cynefin frameworks and Wardley maps
 *              repeat: `trim`, the order of `sort`, and the replacement of runs of blanks.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// JavaScript's string operations as Pele's readers of the diagrams drawn on a fixed plane use them.
enum PlaneMapText {
    /// `text` without the white space at its ends, as JavaScript's `trim` leaves it.
    static func trimmed(_ text: String) -> String {
        let bytes = Array(text.utf8)
        return String(decoding: JavaScriptWhitespace.trimmed(bytes[...]), as: UTF8.self)
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
