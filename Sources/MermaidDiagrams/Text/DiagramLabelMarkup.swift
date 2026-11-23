/**
 * File: DiagramLabelMarkup.swift
 * ------------------------------
 * Layer: Core
 * Description: The markup Pele's label layout takes out of a line: HTML tags it knows, and a Markdown string's
 *              emphasis markers, by the rules of text/label.ts `inline`.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

/// What Pele's `inline` (text/label.ts) removes from a line of a label: a tag (`RE_TAG`, `<name …>` or `</name>`) whose
/// name is an HTML element's, its text kept, while anything else shaped like a tag (`List<T>`, `<brand>`) is text; and
/// in a Markdown string the `*`, `**`, `_` and `__` that open or close emphasis.
enum DiagramLabelMarkup {
    /// The line without the HTML tags Pele drops.
    static func withoutTags(_ line: String) -> String {
        guard line.contains("<") else { return line }
        let characters = Array(line.unicodeScalars)
        var result = String.UnicodeScalarView()
        var index = 0
        while index < characters.count {
            if characters[index] == "<", let end = endOfHypertextTag(in: characters, at: index) {
                index = end
                continue
            }
            result.append(characters[index])
            index += 1
        }
        return String(result)
    }

    /// Where the tag `RE_TAG` (`/<\/?([a-zA-Z][\w-]*)(?:\s[^<>]*)?\/?>/`) matches at `start` ends, when its name is an
    /// HTML element's; nil otherwise.
    private static func endOfHypertextTag(in characters: [Unicode.Scalar], at start: Int) -> Int? {
        var index = start + 1
        if index < characters.count, characters[index] == "/" { index += 1 }
        guard index < characters.count, characters[index].isASCII, characters[index].properties.isAlphabetic else { return nil }
        let nameStart = index
        while index < characters.count, isNameCharacter(characters[index]) { index += 1 }
        let name = String(String.UnicodeScalarView(characters[nameStart..<index])).lowercased()
        guard hypertextElements.contains(name), index < characters.count else { return nil }
        if characters[index].properties.isWhitespace {
            while index < characters.count, characters[index] != "<", characters[index] != ">" { index += 1 }
        } else if characters[index] == "/" {
            index += 1
        }
        guard index < characters.count, characters[index] == ">" else { return nil }
        return index + 1
    }

    /// `[\w-]`: an ASCII letter, a digit, an underscore or a hyphen.
    private static func isNameCharacter(_ character: Unicode.Scalar) -> Bool {
        character.isASCII && (character.properties.isAlphabetic || ("0"..."9").contains(character) || character == "_" || character == "-")
    }

    /// The line without its emphasis markers, as `inline` reads a Markdown string: a `*` or `_` (doubled for bold)
    /// opens emphasis where text follows it and its like comes later in the line, closes open emphasis of its kind
    /// where text precedes it, and stays as text otherwise; a `_` between two word characters (`snake_case`) is text.
    static func withoutEmphasisMarkers(_ line: String) -> String {
        let characters = Array(line)
        var isBoldOpen = false
        var isItalicOpen = false
        var result = ""
        var index = 0
        while index < characters.count {
            let character = characters[index]
            guard character == "*" || character == "_" else {
                result.append(character)
                index += 1
                continue
            }
            let isDouble = index + 1 < characters.count && characters[index + 1] == character
            let length = isDouble ? 2 : 1
            let opens = !(isDouble ? isBoldOpen : isItalicOpen)
            let previous = index > 0 ? characters[index - 1] : " "
            let next = index + length < characters.count ? characters[index + length] : " "
            let canOpen = opens && !next.isWhitespace && containsMarker(character, length: length, in: characters, from: index + length)
            let canClose = !opens && !previous.isWhitespace
            let isBetweenWords = character == "_" && isWordCharacter(previous) && isWordCharacter(next)
            if (canOpen || canClose) && !isBetweenWords {
                if isDouble { isBoldOpen = canOpen } else { isItalicOpen = canOpen }
                index += length
                continue
            }
            result.append(character)
            index += 1
        }
        return result
    }

    /// Whether `length` of `marker` stand in a row anywhere from `start`.
    private static func containsMarker(_ marker: Character, length: Int, in characters: [Character], from start: Int) -> Bool {
        var run = 0
        for character in characters[min(start, characters.count)...] {
            run = character == marker ? run + 1 : 0
            if run >= length { return true }
        }
        return false
    }

    /// `\w`: an ASCII letter, a digit or an underscore.
    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber || character == "_")
    }

    /// The HTML elements whose tags `inline` drops (text/label.ts `HTML_TAGS`).
    private static let hypertextElements: Set<String> = Set("""
        a abbr address article aside audio b bdi bdo big blockquote body br button caption center cite code col \
        colgroup data dd del details dfn dialog div dl dt em embed fieldset figcaption figure font footer form h1 h2 \
        h3 h4 h5 h6 head header hr html i iframe img input ins kbd label legend li link main map mark meta meter nav \
        noscript object ol optgroup option output p picture pre progress q rp rt ruby s samp script section select \
        small source span strike strong style sub summary sup table tbody td template textarea tfoot th thead time \
        title tr track tt u ul var video wbr
        """.split(separator: " ").map(String.init))
}
