/**
 * File: UseCaseColorSemicolons.swift
 * ----------------------------------
 * Layer: Core
 * Description: Drops the semicolon Mermaid's preprocessing drops after a color on a `style` or `classDef` line, as
 *              Pele's dropColorSemicolons does, before a use case diagram is read.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// Does what Mermaid's `text.replace(/keyword.*:\S*#.*;/g, …)` does, in one pass as Pele does: on a line where `style`
/// (and then, in a second pass, `classDef`) is followed by a colon, a `#` after it with no whitespace between, and
/// later a semicolon, the line's last semicolon goes, so that `style A fill:#f9f;` is read as `fill:#f9f`.
enum UseCaseColorSemicolons {
    static func dropping(in units: [UInt16]) -> [UInt16] {
        dropping("classDef", in: dropping("style", in: units))
    }

    private static func isLineBreak(_ unit: UInt16) -> Bool { unit == 0x0A || unit == 0x0D || unit == 0x2028 || unit == 0x2029 }

    private static func dropping(_ keyword: String, in units: [UInt16]) -> [UInt16] {
        let word = Array(keyword.utf16)
        var dropped: [Int] = []
        var from = firstIndex(of: word, in: units, from: 0)
        while let start = from {
            var lineEnd = start + word.count
            while lineEnd < units.count, !isLineBreak(units[lineEnd]) { lineEnd += 1 }
            if let hash = colorHash(in: units, from: start + word.count, to: lineEnd),
               let semicolon = units[(hash + 1)..<max(hash + 1, lineEnd)].lastIndex(of: UInt16(ascii: ";")) {
                dropped.append(semicolon)
            }
            from = lineEnd >= units.count ? nil : firstIndex(of: word, in: units, from: lineEnd + 1)
        }
        guard !dropped.isEmpty else { return units }
        var result: [UInt16] = []
        result.reserveCapacity(units.count - dropped.count)
        var previous = 0
        for index in dropped {
            result.append(contentsOf: units[previous..<index])
            previous = index + 1
        }
        result.append(contentsOf: units[previous...])
        return result
    }

    /// The first `#` after a colon with no whitespace between them, on the line from `start` to `end`.
    private static func colorHash(in units: [UInt16], from start: Int, to end: Int) -> Int? {
        var isAfterColon = false
        for index in start..<max(start, end) {
            let unit = units[index]
            if unit == UInt16(ascii: ":") {
                isAfterColon = true
            } else if unit == UInt16(ascii: "#") {
                if isAfterColon { return index }
            } else if UseCaseCharacters.isJavaScriptWhitespace(unit) {
                isAfterColon = false
            }
        }
        return nil
    }

    private static func firstIndex(of word: [UInt16], in units: [UInt16], from start: Int) -> Int? {
        guard !word.isEmpty, units.count >= word.count, start <= units.count - word.count else { return nil }
        for index in start...(units.count - word.count) where units[index] == word[0] && units[index..<(index + word.count)].elementsEqual(word) {
            return index
        }
        return nil
    }
}
