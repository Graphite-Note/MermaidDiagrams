/**
 * File: AgentFlowReadingEquivalenceTests.swift
 * --------------------------------------------
 * Layer: Tests
 * Description: The agent flow reader on bytes against 0.7.0's reader on UTF-16 code units kept as the reference: every
 *              corpus input, Pele's reference inputs, random and mutated texts (beyond ASCII and kept to it), spellings
 *              Swift holds equal, each the same model, list for list, or the same error; hostile texts read in time
 *              that grows with their length, and readings on many threads at once alike; names Swift holds equal
 *              that the grammar reads, one name.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 26/11/2026
 */

import Foundation
import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class AgentFlowReadingEquivalenceTests: XCTestCase {
    func testEveryCorpusInputAndPelesReferenceInputIsReadAsTheReferenceReadsIt() throws {
        let sources = try Self.originals()
        XCTAssertGreaterThan(Self.assertReadAlike(sources), 250)
        XCTAssertGreaterThan(Self.assertReadAlike(sources.map(GraphTextMutations.ascii)), 250)
    }

    func testMutatedTextsAreReadAsTheReferenceReadsThem() throws {
        var mutations = GraphTextMutations(seed: 41)
        let originals = try Self.originals()
        var sources: [String] = []
        for round in 0..<8_000 {
            let mutated = mutations.mutated(originals[round % originals.count], pieces: Self.pieces)
            sources.append(round % 2 == 0 ? mutated : GraphTextMutations.ascii(mutated))
        }
        XCTAssertGreaterThan(Self.assertReadAlike(sources), 5_000)
    }

    func testRandomlyChangedTextsAreReadAsTheReferenceReadsThem() throws {
        var mutations = C4RandomTexts(seed: 47)
        let originals = try Self.originals()
        let sources = (0..<3_000).map { round in mutations.mutated(originals[round % originals.count]) }
        XCTAssertGreaterThan(Self.assertReadAlike(sources), 2_000)
    }

    /// Names Swift holds equal (a composed and a decomposed letter, the Kelvin sign and `K`) are one node, one flow, one
    /// class and one edge identifier, as 0.7.0's String keys made them; text beyond the Basic Multilingual Plane counts two
    /// columns, and a line or paragraph separator in a multi-line token stops its column, as Jison counts them.
    func testSpellingsAndCharactersBeyondASCIIAreReadAlike() {
        let sources = [
            "agentflow-beta\n  caf\u{E9} --> cafe\u{301}\n  cafe\u{301}@{ shape: tool }",
            "agentflow-beta\n  flow caf\u{E9}[Flow]\n    \u{212A} --> K\n  end\n  style K fill:#f00\n  class \u{212A},cafe\u{301} hot\n  classDef hot fill:#0f0",
            "agentflow-beta LR\n  a[\"😀 x\"] --> b[\"\u{2028}y\"]\n  b -- \"😀\u{2029}\" --> c\n  c@{ label: \"t\u{2028}\n  u\" }",
            "agentflow-beta\n  e1@-->x\n  a e1@--> b\n  a --> b\n  L_a_b_0@{ curve: linear }\n  class L_a_b_2 hot",
            "agentflow-beta\n  %%{init: {\"theme\": \"forest\"} }%%  😀 --> b\n  a\u{00A0}--> b",
            "agentflow-beta\n  a[\"\u{301}x\"] --> b[\"x\u{301}\"]\n  a -- \"\u{301}\" --> c",
            "agentflow-beta\n  classDef a\u{301},b fill:#f00\\,x;color:red\n  class n a\u{301}\n  n[N]",
            "agentflow-beta\n  accDescr {\n    one\n  \u{3000}two\n  }\n  accTitle: t\u{00A0}",
            "agentflow-beta\n  n1@{ shape: T\u{301}ool }\n  n2@{ shape: \u{212A} }",
        ]
        XCTAssertEqual(Self.assertReadAlike(sources), sources.count)
    }

    /// Names the grammar reads and Swift holds equal though their bytes differ (the Kelvin sign and `K`, the Angstrom
    /// sign and `Å`, a Greek letter with oxia and with tonos, a Hangul syllable and its jamo) are one node, one flow, one
    /// class, one connector, one global node, one edge identifier and one made edge identifier (`L_start_end_n`), as
    /// 0.7.0's String keys made them. The grammar refuses an identifier that starts beyond ASCII or holds a combining
    /// mark, so the texts above that write them are refused alike and name nothing; each of these is read by the
    /// reference, and with its names compared by their bytes the reader would make two of each.
    func testNamesSwiftHoldsEqualThatTheGrammarReadsAreOneName() throws {
        let sources = [
            "agentflow-beta\n  x\u{212A} --> xK\n  xK@{ shape: tool }\n  x\u{212A}[Kelvin]\n  a\u{212B} --> a\u{C5}\n  g\u{1F71} --> g\u{3AC}\n"
                + "  h\u{D55C} --> h\u{1112}\u{1161}\u{11AB}",
            "agentflow-beta\n  flow f\u{212A}[Flow]\n    a\u{212A} --> aK\n  end\n  flow fK\n    b\n  end\n  style aK fill:#f00\n  class a\u{212A},b hot\u{212A}\n"
                + "  classDef hotK fill:#0f0\n  classDef hot\u{212A} color:red",
            "agentflow-beta\n  a x\u{212A}1@--> b\n  xK1@{ curve: linear }\n  a xK1@--> c",
            "agentflow-beta\n  x\u{212A} --> y\n  L_xK_y_0@{ curve: linear }\n  class L_x\u{212A}_y_0 hot\n  xK --> y\n  L_xK_y_2@{ curve: basis }\n  classDef hot fill:#f00",
            "agentflow-beta\n  connector c\u{212A}[\"C\"]\n  cK --> d\u{212A}\n  global\n    dK\n  end\n  flow f\n    d\u{212A} --> q\n  end",
            "agentflow-beta\n  click n\u{212A} href \"u\" \"tip\"\n  nK[N]",
            "agentflow-beta\n  a\u{D55C} e\u{1112}\u{1161}\u{11AB}@--> b\n  e\u{D55C}@{ curve: linear }",
        ]
        let read = try sources.map { source in try XCTUnwrap(try ReferenceAgentFlowReading.read(source, limits: .standard), source) }
        // The reference makes one of each pair: four nodes of eight spellings, one flow and one class of two each, one
        // edge for the two identifiers that name it.
        XCTAssertEqual(read[0].vertices.count, 4)
        XCTAssertEqual(read[1].flows.count, 1)
        XCTAssertEqual(read[1].classDefinitions.count, 1)
        XCTAssertEqual(read[3].edges.compactMap(\.interpolation), ["linear", "basis"])
        XCTAssertEqual(Self.assertReadAlike(sources), sources.count)
        XCTAssertEqual(Self.assertReadAlike(sources.map { source in source.replacingOccurrences(of: "\n", with: "\r\n") }), sources.count)
    }

    /// Statements few corpus inputs write: long and split arrows, link styles by index and by default, clicks of every
    /// form, properties, connectors written again and over a node, `global` blocks, flows written again, collapsed flows
    /// inside collapsed flows, flows that hold each other, removed and unknown shapes, metadata on flows, edges and
    /// connectors, and errors of each kind.
    func testRareStatementsAreReadAlike() {
        let sources = [
            "agentflow-beta\n  a ---------------> b\n  a --x g\n  a --- h\n  a -------x i",
            "agentflow-beta\n  a -.........- c",
            "agentflow-beta\n  a -- t --> d",
            "agentflow-beta\n  a --> b\n  b --> c\n  linkStyle 0,1 stroke:red,stroke-width:2px\n  linkStyle default interpolate basis fill:#fff\n  linkStyle 1 interpolate linear",
            "agentflow-beta\n  a\n  b\n  c\n  d\n  click a href \"https://x\" _blank\n  click b \"u\" \"tip\" _self\n  click c call f(x) \"tip\"\n  click d cb \"tip\"\n  click a,b href \"v\"",
            "agentflow-beta\n  a[|field:one|Text] --> b[|k:x|T2]\n  a[|field:other|Text]",
            "agentflow-beta\n  a[A] --> b\n  connector a[\"Conn\"]@{ shape: tool }\n  connector a[\"Again\"]\n  connector b\n  a@{ shape: input }",
            "agentflow-beta\n  flow f\n    a --> b\n    global\n      a\n    end\n  end\n  flow g\n    a --> c\n  end\n  global\n    c\n  end",
            "agentflow-beta\n  flow f[One]\n    a\n  end\n  flow f[Two]\n    direction LR\n    b\n  end\n  flow\n    c\n  end",
            "agentflow-beta\n  flow outer@{ view: collapsed }\n    flow inner@{ view: collapsed }\n      x --> y\n    end\n    z --> x\n  end\n  z --> w\n  y --> w",
            "agentflow-beta\n  flow a\n    b\n  end\n  flow b\n    a\n  end\n  a --> b",
            "agentflow-beta\n  a([Stadium]) --> b[(Cylinder)] --> c((Circle)) --> d>Odd] --> e{{Hex}} --> f[/Lean/] --> g[\\Lean\\]",

            "agentflow-beta\n  a@{ label: \"L\", labelType: string }\n  b@{ label: 12, labelType: other }\n  c@{ label: \"\" }",
            "agentflow-beta\n  a --> b\n  a e1@-.- c\n  e1@{ curve: 1.50 }\n  L_a_b_0@{ curve: true }\n  flow f@{ view: collapsed, color: x }\n    q\n  end\n  f@{ view: open }",
            "agentflow-beta\n  b@{\n    label: \"multi\n    line\"\n  }\n  c@{\n    shape: tool\n    label: x\n  }",
            "agentflow-beta\n  a@{ shape: tool, shape: input }\n  b@{ __proto__: x }\n  c@{ - 1\n - 2 }",
            "agentflow-beta\n  a@{ : : }",
            "agentflow-beta\n  style a fill:#f00,color:#fff\n  classDef c1,c2 fill:#00f,stroke:#000;color:red\n  class a,b c1\n  a:::c2 --> b",
            "agentflow-beta\n  accTitle: Title\n  accDescr: Description\n  a --> b",
            "agentflow-beta\n  connectors --> a\n  connectors@{ shape: tool }",
            "agentflow-beta\n  a & b & c --> d & e\n  a & a --> b\n  b e1@--> x",
            "agentflow-beta >\n  a",
            "agentflow-beta v\n  a",
            "agentflow-beta\n  direction RL\n  a --> b",
        ]
        for source in sources { XCTAssertNoThrow(try ReferenceAgentFlowReading.read(source, limits: .standard), source) }
        XCTAssertEqual(Self.assertReadAlike(sources), sources.count)
        let refused = [
            "agentflow-beta\n  a --> b\n  linkStyle 3 stroke:red", "agentflow-beta\n  a --> b\n  linkStyle 99999999999999999999999 stroke:red",
            "agentflow-beta\n  a@{ shape: notAShape }", "agentflow-beta\n  a@{ shape: Tool }", "agentflow-beta\n  a@{ shape: lean_right }",
            "agentflow-beta\n  a@{ shape: 1 }", "agentflow-beta\n  a@{ shape: [x] }", "agentflow-beta\n  a@{ shape: tool\n  label: x, }",
            "agentflow-beta\n  a@{ shape: \"a: b\" : c }", "agentflow-beta\n  a -->", "agentflow-beta\n  flow f\n    a", "agentflow-beta\n  a[unclosed",
            "agentflow-beta\n  a --> b ^", "agentflow-beta\n  a == t --> f", "agentflow-beta\n  e1@--> x", "agentflow-beta\n  a -. t --> e",
            "agentflow-beta\n  c@{\n    shape: tool,\n    label: x,\n  }",
        ]
        for source in refused { XCTAssertThrowsError(try ReferenceAgentFlowReading.read(source, limits: .standard), source) }
        XCTAssertEqual(Self.assertReadAlike(refused), refused.count)
    }

    func testLimitsRefuseAlike() throws {
        let source = AgentFlowCorpus.generated(flowCount: 6, nodesPerFlow: 8)
        let standard = MermaidDiagramLimits.standard
        for (nodes, edges, bytes) in [(5, 500, standard.maximumSourceBytes), (500, 7, standard.maximumSourceBytes), (54, 500, standard.maximumSourceBytes),
                                      (500, 500, 100)] {
            let limits = MermaidDiagramLimits(maximumSourceBytes: bytes, maximumNodeCount: nodes, maximumEdgeCount: edges,
                                              maximumLayoutPointCount: standard.maximumLayoutPointCount)
            XCTAssertEqual(Self.assertReadAlike([source], limits: limits), 1)
        }
    }

    /// The reference inputs and texts made to be hard, read alike; a text ten times as long read in at most forty times
    /// the time.
    func testHostileTextsAreReadAlikeInTimeThatGrowsWithTheirLength() {
        let limits = MermaidDiagramLimits(maximumSourceBytes: 10_000_000, maximumNodeCount: 100_000, maximumEdgeCount: 100_000, maximumLayoutPointCount: 1_000_000)
        let small = AgentFlowHostileReadingTexts.all(count: 300)
        let large = AgentFlowHostileReadingTexts.all(count: 3_000)
        XCTAssertEqual(Self.assertReadAlike(AgentFlowHostileTexts.all + small + large, limits: limits), AgentFlowHostileTexts.all.count + small.count + large.count)
        func seconds(_ sources: [String]) -> Double {
            let start = Date()
            for source in sources { _ = try? MermaidDiagramReader.read(source, limits: limits) }
            return Date().timeIntervalSince(start)
        }
        _ = seconds(small)
        XCTAssertLessThan(seconds(large), max(seconds(small), 0.005) * 40)
    }

    /// The same texts read on twelve threads at once give what one thread gives.
    func testReadingsOnManyThreadsAtOnceAreAlike() throws {
        var mutations = GraphTextMutations(seed: 43)
        let originals = try Self.originals()
        let sources = (0..<400).map { round in mutations.mutated(originals[round % originals.count], pieces: Self.pieces) }
        let expected = sources.map { source in try? MermaidDiagramReader.read(source, limits: .standard) }
        let mismatches = ThreadSafeCount()
        DispatchQueue.concurrentPerform(iterations: 12) { _ in
            for (index, source) in sources.enumerated() where (try? MermaidDiagramReader.read(source, limits: .standard)) != expected[index] {
                mismatches.add()
            }
        }
        XCTAssertEqual(mismatches.value, 0)
    }

    /// Every agent flow of the corpora, Pele's reference inputs and its documentation examples.
    static func originals() throws -> [String] {
        let entries = try XCTUnwrap(JSONSerialization.jsonObject(with: AgentFlowCorpus.referenceData()) as? [[String: Any]])
        let references = entries.compactMap { entry in entry["src"] as? String }
        let corpora = try OutputDigest.corpora().flatMap(\.sources).filter { source in source.contains("agentflow") }
        return corpora + references + AgentFlowHostileTexts.all
    }

    /// Pieces the agent flow's lexer and grammar treat apart, with the graph readers' common ones.
    static let pieces = GraphTextMutations.commonPieces + [
        "-->", "--x", "-.-", "---", "-.->", "-- t -->", "--|t|", "@{", "@{ shape: tool }", "@{ shape: input, label: \"L\" }", "@{ view: collapsed }",
        "@{\n  shape: task\n}", "@{ curve: linear }", "flow ", "flow f[\"T\"]\n", "global\n", "connector c[\"C\"]\n", "end\n", "classDef hot fill:#f00\n",
        "class a hot\n", ":::hot", "style a fill:#0f0\n", "linkStyle 0 stroke:red\n", "linkStyle default interpolate basis\n", "click a href \"u\"\n",
        "click a call f()\n", "accDescr {\n x\n}\n", "e1@", "&", " & ", "((", "))", "{{", "}}", "[/", "\\]", "/]", "[\\", "(-", "-)", "([", "])", "[[", "]]",
        "[(", ")]", "[|f:v|", "\"`", "`\"", "%%{init: {}}%%", "L_a_b_0", "subGraph0", "connectors", "😀", "\u{2028}", "\u{2029}", "\u{301}",
        "TB", "LR", "<", "^", "v",
    ]

    /// Reads each source both ways and fails for each that differs; returns how many the reference read as an agent flow,
    /// or refused while reading one.
    @discardableResult
    static func assertReadAlike(_ sources: [String], limits: MermaidDiagramLimits = .standard, file: StaticString = #filePath, line: UInt = #line) -> Int {
        var checked = 0
        var mismatches = 0
        for source in sources {
            let reference = Result { () throws(MermaidDiagramReadError) in try ReferenceAgentFlowReading.read(source, limits: limits) }
            let package = Result { () throws(MermaidDiagramReadError) in try MermaidDiagramReader.read(source, limits: limits) }
            var difference: String?
            switch (reference, package) {
            case (.success(nil), _): continue
            case (.success(let expected?), .success(.agentFlow(let read))): difference = Self.difference(read, expected)
            case (.failure(let expected), .failure(let error)):
                if expected != error { difference = "error \(error) where the reference throws \(expected)" }
            case (.failure(let expected), .success): difference = "read where the reference throws \(expected)"
            case (.success, .failure(let error)): difference = "throws \(error) where the reference reads"
            case (.success, .success): difference = "read as another type"
            }
            checked += 1
            if let difference {
                mismatches += 1
                if mismatches <= 5 { XCTFail("\(difference):\n\(source.prefix(600).debugDescription)", file: file, line: line) }
            }
        }
        XCTAssertEqual(mismatches, 0, file: file, line: line)
        return checked
    }

    /// The first list or field in which the model read differs from the reference's, or nil.
    static func difference(_ read: AgentFlowDiagram, _ expected: ReferenceAgentFlowDiagram) -> String? {
        let fields: [(String, Bool)] = [
            ("direction", read.directionKeyword == expected.directionKeyword), ("vertices", read.vertices == expected.vertices),
            ("edges", read.edges == expected.edges), ("flows", read.flows == expected.flows),
            ("connectors", read.connectorIdentifiers == expected.connectorIdentifiers), ("classes", read.classDefinitions == expected.classDefinitions),
            ("default edge style", read.defaultEdgeStyle == expected.defaultEdgeStyle),
            ("default interpolation", read.defaultInterpolation == expected.defaultInterpolation), ("mappings", read.mappings == expected.mappings),
            ("diagnostics", read.diagnostics == expected.diagnostics), ("graph nodes", read.graph.nodes == expected.graph.nodes),
            ("graph edges", read.graph.edges == expected.graph.edges), ("title", read.title == expected.title),
            ("accessibility", read.accessibilityTitle == expected.accessibilityTitle && read.accessibilityDescription == expected.accessibilityDescription),
            ("options", read.options == expected.options),
        ]
        return fields.first { _, isAlike in !isAlike }.map { name, _ in "the \(name) differ" }
    }
}

