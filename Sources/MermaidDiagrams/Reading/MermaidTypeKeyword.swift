/**
 * File: MermaidTypeKeyword.swift
 * ------------------------------
 * Layer: Core
 * Description: The diagram types the reader tells from its keyword's bytes before making a String of it: the
 *              flowchart's keywords and the swimlane's; every other type is named by its keyword's text.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

/// The type a keyword names, told from its bytes for the flowchart (`flowchart`, `graph`, `flowchart-elk`) and the
/// swimlane (`swimlane-beta`), which are read from the text itself; `other` for the rest, read from a cursor.
enum MermaidTypeKeyword {
    case flowchart
    case swimlane
    case other

    init(_ keyword: UnsafeBufferPointer<UInt8>) {
        switch keyword.count {
        case 5: self = Self.spells(keyword, "graph") ? .flowchart : .other
        case 9: self = Self.spells(keyword, "flowchart") ? .flowchart : .other
        case 13: self = Self.spells(keyword, "flowchart-elk") ? .flowchart : Self.spells(keyword, "swimlane-beta") ? .swimlane : .other
        default: self = .other
        }
    }

    private static func spells(_ keyword: UnsafeBufferPointer<UInt8>, _ word: StaticString) -> Bool {
        let letters = word.utf8Start
        for index in 0..<keyword.count where keyword[index] != letters[index] { return false }
        return true
    }
}
