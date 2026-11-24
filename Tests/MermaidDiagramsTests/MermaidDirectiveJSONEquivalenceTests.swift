/**
 * File: MermaidDirectiveJSONEquivalenceTests.swift
 * ------------------------------------------------
 * Layer: Tests
 * Description: A directive's JSON read on its bytes is what JSONDecoder made of it in 0.7.0, number bits included, on
 *              every directive of every corpus, random JSON texts and mutated ones; and every type's options, read with
 *              the directives once per reading, are 0.7.0's on every corpus input and on mutated directives.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class MermaidDirectiveJSONEquivalenceTests: XCTestCase {
    /// Every section a type asks options for, and some no type does.
    static let sections = ["class", "cynefin", "sankey", "xyChart", "treeView", "gitGraph", "wardley-beta", "agentflow", "gantt", "architecture",
                           "kanban", "quadrantChart", "pie", "radar", "railroad", "packet", "block", "usecase", "treemap", "themeVariables",
                           "timeline", "flowchart", "theme", "nothing"]

    /// Every input of every corpus and spec, and the corpora of configured diagrams.
    static func everySource() throws -> [String] {
        try OutputDigest.corpora().flatMap(\.sources) + PeleResults.compatInputs().sorted { $0.key < $1.key }.flatMap(\.value)
            + PeleResults.flowchartSpecTexts().map(\.source) + PeleResults.preprocessing().preprocessing.map(\.source)
            + PeleResults.sources(ofCorpus: "configured-docs") + PeleResults.sources(ofCorpus: "directive-docs")
    }

    /// How the reading of a directive's content differs from JSONDecoder's, or nil.
    private func difference(_ content: String) -> String? {
        let expected = ReferenceMermaidConfigurationOptions.directiveObject(content)
        let read = Array(content.utf8).withUnsafeBufferPointer { buffer in MermaidDirectiveConfiguration.object(in: buffer) }
        switch (expected, read) {
        case (nil, nil): return nil
        case (let expected?, let read?): return DirectiveValueComparison.isIdentical(.object(expected), .object(read)) ? nil : "read \(read), expected \(expected)"
        case (nil, let read?): return "read \(read), expected none"
        case (let expected?, nil): return "none, expected \(expected)"
        }
    }

    private func differences(_ contents: [String]) -> [String] {
        var found: [String] = []
        for content in contents {
            guard let difference = difference(content) else { continue }
            found.append("\(difference) in \(content.debugDescription)")
            if found.count == 5 { break }
        }
        return found
    }

    /// Whether the bytes reader reads the content itself, rather than leaving it to JSONDecoder.
    private func isReadOnBytes(_ content: String) -> Bool {
        let trimmed = Array(content.utf8.drop { byte in byte == 0x20 || (0x09...0x0D).contains(byte) }.reversed().drop { byte in
            byte == 0x20 || (0x09...0x0D).contains(byte)
        }.reversed())
        return trimmed.withUnsafeBufferPointer { buffer in MermaidConfigurationJSONReader.object(in: buffer) } != nil
    }

    /// The contents of every directive in the text, after its apostrophes are made quotation marks, as they are read.
    static func directiveContents(of source: String) -> [String] {
        let text = Array(source.utf8).map { byte in byte == UInt8(ascii: "'") ? UInt8(ascii: "\"") : byte }
        var contents: [String] = []
        var position = 0
        while let match = MermaidDirectiveConfiguration.nextDirective(in: text, from: position) {
            position = max(match.end, match.start + 1)
            if let content = match.content { contents.append(String(decoding: text[content], as: UTF8.self)) }
        }
        return contents
    }

    func testEveryCorpusDirectiveIsReadAsJSONDecoderReadsIt() throws {
        let contents = try Self.everySource().flatMap(Self.directiveContents)
        XCTAssertGreaterThanOrEqual(contents.count, 84)
        XCTAssertEqual(differences(contents), [])
        XCTAssertGreaterThan(contents.filter(isReadOnBytes).count, contents.count / 2)
    }

    func testRandomJSONTextsAreReadAsJSONDecoderReadsThem() {
        var generator = RandomJSONTexts(seed: 0x5EED_0F15)
        let contents = (0..<12_000).map { _ in generator.objectText() }
        XCTAssertEqual(differences(contents), [])
        let readOnBytes = contents.filter(isReadOnBytes).count
        XCTAssertGreaterThan(readOnBytes, 2_000, "too few texts read on bytes to compare")
        XCTAssertLessThan(readOnBytes, 11_000, "too few texts left to JSONDecoder to compare")
    }

    func testMutatedJSONTextsAreReadAsJSONDecoderReadsThem() throws {
        var generator = RandomJSONTexts(seed: 0xC0FF_EE11)
        let corpus = try Self.everySource().flatMap(Self.directiveContents)
        let contents = (0..<12_000).map { index in generator.mutated(index.isMultiple(of: 2) ? corpus[index % corpus.count] : generator.objectText()) }
        XCTAssertEqual(differences(contents), [])
    }

    /// Numbers of every length and form JSON allows and some it does not, each alone and in an object.
    func testNumbersKeepEveryBitJSONDecoderGives() {
        var generator = RandomJSONTexts(seed: 0x0123_4567)
        var contents: [String] = []
        for _ in 0..<6_000 { contents.append("{\"n\": \(generator.number())}") }
        for written in ["0", "-0", "0.0", "-0.0", "1", "01", "-01", "1.", ".5", "-", "+1", "1e3", "1E-2", "2.5e+10", "1e400", "1e-400",
                        "9007199254740993", "123456789012345678901234567890", "1234567890123456789012345678901234567890", "0.1", "0.30000000000000004",
                        "4.35", "1.7976931348623157", "-12.5000000000000000000001"] {
            contents.append("{\"n\": \(written)}")
        }
        XCTAssertEqual(differences(contents), [])
    }

    func testHostileDirectivesAreReadAsBeforeAndBounded() {
        let deep = String(repeating: "{\"a\":", count: 40) + "1" + String(repeating: "}", count: 40)
        let deepArrays = "{\"a\":" + String(repeating: "[", count: 40) + String(repeating: "]", count: 40) + "}"
        let wide = "{" + (0..<5_000).map { index in "\"k\(index)\": \(index)" }.joined(separator: ",") + "}"
        let duplicated = "{\"a\": 1, \"a\": 2}"
        let longString = "{\"a\": \"" + String(repeating: "x", count: 40_000) + "\"}"
        let unclosed = "{\"a\": [1, 2, {\"b\": \"c\""
        XCTAssertEqual(differences([deep, deepArrays, wide, duplicated, longString, unclosed, "{", "}", "", " ", "{}", "[]", "null", "\"a\""]), [])
        let start = ContinuousClock.now
        for _ in 0..<20 { _ = difference(wide) }
        XCTAssertLessThan(ContinuousClock.now - start, .seconds(10))
    }

    /// Every type's options, its directives read once for the reading, are 0.7.0's for every section.
    func testEveryCorpusInputsOptionsAreAsBefore() throws {
        XCTAssertEqual(try optionDifferences(Self.everySource()), [])
    }

    func testMutatedConfiguredInputsOptionsAreAsBefore() throws {
        var generator = RandomJSONTexts(seed: 0xD1_2EC7)
        let configured = try PeleResults.sources(ofCorpus: "configured-docs") + PeleResults.sources(ofCorpus: "directive-docs")
        let sources = (0..<3_000).map { index in generator.mutated(configured[index % configured.count]) }
        XCTAssertEqual(optionDifferences(sources), [])
    }

    private func optionDifferences(_ sources: [String]) -> [String] {
        var found: [String] = []
        for source in sources {
            guard let frontEnd = try? MermaidFrontEnd.read(source), let (_, reference) = try? ReferenceMermaidReader.preprocessed(source) else { continue }
            let cursor = MermaidTextCursor(frontEnd)
            for section in Self.sections {
                let expected = ReferenceMermaidConfigurationOptions(section: section, in: reference.sourceBytes)
                let read = ReferenceMermaidConfigurationOptions(MermaidConfigurationOptions(section: section, in: cursor))
                // The cursor's options for a second section are read from the directives kept from the first.
                let again = ReferenceMermaidConfigurationOptions(MermaidConfigurationOptions(section: section, in: cursor))
                if read != expected || again != expected { found.append("\(section): \(read), expected \(expected) in \(String(source.prefix(160)).debugDescription)") }
            }
            if found.count >= 5 { break }
        }
        return found
    }
}

/// Compares a directive's values exactly: numbers by their bits.
enum DirectiveValueComparison {
    static func isIdentical(_ first: DirectiveValue, _ second: DirectiveValue) -> Bool {
        switch (first, second) {
        case (.null, .null): true
        case (.boolean(let a), .boolean(let b)): a == b
        case (.number(let a), .number(let b)): a.bitPattern == b.bitPattern
        case (.text(let a), .text(let b)): Array(a.utf8) == Array(b.utf8)
        case (.array(let a), .array(let b)): a.count == b.count && zip(a, b).allSatisfy { pair in isIdentical(pair.0, pair.1) }
        case (.object(let a), .object(let b)):
            a.count == b.count && a.allSatisfy { key, value in b[key].map { other in isIdentical(value, other) } ?? false }
        default: false
        }
    }
}

/// Seeded JSON texts, valid and not, of the shapes directives are written in, and mutations of texts.
struct RandomJSONTexts {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    /// SplitMix64.
    private mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }

    mutating func below(_ bound: Int) -> Int {
        bound <= 1 ? 0 : Int(next() % UInt64(bound))
    }

    private mutating func pick(_ choices: [String]) -> String {
        choices[below(choices.count)]
    }

    private mutating func space() -> String {
        below(3) == 0 ? pick(["", " ", "\n", "\t", "\r\n", "  ", "\u{0B}", "\u{A0}", "\u{2028}", "\u{0C}"]) : pick(["", " "])
    }

    mutating func number() -> String {
        if below(4) == 0 {
            return pick(["0", "-0", "1.5", "01", "1.", ".5", "1e3", "-2.25", "1E+2", "00", "-", "0x10", "Infinity", "NaN", "1_000"])
        }
        let sign = below(3) == 0 ? "-" : ""
        let whole = below(4) == 0 ? "0" : String(below(9) + 1) + (0..<below(20)).map { _ in String(below(10)) }.joined()
        let fraction = below(2) == 0 ? "" : "." + (0..<(below(20) + 1)).map { _ in String(below(10)) }.joined()
        return sign + whole + fraction
    }

    private mutating func string() -> String {
        "\"" + pick(["", "a", "base", "#ff0000", "é", "中文", "a b", "a\\\"b", "\\n", "\\u0041", "tab\there", "x\u{1}y", "dark", "'q'", "}%", "--x"]) + "\""
    }

    private mutating func key() -> String {
        pick(["\"theme\"", "\"themeVariables\"", "\"pie\"", "\"gitGraph\"", "\"a\"", "\"a\"", "\"\"", "\"é\"", "\"__proto__\"", "\"x.y\"",
              "\"showBranches\"", "\"pie1\"", "\"cScale0\"", "\"k\\u0041\"", "theme", "'q'"])
    }

    private mutating func value(depth: Int) -> String {
        switch below(depth > 3 ? 4 : 7) {
        case 0: return number()
        case 1: return string()
        case 2: return pick(["true", "false", "null", "True", "nul", "truex"])
        case 3: return string()
        case 4: return object(depth: depth + 1)
        case 5: return "[" + (0..<below(4)).map { _ in space() + value(depth: depth + 1) + space() }.joined(separator: pick([",", ",", ",", ",,", ""])) + "]"
        default: return object(depth: depth + 1)
        }
    }

    private mutating func object(depth: Int) -> String {
        let entries = (0..<below(5)).map { _ in space() + key() + space() + pick([":", ":", ":", ""]) + space() + value(depth: depth) + space() }
        return "{" + entries.joined(separator: pick([",", ",", ",", ",", ", ", ""])) + (below(20) == 0 ? "," : "") + "}"
    }

    /// An object's text, with white space around it, sometimes something after it.
    mutating func objectText() -> String {
        space() + object(depth: 0) + space() + (below(30) == 0 ? pick(["x", "}", "{}", "1"]) : "")
    }

    /// `text` changed one to three times: a byte removed, or a piece inserted, at a random place.
    mutating func mutated(_ text: String) -> String {
        var scalars = Array(text.unicodeScalars)
        let pieces = ["{", "}", "[", "]", "\"", "'", ":", ",", "\\", " ", "\n", "\t", "\r", "0", "-", ".", "e", "1", "é", "\u{A0}", "true", "null",
                      "%%{init: {'theme': 'dark'}}%%", "%%{init: ", "}%%", "%%", "---", "---\n", "config:", "  ", "#", "'#f00'"]
        for _ in 0..<(below(3) + 1) {
            let place = below(scalars.count + 1)
            if below(3) == 0, !scalars.isEmpty {
                scalars.remove(at: min(place, scalars.count - 1))
            } else {
                scalars.insert(contentsOf: pick(pieces).unicodeScalars, at: place)
            }
        }
        var mutated = String.UnicodeScalarView()
        mutated.append(contentsOf: scalars)
        return String(mutated)
    }
}
