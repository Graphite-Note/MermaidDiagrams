/**
 * File: PlaneMapTerminalValues.swift
 * ----------------------------------
 * Layer: Core
 * Description: The values of the terminals Mermaid's Langium grammars share, as Pele's common/tokens.ts takes them: a
 *              title's and an accessibility statement's text, and a string's without its quotation marks and escapes.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

/// The values of shared terminals, each from the token's text as matched.
enum PlaneMapTerminalValues {
    /// A title's text: after `title`, trimmed, runs of spaces and tabs made one space.
    static func title(_ token: String) -> String {
        PlaneMapText.singleSpaced(String(token.dropFirst("title".count)))
    }

    /// An accessibility title's text: after its colon, trimmed, runs of blanks made one.
    static func accessibilityTitle(_ token: String) -> String {
        guard let colon = token.firstIndex(of: ":") else { return "" }
        return PlaneMapText.singleSpaced(String(token[token.index(after: colon)...]))
    }

    /// An accessibility description's text: after its colon as a title's, or between its braces each line trimmed, the
    /// empty ones left out, runs of blanks made one space, joined by line breaks.
    static func accessibilityDescription(_ token: String) -> String {
        let afterKeyword = token.dropFirst("accDescr".count)
        let start = afterKeyword.drop { character in character == " " || character == "\t" }
        if start.first == ":" { return PlaneMapText.singleSpaced(String(start.dropFirst())) }
        guard let opening = token.firstIndex(of: "{"), let closing = token.lastIndex(of: "}"), opening < closing else { return "" }
        let lines = token[token.index(after: opening)..<closing].split(whereSeparator: { character in character == "\n" || character == "\r" || character == "\r\n" })
        return lines.map { line in PlaneMapText.singleSpaced(String(line)) }.filter { line in !line.isEmpty }.joined(separator: "\n")
    }

    /// A string's text without its quotation marks, each backslash replaced by the character it escapes (`\n` a line
    /// break, `\t` a tab, `\0` a null character; any other character itself).
    static func string(_ token: String) -> String {
        let inside = token.dropFirst().dropLast()
        // Without a backslash's byte no character is one, and the text is kept as it is.
        guard inside.utf8.contains(UInt8(ascii: "\\")) else { return String(inside) }
        var text = ""
        var isEscaping = false
        for character in inside {
            if isEscaping {
                text.append(escapes[character] ?? character)
                isEscaping = false
            } else if character == "\\" {
                isEscaping = true
            } else {
                text.append(character)
            }
        }
        return text
    }

    private static let escapes: [Character: Character] = ["b": "\u{08}", "f": "\u{0C}", "n": "\n", "r": "\r", "t": "\t", "v": "\u{0B}", "0": "\u{00}"]
}
