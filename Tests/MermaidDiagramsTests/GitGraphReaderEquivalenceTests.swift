/**
 * File: GitGraphReaderEquivalenceTests.swift
 * ------------------------------------------
 * Layer: Tests
 * Description: The Git graph reader gives the graph 0.7.0's reader gave, or its error with its line, on every corpus
 *              input and spec text, thousands of them changed at random, random histories of every statement, and
 *              long and many ones in time; made-up commit ids are 0.7.0's for every place and taken id.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class GitGraphReaderEquivalenceTests: XCTestCase {
    private static let tokens = ["gitGraph", "gitGraph LR:", "gitGraph TB:\n", "commit\n", "commit id: \"a\"\n", "commit id: \"0-1c6f6a1\"\n",
                                 "commit tag: \"v1\"\n", "commit type: HIGHLIGHT\n", "commit type: REVERSE msg: \"m\"\n", "branch develop\n",
                                 "branch feature order: 2\n", "checkout main\n", "switch develop\n", "merge develop\n", "merge feature id: \"m\" tag: \"t\"\n",
                                 "cherry-pick id: \"a\"\n", "cherry-pick id: \"m\" parent: \"a\"\n", "branch main\n", "checkout nowhere\n", "id:", "tag:",
                                 "\"unclosed", "order: -1", "title History\n", "accTitle: t\n"]

    @discardableResult
    private func assertReadAsTheReference(_ source: String, limits: MermaidDiagramLimits = .standard, file: StaticString = #filePath,
                                          line: UInt = #line) -> Bool {
        guard let frontEnd = try? MermaidFrontEnd.read(source), frontEnd.typeKeyword == .gitGraph else { return false }
        let cursor = MermaidTextCursor(frontEnd)
        let read = MapReadingEquivalence.outcome { () throws(MermaidDiagramReadError) in try GitGraphParser.parse(cursor, limits: limits) }
        let expected = MapReadingEquivalence.outcome { () throws(MermaidDiagramReadError) in try ReferenceGitGraphParser.parse(cursor, limits: limits) }
        XCTAssertEqual(read, expected, String(source.prefix(200)), file: file, line: line)
        return true
    }

    func testEveryTextAndItsChangesReadAsTheFrozenReaderReadThem() throws {
        let texts = MapReadingEquivalence.texts(readAs: .gitGraph, among: try MapReadingEquivalence.everyText(), mutationCount: 60, tokens: Self.tokens,
                                                seed: 0x617_0001)
        var comparedCount = 0
        for text in texts where assertReadAsTheReference(text) { comparedCount += 1 }
        XCTAssertGreaterThan(comparedCount, 2_000)
    }

    /// Histories of every statement: commits with written, made-up and colliding ids, tags and types, branches with
    /// orders, checkouts, merges and cherry-picks that Mermaid takes and that it refuses.
    func testRandomHistoriesReadAsTheFrozenReaderReadThem() {
        var random = MapReadingMutations(seed: 0x617_0002, tokens: [])
        let branchNames = ["main", "develop", "feature", "release/1.0", "hot-fix", "é"]
        for _ in 0..<1_500 {
            var text = ["gitGraph\n", "gitGraph LR:\n", "gitGraph TB:\n", "gitGraph BT:\n"][random.below(4)]
            var commitNames: [String] = []
            for step in 0..<(1 + random.below(24)) {
                let branch = branchNames[random.below(branchNames.count)]
                switch random.below(7) {
                case 0, 1:
                    var statement = "commit"
                    if random.below(3) == 0 {
                        let name = random.below(4) == 0 ? "\(random.below(4))-\(["1c6f6a1", "3c6ef37", "daa66d4"][random.below(3)])" : "c\(step)"
                        commitNames.append(name)
                        statement += " id: \"\(name)\""
                    }
                    if random.below(4) == 0 { statement += " tag: \"v\(step)\"" }
                    if random.below(5) == 0 { statement += [" type: HIGHLIGHT", " type: REVERSE", " type: NORMAL"][random.below(3)] }
                    text += statement + "\n"
                case 2: text += "branch \(branch)" + (random.below(3) == 0 ? " order: \(random.below(4))" : "") + "\n"
                case 3: text += ["checkout ", "switch "][random.below(2)] + branch + "\n"
                case 4: text += "merge \(branch)" + (random.below(3) == 0 ? " id: \"m\(step)\"" : "") + (random.below(4) == 0 ? " tag: \"t\(step)\"" : "") + "\n"
                case 5:
                    let picked = commitNames.isEmpty ? "none" : commitNames[random.below(commitNames.count)]
                    text += "cherry-pick id: \"\(picked)\"" + (random.below(4) == 0 ? " parent: \"c\(random.below(step + 1))\"" : "") + "\n"
                default: text += "commit\n"
                }
            }
            assertReadAsTheReference(text)
        }
    }

    /// Made-up ids are the frozen ones for every place up to 200,000 and for the next candidates after taken ones.
    func testMadeUpIdsAreTheFrozenOnes() {
        for place in 0..<200_000 {
            XCTAssertEqual(GitGraphCommitIdentifier.generated(sequenceNumber: place) { _ in false },
                           ReferenceGitGraphCommitIdentifier.generated(sequenceNumber: place) { _ in false })
        }
        for place in [0, 9, 10, 99, 12_345, Int(Int32.max), Int.max - 1] {
            var refusals = 0
            let identifier = GitGraphCommitIdentifier.generated(sequenceNumber: place) { _ in refusals += 1; return refusals < 5 }
            var referenceRefusals = 0
            let expected = ReferenceGitGraphCommitIdentifier.generated(sequenceNumber: place) { _ in referenceRefusals += 1; return referenceRefusals < 5 }
            XCTAssertEqual(identifier, expected)
        }
    }

    /// Many commits, branches past the node limit, long names and messages are read as the frozen reader reads them,
    /// each in well under a second.
    func testHostileHistoriesReadAsTheFrozenReaderQuickly() {
        let cases = [
            "gitGraph\n" + String(repeating: "commit\n", count: 2_500),
            "gitGraph\n" + (0..<1_200).map { index in "branch b\(index)\ncommit\n" }.joined(),
            "gitGraph\ncommit id: \"" + String(repeating: "x", count: 40_000) + "\"",
            "gitGraph\ncommit\nbranch " + String(repeating: "n", count: 30_000) + "\ncommit\ncheckout main\nmerge " + String(repeating: "n", count: 30_000),
            "gitGraph\n" + (0..<800).map { index in "commit id: \"c\(index)\" tag: \"t\(index)\"\n" }.joined(),
        ]
        for source in cases {
            XCTAssertTrue(assertReadAsTheReference(source), String(source.prefix(40)))
            guard let cursor = MapReadingEquivalence.cursor(of: source, readAs: .gitGraph) else { continue }
            let start = Date()
            _ = try? GitGraphParser.parse(cursor, limits: .standard)
            XCTAssertLessThan(Date().timeIntervalSince(start), 1, String(source.prefix(40)))
        }
    }
}