/// Agent flows made to be hard for a reader, `count` of each thing: long lines, many nodes whose names share all but
/// their last bytes, deep and repeated flows, many edges between the same two nodes, many metadata blocks, class lists
/// and link styles, and many edges an `&` group makes.
enum AgentFlowHostileReadingTexts {
    static func all(count: Int) -> [String] {
        let prefix = String(repeating: "n", count: 40)
        let names = (0..<count).map { index in "\(prefix)\(index)" }
        return [
            "agentflow-beta\n" + names.enumerated().map { index, name in "  \(name) --> \(names[(index * 7) % count])" }.joined(separator: "\n"),
            "agentflow-beta\n  a[" + String(repeating: "word ", count: count * 4) + "] --> b",
            "agentflow-beta\n" + (0..<min(count, 400)).map { index in String(repeating: " ", count: index) + "flow f\(index)" }.joined(separator: "\n")
                + "\n  x --> y\n" + String(repeating: "end\n", count: min(count, 400)),
            "agentflow-beta\n" + (0..<count).map { _ in "  a --> b" }.joined(separator: "\n"),
            "agentflow-beta\n" + (0..<count).map { index in "  n\(index)@{ shape: \(index.isMultiple(of: 2) ? "tool" : "stadium"), label: \"L\(index)\" }" }.joined(separator: "\n"),
            "agentflow-beta\n  classDef hot fill:#f00\n" + (0..<count).map { index in "  n\(index) --> m\(index)\n  class n\(index),m\(index) hot" }.joined(separator: "\n")
                + "\n" + (0..<min(count, 500)).map { index in "  linkStyle \(index) stroke:red" }.joined(separator: "\n"),
            "agentflow-beta\n  " + (0..<min(count, 200)).map { index in "a\(index)" }.joined(separator: " & ") + " --> "
                + (0..<min(count, 200)).map { index in "b\(index)" }.joined(separator: " & "),
            "agentflow-beta\n" + (0..<count).map { index in "  flow g\(index % 20)\n    k\(index)\n  end" }.joined(separator: "\n"),
        ]
    }
}
