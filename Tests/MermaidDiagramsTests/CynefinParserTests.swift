/**
 * File: CynefinParserTests.swift
 * ------------------------------
 * Layer: Tests
 * Description: The inputs of Mermaid 12.1.0's Cynefin specs (cynefin.spec.ts and cynefin.integration.spec.ts, as Pele
 *              ports them in tests/compat/cynefin), the seeds of Pele's differential test, and the errors.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class CynefinParserTests: XCTestCase {
    private func cynefin(_ source: String) throws -> CynefinDiagram {
        try CynefinReading.cynefin(source)
    }

    // MARK: Mermaid's integration spec

    func testDomainsWithTheirItems() throws {
        let basic = try cynefin("cynefin-beta\n  complex\n    \"Emergent practice\"\n    \"Probe-sense-respond\"\n  clear\n    \"Best practice\"\n")
        XCTAssertEqual(basic.items.count, 2)
        XCTAssertEqual(basic.items[.complex], ["Emergent practice", "Probe-sense-respond"])
        XCTAssertEqual(basic.items[.clear], ["Best practice"])
        let five = try cynefin("cynefin-beta\n  complex\n    \"A\"\n  complicated\n    \"B\"\n  clear\n    \"C\"\n  chaotic\n    \"D\"\n  confusion\n    \"E\"\n")
        XCTAssertEqual(Set(five.items.keys), Set(CynefinDomain.allCases))
        XCTAssertEqual(try cynefin("cynefin-beta\n  complex\n").items[.complex], [])
        XCTAssertEqual(try cynefin("cynefin-beta\n  complex\n    \"First item\"\n    \"Second item\"\n    \"Third item\"\n").items[.complex],
                       ["First item", "Second item", "Third item"])
        let commented = try cynefin("cynefin-beta\n  %% This is a comment\n  complex\n    \"Item\"\n  %% Another comment\n")
        XCTAssertEqual(commented.items, [.complex: ["Item"]])
    }

    func testTransitionsWithAndWithoutLabels() throws {
        let labelled = try cynefin("cynefin-beta\n  complex\n    \"Practice\"\n  complicated\n    \"Analysis\"\n  complex --> complicated : \"Pattern found\"\n")
        XCTAssertEqual(labelled.transitions, [CynefinTransition(from: .complex, to: .complicated, label: "Pattern found")])
        XCTAssertEqual(try cynefin("cynefin-beta\n  complex\n    \"A\"\n  complicated\n    \"B\"\n  complex --> complicated\n").transitions,
                       [CynefinTransition(from: .complex, to: .complicated, label: nil)])
        let several = try cynefin("cynefin-beta\n  complex\n    \"A\"\n  complicated\n    \"B\"\n  clear\n    \"C\"\n  complex --> complicated : \"Analyzed\"\n"
                                  + "  complicated --> clear : \"Codified\"\n  chaotic --> complex : \"Stabilized\"\n")
        XCTAssertEqual(several.transitions.map(\.from), [.complex, .complicated, .chaotic])
    }

    func testAccessibilityStatementsAndTheTitle() throws {
        XCTAssertEqual(try cynefin("cynefin-beta\n  accTitle: Cynefin Framework Overview\n  complex\n    \"Emergent\"\n").accessibilityTitle, "Cynefin Framework Overview")
        XCTAssertEqual(try cynefin("cynefin-beta\n  accDescr: A diagram showing the five Cynefin domains\n  complex\n    \"Emergent\"\n").accessibilityDescription,
                       "A diagram showing the five Cynefin domains")
        XCTAssertEqual(try cynefin("cynefin-beta\n  title My Cynefin Map\n  complex\n    \"Emergent\"\n").title, "My Cynefin Map")
    }

    func testAFullDiagram() throws {
        let diagram = try cynefin("""
            cynefin-beta
              title Team Practices
              accTitle: Cynefin for team practices
              complex
                "Retrospectives"
                "Pair programming"
              complicated
                "Code review"
                "Architecture decisions"
              clear
                "Deployment checklist"
              chaotic
                "Incident response"
              confusion
                "New initiative"
              complex --> complicated : "Pattern emerges"
              complicated --> clear : "Best practice found"
              chaotic --> complex : "Stabilized"
              confusion --> chaotic : "Crisis detected"
            """)
        XCTAssertEqual(diagram.title, "Team Practices")
        XCTAssertEqual(diagram.accessibilityTitle, "Cynefin for team practices")
        XCTAssertEqual(CynefinDomain.allCases.map { domain in diagram.items[domain]?.count }, [2, 2, 1, 1, 1])
        XCTAssertEqual(diagram.transitions.count, 4)
        XCTAssertEqual(diagram.transitions.last, CynefinTransition(from: .confusion, to: .chaotic, label: "Crisis detected"))
    }

    func testTransitionsFromADomainToItselfAreLeftOut() throws {
        let mixed = try cynefin("cynefin-beta\n  complex\n    \"A\"\n  complicated\n    \"B\"\n  complex --> complex : \"Self-reflection\"\n"
                                + "  complex --> complicated : \"Pattern found\"\n  complicated --> complicated\n")
        XCTAssertEqual(mixed.transitions, [CynefinTransition(from: .complex, to: .complicated, label: "Pattern found")])
        XCTAssertTrue(try cynefin("cynefin-beta\n  complex\n    \"A\"\n  complex --> complex\n").transitions.isEmpty)
    }

    func testALaterBlockOfADomainReplacesTheEarlier() throws {
        let diagram = try cynefin("cynefin-beta\ncomplex\n\"a\"\ncomplex\n\"b\"\ncomplex --> complicated : 'single'\n")
        XCTAssertEqual(diagram.items[.complex], ["b"])
        XCTAssertEqual(diagram.transitions.first?.label, "single")
    }

    // MARK: The seeds of Pele's differential test, every one of which Mermaid's grammar accepts

    func testPelesSeedsRead() throws {
        let seeds = [
            "cynefin-beta", "cynefin-beta:", "cynefin-beta:\ncomplex\n\"a\"", "\n\n  cynefin-beta\n", "cynefin-beta title T\n",
            "cynefin-beta complex \"a\" \"b\" clear\n\"c\"", "cynefin-beta\ncomplex --> clear\nclear --> chaotic : \"x\"\nchaotic --> chaotic",
            "cynefin-beta\naccTitle: at\naccDescr {\n multi\n line\n}\ntitle t\ncomplex\n\n\n\"a\"\n\n\"b\"\n",
            "cynefin-beta\ncomplex\n\"a\"\ncomplex\n\"b\"\ncomplex --> complicated : 'single'\n", "---\ntitle: x\n---\ncynefin-beta\nclear\n\"a\"",
            "%%{init: {\"theme\":\"dark\"}}%%\ncynefin-beta %% c\nclear %% d\n\"a\" %% e\n", "cynefin-beta\r\ncomplex\r\n\"a\"\r\n",
        ]
        for seed in seeds { XCTAssertNoThrow(try cynefin(seed), seed) }
        XCTAssertEqual(try cynefin(seeds[5]).items, [.complex: ["a", "b"], .clear: ["c"]])
        let described = try cynefin(seeds[7])
        XCTAssertEqual(described.accessibilityDescription, "multi\nline")
        XCTAssertEqual(described.items[.complex], ["a", "b"])
        XCTAssertEqual(try cynefin(seeds[9]).title, "x")
        XCTAssertEqual(try cynefin(seeds[10]).items[.clear], ["a"])
        XCTAssertEqual(try cynefin(seeds[11]).items[.complex], ["a"])
    }

    func testStringsTakeTheirEscapes() throws {
        XCTAssertEqual(try cynefin("cynefin-beta\ncomplex\n\"a\\\"b\" 'c\\nd'").items[.complex], ["a\"b", "c\nd"])
    }

    func testErrorsSayWhatBrokeOnWhichLine() {
        XCTAssertEqual(CynefinReading.readError("cynefin-beta\n  complexity"), .invalidSyntax(line: 2, problem: .unexpectedText("ity")))
        XCTAssertEqual(CynefinReading.readError("cynefin-beta\n  Clear"), .invalidSyntax(line: 2, problem: .unexpectedText("Clear")))
        XCTAssertEqual(CynefinReading.readError("cynefin-beta\n  complex --> "), .invalidSyntax(line: 2, problem: .cynefin(.expectedDomain)))
        XCTAssertEqual(CynefinReading.readError("cynefin-beta\n  complex --> clear : x"), .invalidSyntax(line: 2, problem: .unexpectedText("x")))
        XCTAssertEqual(CynefinReading.readError("cynefin-beta\n  complex --> clear : clear"), .invalidSyntax(line: 2, problem: .cynefin(.expectedQuotedLabel)))
        XCTAssertEqual(CynefinReading.readError("cynefin-beta\n  title x\n  \"stray\""), .invalidSyntax(line: 3, problem: .cynefin(.expectedStatement)))
        XCTAssertEqual(CynefinReading.readError("cynefin-beta\n  complex --> clear \"a\""), .invalidSyntax(line: 2, problem: .cynefin(.expectedLineEnd)))
        XCTAssertEqual(CynefinReading.readError("cynefin-beta\n  complex\n  \"unclosed"), .invalidSyntax(line: 3, problem: .unexpectedText("\"unclosed")))
        XCTAssertEqual(CynefinReading.readError("cynefin-beta_x"), .invalidSyntax(line: 1, problem: .unexpectedText("_x")))
    }

    func testOptionsComeFromTheFrontMatterWithinTheirRanges() throws {
        let options = try cynefin("---\nconfig:\n  cynefin:\n    seed: 42\n    width: 900\n    height: 50\n    showDomainDescriptions: false\n"
                                  + "    boundaryAmplitude: 20\n---\ncynefin-beta\n  complex").options
        XCTAssertEqual(options.seed, 42)
        XCTAssertEqual(options.width, 900)
        XCTAssertEqual(options.height, 440, "Below 100: the default")
        XCTAssertFalse(options.showsDomainDescriptions)
        XCTAssertEqual(options.boundaryAmplitude, 20)
        XCTAssertNil(try cynefin("---\nconfig:\n  cynefin:\n    seed: 0\n---\ncynefin-beta").options.seed, "Zero: the identifier's hash")
    }

    func testItemsAndTransitionsAreBoundedByTheLimits() {
        var limits = MermaidDiagramLimits.standard
        limits.maximumNodeCount = 2
        limits.maximumEdgeCount = 1
        XCTAssertEqual(CynefinReading.readError("cynefin-beta\ncomplex\n\"a\"\n\"b\"\n\"c\"", limits: limits), .tooManyNodes(limit: 2))
        XCTAssertNil(CynefinReading.readError("cynefin-beta\ncomplex\n\"a\"\n\"b\"\ncomplex\n\"c\"\n\"d\"", limits: limits), "A replaced block no longer counts")
        XCTAssertEqual(CynefinReading.readError("cynefin-beta\ncomplex --> clear\nclear --> chaotic", limits: limits), .tooManyEdges(limit: 1))
    }
}
