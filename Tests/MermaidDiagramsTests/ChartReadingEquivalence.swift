/**
 * File: ChartReadingEquivalence.swift
 * -----------------------------------
 * Layer: Tests
 * Description: What the chart readers' equivalence tests share: a reader and its frozen 0.7.0 reference run on the same
 *              text, from the cursor after its keyword, give the same model or the same error; the corpora's sources of
 *              a type; texts mutated from them byte by byte and line by line.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

/// A reader run from the cursor after a diagram's keyword, with that keyword.
typealias ChartReading<Model> = (MermaidTextCursor, String) throws(MermaidDiagramReadError) -> Model

enum ChartReadingEquivalence {
    /// Whether `source` names a diagram of `keywords`, and if so, that `read` and `reference` agree on it: the same model,
    /// or the same error. Nil when the source is of another type or its front end is refused.
    static func agree<Model: Equatable>(_ source: String, keywords: Set<String>, read: ChartReading<Model>,
                                        reference: ChartReading<Model>) -> Bool? {
        guard let frontEnd = try? MermaidFrontEnd.read(source), keywords.contains(frontEnd.keywordText) else { return nil }
        let keyword = frontEnd.keywordText
        let readResult = Result { () throws(MermaidDiagramReadError) -> Model in try read(MermaidTextCursor(frontEnd), keyword) }
        let referenceResult = Result { () throws(MermaidDiagramReadError) -> Model in try reference(MermaidTextCursor(frontEnd), keyword) }
        switch (readResult, referenceResult) {
        case (.success(let model), .success(let expected)): return model == expected
        case (.failure(let error), .failure(let expected)): return error == expected
        default: return false
        }
    }

    /// The sources of every corpus that the front end reads as one of `keywords`.
    static func corpusSources(keywords: Set<String>) throws -> [String] {
        try OutputDigest.corpora().flatMap(\.sources).filter { source in
            (try? MermaidFrontEnd.read(source)).map { frontEnd in keywords.contains(frontEnd.keywordText) } ?? false
        }
    }
}

/// Texts made from a diagram's text by a seeded generator: lines dropped, repeated, swapped or cut short, and bytes
/// changed, put in or taken out, among them the characters a reader decides on.
struct ChartTextMutations {
    private var state: UInt64
    /// The characters the readers of these types decide on, put in at random places.
    private static let significant: [Character] = ["\"", "`", "[", "]", "(", ")", "{", "}", "<", ">", ":", ",", ";", "-", "=", ".", "%", "\n", " ",
                                                   "\t", "\r", "&", "#", "x", "o", "0", "9", "é", "\u{3000}"]

    init(seed: UInt64) {
        state = seed
    }

    private mutating func next(below bound: Int) -> Int {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Int((state >> 33) % UInt64(max(bound, 1)))
    }

    /// `source` with one to four of its lines dropped, repeated, swapped, cut short or added again at the end.
    mutating func mutated(_ source: String) -> String {
        var lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.count > 1 else { return source }
        for _ in 0...next(below: 3) {
            let index = 1 + next(below: lines.count - 1)
            switch next(below: 5) {
            case 0: lines.remove(at: index)
            case 1: lines.insert(lines[index], at: index)
            case 2: lines.swapAt(index, 1 + next(below: lines.count - 1))
            case 3: lines[index] = String(lines[index].prefix(next(below: lines[index].count + 1)))
            default: lines.append(contentsOf: lines[1...].prefix(1 + next(below: 6)))
            }
            if lines.count < 2 { break }
        }
        return lines.joined(separator: "\n")
    }

    /// `source` with one to three characters after its first line changed, put in or taken out.
    mutating func spliced(_ source: String) -> String {
        var characters = Array(source)
        let firstLineEnd = (characters.firstIndex(of: "\n") ?? characters.count - 1) + 1
        guard characters.count > firstLineEnd else { return source }
        for _ in 0...next(below: 2) {
            let index = firstLineEnd + next(below: characters.count - firstLineEnd)
            let character = Self.significant[next(below: Self.significant.count)]
            switch next(below: 3) {
            case 0: characters[index] = character
            case 1: characters.insert(character, at: index)
            default: characters.remove(at: index)
            }
            if characters.count <= firstLineEnd { break }
        }
        return String(characters)
    }
}
