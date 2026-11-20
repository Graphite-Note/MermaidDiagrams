/**
 * File: PeleCompatCoverageTests.swift
 * -----------------------------------
 * Layer: Tests
 * Description: Walks the copy of the inputs of Pele's tests/compat (Mermaid 12.1.0's parser specs as Pele ports them)
 *              and reports every spec file of which the package's tests and resources hold no text.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import Foundation
import XCTest
@testable import MermaidDiagramsBenchmark

/// Every type of tests/compat is ported (each has its parser tests), so a spec file none of whose diagram texts appears in
/// the package's tests or resources is either ported with texts of its own or not ported: either way it must be listed in
/// PeleKnownDifferences.md with what covers it. A text is looked for without its spaces and its first line (the type's
/// keyword, which the tests' helpers often add), so that an input written over several Swift lines or with `\n` is found.
final class PeleCompatCoverageTests: XCTestCase {
    func testEveryCompatSpecFileHasItsTextsInTheTestsOrIsListed() throws {
        let haystack = try Self.testsAndResources() as NSString
        let known = try PeleKnownDifferenceList()
        let inputs = try PeleResults.compatInputs()
        XCTAssertEqual(inputs.count, 136, "The spec and test files of Pele's tests/compat")
        var foundCount = 0, textCount = 0, report: [String] = []
        for (file, texts) in inputs.sorted(by: { first, second in first.key < second.key }) where !texts.isEmpty {
            let found = texts.filter { text in haystack.range(of: Self.signature(of: text), options: .literal).location != NSNotFound }.count
            foundCount += found
            textCount += texts.count
            report.append("\(found)/\(texts.count) \(file)")
            if found == 0 {
                XCTAssertNotNil(known.compatFilesWithoutCopies[file], "\(file): none of its \(texts.count) texts is in the package's tests, and it is not listed")
            } else {
                XCTAssertNil(known.compatFilesWithoutCopies[file], "\(file) is listed as without copies, but \(found) of its texts are found")
            }
        }
        XCTAssertGreaterThan(foundCount * 10, textCount * 6, "Texts of tests/compat found in the package's tests:\n" + report.joined(separator: "\n"))
    }

    /// The text without its first line (unless that leaves almost nothing) and without white space.
    static func signature(of text: String) -> String {
        let lines = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n", omittingEmptySubsequences: false)
        let body = lines.count > 1 ? lines.dropFirst().joined(separator: "\n") : text
        let signature = withoutWhiteSpace(body)
        return signature.count >= 4 ? signature : withoutWhiteSpace(text)
    }

    private static func withoutWhiteSpace(_ text: String) -> String {
        String(text.unicodeScalars.filter { scalar in !CharacterSet.whitespacesAndNewlines.contains(scalar) }.map(Character.init))
    }

    /// The package's test sources, with Swift's `\n`, `\t`, `\"` and `\\` read, and every input of its resources.
    private static func testsAndResources() throws -> String {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        var haystack = ""
        for name in try FileManager.default.contentsOfDirectory(atPath: folder.path) where name.hasSuffix(".swift") {
            let source = try String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)
            haystack += withoutWhiteSpace(source.replacingOccurrences(of: "\\n", with: "").replacingOccurrences(of: "\\t", with: "")
                .replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\"))
        }
        let corpora = Set(try PeleResults.corpus().inputs.map(\.corpus))
        for corpus in corpora.sorted() { haystack += try PeleResults.sources(ofCorpus: corpus).map(withoutWhiteSpace).joined() }
        haystack += try PeleResults.flowchartSpecTexts().map { text in withoutWhiteSpace(text.source) }.joined()
        return haystack
    }
}
