/**
 * File: ReferencePlaneMapText.swift
 * ---------------------------------
 * Layer: Tests
 * Description: 0.7.0's PlaneMapText, frozen as main de81532 had it, which the readers of Venn diagrams, Cynefin frameworks and Wardley maps is compared with.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

@testable import MermaidDiagrams

/// JavaScript's string operations as Pele's readers of the diagrams drawn on a fixed plane use them.
enum ReferencePlaneMapText {
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
