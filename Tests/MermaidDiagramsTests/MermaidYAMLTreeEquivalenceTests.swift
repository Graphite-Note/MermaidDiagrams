/**
 * File: MermaidYAMLTreeEquivalenceTests.swift
 * -------------------------------------------
 * Layer: Tests
 * Description: The YAML tree a front matter is read into holds what Pele's YAML reader (SequenceAttributesBlockSyntax,
 *              the reference) reads, number bits included, or is refused where it is refused: on every front matter of
 *              every corpus, Pele's own YAML texts, random and mutated YAML and hostile texts; and the title and the
 *              options of every corpus input read from the tree are 0.7.0's.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class MermaidYAMLTreeEquivalenceTests: XCTestCase {
    /// How the tree's reading of `yaml` differs from the reference's, or nil.
    private func difference(_ yaml: String) -> String? {
        let bytes = Array(yaml.utf8)
        let expected = MermaidYAMLDocument.value(of: bytes)
        let tree = MermaidYAMLTree.read(bytes)
        switch (expected, tree) {
        case (nil, nil): return nil
        case (nil, let tree?): return "read \(tree.value(of: MermaidYAMLTree.root)), expected a refusal"
        case (let expected?, nil): return "refused, expected \(expected)"
        case (let expected?, let tree?):
            let read = tree.value(of: MermaidYAMLTree.root)
            guard DirectiveValueComparison.isIdentical(read, expected) else { return "read \(read), expected \(expected)" }
            let title = MermaidFrontMatter.title(in: tree)
            let expectedTitle = ReferenceMermaidFrontMatter.title(in: expected)
            return title == expectedTitle ? nil : "title \(title ?? "-"), expected \(expectedTitle ?? "-")"
        }
    }

    private func differences(_ texts: [String]) -> [String] {
        var found: [String] = []
        for text in texts {
            guard let difference = difference(text) else { continue }
            found.append("\(difference) in \(text.debugDescription)")
            if found.count == 5 { break }
        }
        return found
    }

    private func isReadOnBytes(_ yaml: String) -> Bool {
        MermaidYAMLTreeReader.tree(of: Array(yaml.utf8)) != nil
    }

    /// The front matter body of every source that has one, as the reader finds it.
    static func frontMatterBodies() throws -> [String] {
        try MermaidDirectiveJSONEquivalenceTests.everySource().compactMap { source in
            ReferenceMermaidFrontMatter.find(in: Array(source.utf8)).map(\.body)
        }
    }

    func testEveryCorpusFrontMatterIsReadAsTheReferenceReadsIt() throws {
        let bodies = try Self.frontMatterBodies()
        XCTAssertGreaterThan(bodies.count, 150)
        XCTAssertEqual(differences(bodies), [])
        // Nearly every front matter written is of the shapes read on bytes.
        XCTAssertGreaterThan(bodies.filter(isReadOnBytes).count, bodies.count * 9 / 10)
    }

    func testPelesYAMLTextsAreReadAsTheReferenceReadsThem() throws {
        let texts = try PeleResults.preprocessing().yaml.map(\.source)
        XCTAssertEqual(differences(texts), [])
    }

    func testRandomYAMLTextsAreReadAsTheReferenceReadsThem() {
        var generator = RandomYAMLTexts(seed: 0x9A31_0001)
        let texts = (0..<15_000).map { _ in generator.document() }
        XCTAssertEqual(differences(texts), [])
        let readOnBytes = texts.filter(isReadOnBytes).count
        XCTAssertGreaterThan(readOnBytes, 3_000, "too few texts read on bytes to compare")
        XCTAssertLessThan(readOnBytes, 14_000, "too few texts left to the reference to compare")
    }

    func testMutatedFrontMattersAreReadAsTheReferenceReadsThem() throws {
        let bodies = try Self.frontMatterBodies()
        var generator = RandomYAMLTexts(seed: 0x9A31_0002)
        let texts = (0..<15_000).map { index in generator.mutated(index.isMultiple(of: 3) ? generator.document() : bodies[index % bodies.count]) }
        XCTAssertEqual(differences(texts), [])
    }

    func testHostileYAMLIsReadAsTheReferenceReadsItAndBounded() {
        let deep = (0..<120).map { depth in String(repeating: " ", count: depth) + "k\(depth):" }.joined(separator: "\n") + " 1"
        let wide = (0..<6_000).map { index in "key\(index): value \(index)" }.joined(separator: "\n")
        let duplicated = (0..<200).map { _ in "a: 1" }.joined(separator: "\n")
        let longLine = "a: " + String(repeating: "x", count: 50_000)
        let ragged = (0..<3_000).map { index in String(repeating: " ", count: index % 7) + "k\(index): v" }.joined(separator: "\n")
        let wideMappings = (0..<300).map { index in "m\(index):\n" + (0..<130).map { key in "  k\(key): \(key)" }.joined(separator: "\n") }
            .joined(separator: "\n")
        XCTAssertEqual(differences([deep, wide, duplicated, longLine, ragged, wideMappings, "", "\n", "---", "a:", ":", "'a': 1", "\"a\": 1"]), [])
        let start = ContinuousClock.now
        for text in [wide, ragged, wideMappings] { _ = MermaidYAMLTree.read(Array(text.utf8)) }
        XCTAssertLessThan(ContinuousClock.now - start, .seconds(5))
    }

    /// The title and every type's options of every corpus input, its front matter read in place into a tree, are
    /// 0.7.0's (`MermaidDirectiveJSONEquivalenceTests` compares the options with the frozen reference).
    func testEveryCorpusInputsTitleIsAsBefore() throws {
        var found: [String] = []
        for source in try MermaidDirectiveJSONEquivalenceTests.everySource() {
            guard let (expectedTitle, _) = try? ReferenceMermaidReader.preprocessed(source) else { continue }
            // A text refused at its keyword is compared by MermaidFrontEndEquivalenceTests.
            guard let frontEnd = try? MermaidFrontEnd.read(source) else { continue }
            if frontEnd.frontMatterTitle != expectedTitle { found.append("title \(frontEnd.frontMatterTitle ?? "-") in \(source.prefix(80).debugDescription)") }
        }
        XCTAssertEqual(Array(found.prefix(5)), [])
    }
}

/// Seeded YAML texts of the shapes front matter is written in and of many others: nested mappings, plain and quoted
/// scalars, numbers and spellings of null and the Booleans, comments, blank lines, fences, lists, flow collections,
/// block scalars, tabs, text beyond ASCII, duplicated keys and wrong indentations.
struct RandomYAMLTexts {
    private var random: RandomJSONTexts
    /// Whether the document being made takes only the keys and scalars front matter is commonly written with.
    private var isCommon = false

    init(seed: UInt64) {
        random = RandomJSONTexts(seed: seed)
    }

    private mutating func pick(_ choices: [String]) -> String {
        choices[random.below(choices.count)]
    }

    private mutating func key() -> String {
        if isCommon { return pick(["config", "title", "theme", "themeVariables", "gitGraph", "pie", "cScale0", "a", "b-c", "_x", "'git0'", "\"q\"", ".ts", "x y"]) }
        return pick(["config", "title", "theme", "themeVariables", "gitGraph", "pie", "showBranches", "cScale0", "pie1", "a", "a", "b-c", "_x", "'git0'",
              "\"quoted\"", "'it''s'", "\"esc\\\"aped\"", ".ts", "Electricity grid", "1", "null", "true", "x y", "é", "k#", "-k", "?k", "a:b",
              "displayMode", "xyChart", "plotColorPalette", "__proto__"])
    }

    private mutating func scalar() -> String {
        if isCommon {
            return pick(["dagre", "'base'", "\"#ff0000\"", "0.25", "400", "-3", "+4", ".5", "1e3", "0x1F", ".inf", "true", "False", "NULL", "~", "''",
                         "it's", "a # c", "'q' # c", "$0,0", "a b", "#ff0000"])
        }
        return pick(["dagre", "classic", "'base'", "\"#ff0000\"", "'#00ff00'", "#ff0000", "0.25", "400", "-3", "+4", ".5", "1e3", "0x1F", "0o17", "0b101",
              ".inf", "-.Inf", ".nan", "true", "False", "NULL", "~", "null", "yes", "''", "\"\"", "'a''b'", "\"a\\nb\"", "it's", "a # c", "a#b",
              "'q' # c", "'unclosed", "\"unclosed", "[1, 2]", "{a: 1}", "|", ">-", "- x", "*a", "&a b", "a: b", "é", "\tx", "x\t", "$0,0",
              "'https://x/#T#'", "material-icon-theme", "compact     #gantt"])
    }

    private mutating func lines(indent: Int, depth: Int) -> [String] {
        var lines: [String] = []
        let spaces = String(repeating: " ", count: indent)
        for _ in 0..<(random.below(4) + 1) {
            switch isCommon ? 3 + random.below(depth > 2 ? 5 : 8) : random.below(depth > 2 ? 8 : 11) {
            case 0: lines.append(pick(["", "  ", "# comment", spaces + "# c", "---", "..."]))
            case 1: lines.append(spaces + pick(["- item", "-", "- a: 1"]))
            case 2: lines.append(String(repeating: " ", count: max(0, indent + [-1, 1, 3][random.below(3)])) + key() + ": " + scalar())
            case 3 ... 7:
                let separator = isCommon ? pick([": ", ":  ", " : "]) : pick([": ", ":", ":  ", " : ", ":\t"])
                lines.append(spaces + key() + separator + scalar() + (isCommon ? pick(["", "", " ", "  # note"]) : pick(["", "", " ", "  # note", "\t"])))
            default:
                lines.append(spaces + key() + pick([":", ":", ": ", ": # c"]))
                lines.append(contentsOf: self.lines(indent: indent + [2, 4, 1, 2][random.below(4)], depth: depth + 1))
            }
        }
        return lines
    }

    /// A document: lines of mappings, sometimes indented as a whole, sometimes with a line continuing a scalar.
    mutating func document() -> String {
        isCommon = random.below(2) == 0
        var lines = self.lines(indent: random.below(4) == 0 ? 2 : 0, depth: 0)
        if isCommon { return lines.joined(separator: "\n") + pick(["", "\n"]) }
        if random.below(12) == 0 { lines.insert(pick(["      continued", "  more text", "\tx"]), at: random.below(lines.count + 1)) }
        if random.below(20) == 0 { lines = [pick(["{a: 1, b: [2]}", "[1, 2]", "plain", "'q'"])] + lines }
        return lines.joined(separator: pick(["\n", "\n", "\n", "\r\n", "\n\n"])) + pick(["", "\n", "\n\n"])
    }

    /// `text` changed one to three times.
    mutating func mutated(_ text: String) -> String {
        random.mutated(text)
    }
}
