/**
 * File: ClassDiagramKeyword.swift
 * -------------------------------
 * Layer: Core
 * Description: The words that start a class diagram's statements, told from a word's bytes as written, without a
 *              String made to look it up.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

/// The words that start a class diagram's statements, which Mermaid matches as written, case included.
enum ClassDiagramKeyword: Equatable {
    case classStatement, namespace, note, direction, accessibilityTitle, accessibilityDescription
    /// `style`, `classDef`, `cssClass`, `click`, `link` and `callback`, which are counted and left.
    case unapplied

    /// The keyword the bytes of `word` spell, or nil.
    init?(_ word: MermaidTextRange, in buffer: UnsafeBufferPointer<UInt8>) {
        func spells(_ literal: StaticString) -> Bool {
            let literalBytes = literal.utf8Start
            for offset in 0..<word.count where buffer[word.lowerBound + offset] != literalBytes[offset] { return false }
            return true
        }
        switch word.count {
        case 4:
            if spells("note") { self = .note } else if spells("link") { self = .unapplied } else { return nil }
        case 5:
            if spells("class") { self = .classStatement } else if spells("style") || spells("click") { self = .unapplied } else { return nil }
        case 8:
            if spells("accTitle") {
                self = .accessibilityTitle
            } else if spells("accDescr") {
                self = .accessibilityDescription
            } else if spells("classDef") || spells("cssClass") || spells("callback") {
                self = .unapplied
            } else {
                return nil
            }
        case 9:
            if spells("namespace") { self = .namespace } else if spells("direction") { self = .direction } else { return nil }
        default: return nil
        }
    }
}
