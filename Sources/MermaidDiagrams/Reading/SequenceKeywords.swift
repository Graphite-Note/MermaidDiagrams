/**
 * File: SequenceKeywords.swift
 * ----------------------------
 * Layer: Core
 * Description: The words that start a sequence diagram's statements, found on a line's bytes in any case.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

extension SequenceParser {
    /// The words that start a statement, lowercased.
    enum Keyword: String, CaseIterable {
        case participant, actor, create, destroy, box, loop, rect, opt, alt, `else`, par, parOver = "par_over", and, critical, option, `break`, end
        case note, activate, deactivate, autonumber, title, accessibilityTitle = "acctitle", accessibilityDescription = "accdescr"
        case link, links, properties, details
    }
}

extension SequenceParser.Keyword {
    /// The keyword the letters and underscores from `start` to `end` spell in any case, compared byte by byte with the
    /// keywords of their length, as `Keyword(rawValue:)` of the word lowercased finds it.
    static func spelled(in bytes: [UInt8], from start: Int, to end: Int) -> Self? {
        let length = end - start
        guard length < keywordsByLength.count else { return nil }
        candidates: for (spelling, keyword) in keywordsByLength[length] {
            for offset in 0..<length where MermaidByte.lowercased(bytes[start + offset]) != spelling[offset] { continue candidates }
            return keyword
        }
        return nil
    }

    /// Every keyword's spelling, by its length.
    private static let keywordsByLength: [[(spelling: [UInt8], keyword: Self)]] = {
        let all = allCases
        var byLength = [[(spelling: [UInt8], keyword: Self)]](repeating: [], count: (all.map(\.rawValue.utf8.count).max() ?? 0) + 1)
        for keyword in all { byLength[keyword.rawValue.utf8.count].append((Array(keyword.rawValue.utf8), keyword)) }
        return byLength
    }()
}
