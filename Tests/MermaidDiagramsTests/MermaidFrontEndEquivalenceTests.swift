/**
 * File: MermaidFrontEndEquivalenceTests.swift
 * -------------------------------------------
 * Layer: Tests
 * Description: The front end that reads a String's own bytes when preprocessing would change none gives every type's
 *              reader the cursor 0.7.0's copying front end gave it: the same bytes, text as written, front matter,
 *              position and line after the keyword, the same title, or the same error.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class MermaidFrontEndEquivalenceTests: XCTestCase {
    /// How the front end's reading of `source` differs from the reference's, or nil.
    private func difference(_ source: String) -> String? {
        let reference = Result { () throws(MermaidDiagramReadError) -> (String?, ReferenceMermaidTextCursor, String) in
            var (title, cursor) = try ReferenceMermaidReader.preprocessed(source)
            ReferenceMermaidReader.skipCommentsAndBlankLines(&cursor)
            guard let keyword = ReferenceMermaidReader.readTypeKeyword(&cursor) else {
                throw cursor.isAtEnd ? .noDiagram : .invalidSyntax(line: cursor.line, problem: .unexpectedText(cursor.excerpt()))
            }
            return (title, cursor, keyword)
        }
        let read = Result { () throws(MermaidDiagramReadError) in try MermaidFrontEnd.read(source) }
        switch (reference, read) {
        case (.failure(let expected), .failure(let error)): return expected == error ? nil : "error \(error), expected \(expected)"
        case (.failure(let expected), .success): return "read, expected \(expected)"
        case (.success, .failure(let error)): return "error \(error)"
        case (.success(let (title, expected, keyword)), .success(let frontEnd)):
            let cursor = MermaidTextCursor(frontEnd)
            if frontEnd.keywordText != keyword { return "keyword \(frontEnd.keywordText), expected \(keyword)" }
            if frontEnd.frontMatterTitle != title { return "title \(frontEnd.frontMatterTitle ?? "-"), expected \(title ?? "-")" }
            if cursor.bytes != expected.bytes { return "bytes differ" }
            if cursor.sourceBytes != expected.sourceBytes { return "text as written differs" }
            if cursor.position != expected.position || cursor.line != expected.line {
                return "position \(cursor.position) line \(cursor.line), expected \(expected.position) line \(expected.line)"
            }
            if cursor.readFrontMatter?.frontMatter?.bodyBytes != expected.readFrontMatter?.frontMatter?.bodyBytes
                || cursor.readFrontMatter?.frontMatter?.end != expected.readFrontMatter?.frontMatter?.end
                || cursor.readFrontMatter?.value != expected.readFrontMatter?.value { return "front matter differs" }
            return nil
        }
    }

    private func differences(in sources: [String]) -> [String] {
        var found: [String] = []
        for source in sources {
            guard let difference = difference(source) else { continue }
            found.append("\(difference) in \(String(source.prefix(120)).debugDescription)")
            if found.count == 5 { break }
        }
        return found
    }

    func testEveryCorpusInputIsReadUpToItsKeywordAsBefore() throws {
        let sources = try OutputDigest.corpora().flatMap(\.sources) + PeleResults.compatInputs().sorted { $0.key < $1.key }.flatMap(\.value)
            + PeleResults.flowchartSpecTexts().map(\.source) + PeleResults.preprocessing().preprocessing.map(\.source)
        XCTAssertEqual(differences(in: sources), [])
    }

    func testMutatedExamplesAreReadUpToTheirKeywordAsBefore() throws {
        let examples = try OutputDigest.corpora().flatMap(\.sources)
        var mutations = FlowchartReadingMutations(seed: 0xF0_0D)
        let prefixes = ["", "\u{FEFF}", "---\ntitle: T\n---\n", "  ---\n", "%%{init: {}}%%\n", "%% c\n", "\r\n", " \n\t", "---\n"]
        var sources: [String] = []
        for index in 0..<6_000 { sources.append(prefixes[index % prefixes.count] + mutations.mutated(examples[index % examples.count])) }
        XCTAssertEqual(differences(in: sources), [])
    }

    /// Texts each pass changes, and texts that hold what a pass looks for without being changed by it.
    func testTextsEachPassChangesOrLeavesAreReadAsBefore() {
        let sources = [
            "graph TD\nA[<span style=\"color:red\">x</span>] --> B", "graph TD\nA[<b>x</b>] --> B", "graph TD\nA --> B\n<br>\n",
            "graph TD\nstyle A fill:#f00;\nA-->B", "graph TD\nstyle A fill:#f00\nA-->B", "graph TD\nclassDef a fill:#f00;stroke:#000;\n",
            "graph TD\nA-->%%{init: {}}%%B", "graph TD\n%% {not a directive}\nA-->B", "graph TD\r\nA-->B\r\n", "\u{FEFF}graph TD\nA",
            "\u{00A0}---\ntitle: x\n---\ngraph TD\nA", "---\n", "---", "  --- \ngraph", "", "%%", "  \n", "1graph", "graph", "\u{2028}graph",
        ]
        XCTAssertEqual(differences(in: sources), [])
    }

    /// A text no pass changes is read from the String itself: no array of its bytes is made for a flowchart.
    func testATextNoPassChangesKeepsTheStringItWasGiven() throws {
        let frontEnd = try MermaidFrontEnd.read("flowchart TD\n  A[\"#1\"] --> B\n  %% a comment\n")
        XCTAssertNil(frontEnd.sourceBytes)
        XCTAssertEqual(frontEnd.typeKeyword, .flowchart)
        XCTAssertEqual(frontEnd.keyword, MermaidTextRange(start: 0, end: 9))
        XCTAssertNotNil(try MermaidFrontEnd.read("graph TD\nstyle A fill:#f00;\n").sourceBytes)
    }

    /// A text past `MermaidTextRange`'s 32-bit offsets is refused before any range is made, whatever limits the caller
    /// set: a range of it would wrap, and a flowchart's reading would read its name table's bytes at a negative offset.
    func testATextLongerThanARangeCanIndexIsRefused() {
        XCTAssertNoThrow(try MermaidFrontEnd.refuseUnindexable(byteCount: Int(Int32.max)))
        XCTAssertThrowsError(try MermaidFrontEnd.refuseUnindexable(byteCount: Int(Int32.max) + 1)) { error in
            XCTAssertEqual(error as? MermaidDiagramReadError, .sourceTooLarge(limitBytes: Int(Int32.max)))
        }
    }
}
