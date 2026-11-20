/**
 * File: AgentFlowParserTests.swift
 * --------------------------------
 * Layer: Tests
 * Description: The inputs of Mermaid 12.1.0's agentflow parser specs as Pele ports them (tests/compat/agentflow:
 *              agentflow, comments, global, flow self-reference, containment cycle, trailing commas): nodes, edges,
 *              flows, connectors, metadata and the graph drawn of them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class AgentFlowParserTests: XCTestCase {
    private typealias Reading = AgentFlowReading

    func testSmokeReadsEmptyDiagramsNodesEdgesLabelsAndDirections() throws {
        let empty = try Reading.diagram("agentflow-beta TB\n")
        XCTAssertTrue(empty.graph.nodes.isEmpty)
        XCTAssertTrue(empty.graph.edges.isEmpty)
        XCTAssertTrue(MermaidDiagram.agentFlow(empty).hasNothingToDraw)
        let two = try Reading.diagram("agentflow-beta TB\n  a[\"Alpha\"]\n  b[\"Beta\"]\n  a --> b")
        XCTAssertEqual(two.graph.nodes.count, 2)
        XCTAssertEqual(two.edges.map { edge in [edge.start, edge.end] }, [["a", "b"]])
        let labelled = try Reading.diagram("agentflow-beta TB\n  research[\"Research\"]\n  research --> write")
        XCTAssertEqual(Reading.vertex("research", in: labelled)?.text, "Research")
        XCTAssertEqual(try Reading.diagram("agentflow-beta LR\n  a --> b").directionKeyword, "LR")
        XCTAssertEqual(try Reading.diagram("agentflow-beta LR\n  a --> b").direction, .leftToRight)
        XCTAssertEqual(try Reading.diagram("agentflow-beta\n  a --> b").directionKeyword, "TB")
    }

    func testSelfLoopsAreKeptButLoopsMadeByCollapsingAreDropped() throws {
        let loop = try Reading.diagram("agentflow-beta TB\n  a[\"Alpha\"]\n  a --> a")
        XCTAssertEqual(loop.graph.edges.map { edge in [edge.start, edge.end] }, [["a", "a"]])
        let mixed = try Reading.diagram("agentflow-beta TB\n  a[\"Alpha\"]\n  b[\"Beta\"]\n  a --> b\n  b --> b")
        XCTAssertEqual(mixed.graph.edges.count, 2)
        let collapsed = try Reading.diagram("agentflow-beta TB\n  flow p[\"P\"]\n    a --> b\n  end\n  p@{ view: \"collapsed\" }")
        XCTAssertTrue(collapsed.graph.edges.isEmpty)
    }

    func testFlowsWithAndWithoutTitlesNestedAndAsGroupsOfTheGraph() throws {
        let titled = try Reading.diagram("agentflow-beta TB\n  flow pipeline[\"Pipeline\"]\n    a --> b\n  end")
        XCTAssertEqual(titled.flows.map(\.identifier), ["pipeline"])
        XCTAssertEqual(titled.flows.first?.title, "Pipeline")
        XCTAssertEqual(Reading.node("pipeline", in: titled)?.isGroup, true)
        XCTAssertEqual(try Reading.diagram("agentflow-beta TB\n  flow pipeline\n    a --> b\n  end").flows.map(\.identifier), ["pipeline"])
        let nested = try Reading.diagram("agentflow-beta TB\n  flow outer[\"Outer\"]\n    flow inner[\"Inner\"]\n      a --> b\n    end\n  end")
        XCTAssertEqual(nested.flows.map(\.identifier), ["inner", "outer"])
        XCTAssertEqual(Reading.node("inner", in: nested)?.parentIdentifier, "outer")
        XCTAssertEqual(Reading.node("a", in: nested)?.parentIdentifier, "inner")
    }

    func testTheThreeEdgeOperatorsAndTheirMeanings() throws {
        let point = try XCTUnwrap(try Reading.diagram("agentflow-beta TB\n  a --> b").edges.first)
        XCTAssertEqual([point.type, point.stroke], ["arrow_point", "normal"])
        XCTAssertEqual(point.semantic, .sequence)
        let cross = try XCTUnwrap(try Reading.diagram("agentflow-beta TB\n  a --x b").edges.first)
        XCTAssertEqual(cross.type, "arrow_cross")
        XCTAssertEqual(cross.semantic, .failure)
        let dotted = try XCTUnwrap(try Reading.diagram("agentflow-beta TB\n  a -.- b").edges.first)
        XCTAssertEqual(dotted.stroke, "dotted")
        XCTAssertEqual(dotted.semantic, .reference)
        XCTAssertEqual(try Reading.diagram("agentflow-beta TB\n  a -- yes --> b").edges.first?.text, "yes")
        XCTAssertEqual(try Reading.diagram("agentflow-beta TB\n  a -->|yes| b").edges.first?.text, "yes")
        // The lexer reads text only after `--`: a dotted link split around its text is refused, as in Pele.
        XCTAssertEqual(Reading.problem("agentflow-beta TB\n  a -. no --> b"),
                       .unexpectedToken(found: "MINUS", expected: "'COMMENT', 'SEMI', 'NEWLINE', 'EOF'"))
    }

    func testShapeAliasesGiveEachNodeItsKind() throws {
        let tool = try Reading.diagram("agentflow-beta TB\n  s[\"Search\"]\n  s@{ shape: tool, returns: \"Result\" }")
        XCTAssertEqual(Reading.kind("s", in: tool), .tool)
        XCTAssertEqual(Reading.vertex("s", in: tool)?.type, "subroutine")
        XCTAssertEqual(Reading.metadata("returns", of: Reading.vertex("s", in: tool)), "Result")
        for (shape, kind) in [("action", AgentFlowVertexKind.action), ("input", .input), ("refdoc", .refdoc), ("decision", .decision), ("task", .task)] {
            let diagram = try Reading.diagram("agentflow-beta TB\n  a[\"A\"]\n  a@{ shape: \(shape) }")
            XCTAssertEqual(Reading.kind("a", in: diagram), kind, shape)
            XCTAssertEqual(Reading.node("a", in: diagram)?.kind, kind, shape)
        }
        XCTAssertEqual(Reading.kind("d", in: try Reading.diagram("agentflow-beta TB\n  d{\"is_valid?\"}")), .decision)
    }

    func testConnectorsWithInlineAndLaterMetadata() throws {
        let one = try Reading.diagram("agentflow-beta TB\n  connector github[\"GitHub\"]\n  github@{ protocol: \"mcp\", transport: \"stdio\" }")
        XCTAssertEqual(one.connectorIdentifiers, ["github"])
        XCTAssertEqual(Reading.metadata("protocol", of: Reading.vertex("github", in: one)), "mcp")
        XCTAssertEqual(Reading.node("github", in: one)?.kind, .connector)
        XCTAssertEqual(try Reading.diagram("agentflow-beta TB\n  connector github[\"GitHub\"]\n  connector slack[\"Slack\"]").connectorIdentifiers.sorted(),
                       ["github", "slack"])
        let inline = try Reading.diagram("agentflow-beta TB\n  connector github[\"GitHub\"]@{ protocol: \"mcp\", transport: \"stdio\" }")
        XCTAssertEqual(Reading.vertex("github", in: inline)?.text, "GitHub")
        XCTAssertEqual(Reading.metadata("transport", of: Reading.vertex("github", in: inline)), "stdio")
        let bare = try Reading.diagram("agentflow-beta TB\n  connector github@{ protocol: \"mcp\" }")
        XCTAssertEqual(Reading.metadata("protocol", of: Reading.vertex("github", in: bare)), "mcp")
        let merged = try Reading.diagram("agentflow-beta TB\n  connector github[\"GitHub\"]@{ protocol: \"mcp\" }\n  github@{ transport: \"stdio\" }")
        XCTAssertEqual(Reading.vertex("github", in: merged)?.metadataKeys, ["protocol", "transport"])
        let multiline = try Reading.diagram("agentflow-beta TB\n  connector github[\"GitHub\"]@{\n    protocol: \"mcp\"\n    transport: \"stdio\"\n  }\n  a --> b")
        XCTAssertEqual(Reading.metadata("transport", of: Reading.vertex("github", in: multiline)), "stdio")
    }

    func testFanOutMetadataAndViewHints() throws {
        XCTAssertEqual(try Reading.diagram("agentflow-beta TB\n  a --> b & c").edges.map(\.end).sorted(), ["b", "c"])
        let metadata = try Reading.diagram("agentflow-beta TB\n  a[\"A\"]\n  a@{ description: \"first\" }\n  a@{ instruction: \"second\" }")
        XCTAssertEqual(Reading.metadata("description", of: Reading.vertex("a", in: metadata)), "first")
        XCTAssertEqual(Reading.metadata("instruction", of: Reading.vertex("a", in: metadata)), "second")
        let flow = try Reading.diagram("agentflow-beta TB\n  flow pipeline[\"P\"]\n    a --> b\n  end\n  pipeline@{ model: \"claude-opus-4-6\", view: \"collapsed\" }")
        XCTAssertEqual(Reading.metadata("model", of: Reading.flow("pipeline", in: flow)), "claude-opus-4-6")
        XCTAssertEqual(Reading.flow("pipeline", in: flow)?.isCollapsed, true)
        XCTAssertEqual(Reading.node("pipeline", in: flow)?.shape, "collapsedGroup")
    }

    func testCommentsAroundTheHeaderBetweenStatementsAndInsideLabels() throws {
        for source in ["%% leading comment\nagentflow-beta TB\n  a --> b", "%% first\n%% second\nagentflow-beta TB\n  a --> b",
                       "agentflow-beta TB\n%% trailing header comment\n  a --> b", "agentflow-beta TB\n  a --> b\n%% trailing comment"] {
            XCTAssertEqual(try Reading.diagram(source).vertices.count, 2, source)
        }
        for source in ["agentflow-beta TB\n  a --> b\n%% mid\n  b --> c", "agentflow-beta TB\n  a --> b\n%%no-space\n  b --> c",
                       "agentflow-beta TB\n  a --> b\n%%\n  b --> c"] {
            XCTAssertEqual(try Reading.diagram(source).vertices.count, 3, source)
        }
        for opening in ["[Plain", "(-ellipse", "[/trap"] {
            let closing = opening == "[Plain" ? "]" : opening == "(-ellipse" ? "-)" : "/]"
            let diagram = try Reading.diagram("agentflow-beta TB\n  a\(opening) %% not part of the label\nlabel\(closing)\n  b --> a")
            let text = try XCTUnwrap(Reading.vertex("a", in: diagram)?.text)
            XCTAssertFalse(text.contains("%%") || text.contains("not part"), text)
            XCTAssertTrue(text.contains(String(opening.drop { character in !character.isLetter })), text)
        }
        XCTAssertEqual(try Reading.diagram("agentflow-beta TB\n%% before\nconnector github[\"GitHub\"]\n%% after\n  a --> b").vertices.count, 3)
    }

    func testGlobalBlocksKeepTheirNodesOutOfFlowsWhereverWritten() throws {
        let before = try Reading.diagram("agentflow-beta\n\nglobal\n  A\nend\n\nflow\n A --> B --> C\nend")
        XCTAssertEqual(before.flows.count, 1)
        XCTAssertEqual(before.flows[0].nodeIdentifiers.sorted(), ["B", "C"])
        XCTAssertNil(Reading.node("A", in: before)?.parentIdentifier)
        XCTAssertEqual(Reading.node("B", in: before)?.parentIdentifier, before.flows[0].identifier)
        XCTAssertEqual(before.graph.nodes.filter(\.isGroup).count, 1)
        let after = try Reading.diagram("agentflow-beta\n\nflow pipeline[\"Pipeline\"]\n  A --> B\nend\n\nglobal\n  A\nend")
        XCTAssertEqual(Reading.flow("pipeline", in: after)?.nodeIdentifiers, ["B"])
        let edges = try Reading.diagram("agentflow-beta\n\nglobal\n  A --> X\nend\n\nflow f[\"Flow\"]\n  A --> B\n  X --> B\nend")
        XCTAssertEqual(Reading.flow("f", in: edges)?.nodeIdentifiers, ["B"])
        let nested = try Reading.diagram("agentflow-beta\n\nflow f[\"Flow\"]\n  global\n    A\n  end\n  A --> B\nend")
        XCTAssertEqual(Reading.flow("f", in: nested)?.nodeIdentifiers, ["B"])
        let shaped = try Reading.diagram("agentflow-beta\n\nglobal\n  A[\"Shared input\"]\n  D{\"Decision\"}\nend\n\nflow f[\"Flow\"]\n  A --> B --> D\nend")
        XCTAssertEqual(Reading.node("A", in: shaped)?.label, "Shared input")
        XCTAssertEqual(Reading.node("D", in: shaped)?.shape, "diamond")
        XCTAssertNil(Reading.node("D", in: shaped)?.parentIdentifier)
    }

    func testAnEdgeToItsOwnFlowNeverMakesTheFlowItsOwnMember() throws {
        let own = try Reading.diagram("agentflow-beta TB\n  flow myFlow[\"My Flow\"]\n    a[\"Task A\"]\n    a --> myFlow\n  end")
        XCTAssertEqual(Reading.flow("myFlow", in: own)?.nodeIdentifiers, ["a"])
        XCTAssertNil(Reading.node("myFlow", in: own)?.parentIdentifier)
        XCTAssertEqual(Reading.node("a", in: own)?.parentIdentifier, "myFlow")
        XCTAssertTrue(own.graph.edges.contains { edge in edge.start == "a" && edge.end == "myFlow" })
        let three = try Reading.diagram("""
            agentflow-beta TB
              flow top["Top"]
                flow mid["Mid"]
                  flow leafFlow["Leaf"]
                    c["Task C"]
                  end
                  m["Task M"]
                  m --> mid
                end
              end
            """)
        XCTAssertEqual(["leafFlow", "mid", "top", "m", "c"].map { identifier in Reading.node(identifier, in: three)?.parentIdentifier },
                       ["mid", "top", nil, "mid", "leafFlow"])
    }

    func testFlowsThatHoldEachOtherDropTheNestingThatClosesTheLoop() throws {
        func mutual(_ first: String = "", _ second: String = "") -> String {
            "agentflow-beta TB\n  flow A[\"Flow A\"]\(first)\n    a1[\"Task A1\"]\n    a1 --> B\n  end\n  flow B[\"Flow B\"]\(second)\n    b1[\"Task B1\"]\n    b1 --> A\n  end"
        }
        let open = try Reading.diagram(mutual())
        XCTAssertEqual(["A", "B", "a1", "b1"].map { identifier in Reading.node(identifier, in: open)?.parentIdentifier }, ["B", nil, "A", "B"])
        let violation = try XCTUnwrap(open.diagnostics.first { diagnostic in diagnostic.identifier == .containmentViolation })
        XCTAssertEqual(violation.nodeIdentifier, "B")
        XCTAssertEqual(violation.severity, .warning)
        let collapsed = try Reading.diagram(mutual("@{ view: collapsed }"))
        XCTAssertEqual(Reading.node("A", in: collapsed)?.shape, "collapsedGroup")
        XCTAssertNil(Reading.node("A", in: collapsed)?.parentIdentifier)
        XCTAssertFalse(try Reading.diagram(mutual("@{ view: collapsed }", "@{ view: collapsed }")).graph.nodes.isEmpty)
        let triangle = "agentflow-beta TB\n  flow A[\"A\"]@{ view: collapsed }\n    a1[\"a1\"]\n    a1 --> B\n  end\n  flow B[\"B\"]\n    b1[\"b1\"]\n"
            + "    b1 --> C\n  end\n  flow C[\"C\"]\n    c1[\"c1\"]\n    c1 --> A\n  end"
        XCTAssertNoThrow(try AgentFlowLayoutEngine.layout(try Reading.diagram(triangle), typography: DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))))
    }

    func testMetadataOverSeveralLinesWithTrailingCommas() throws {
        let connector = try Reading.diagram("agentflow-beta TB\n  connector github[\"GitHub\"]@{\n    protocol: \"mcp\",\n    endpoint: \"https://api.github.com\"\n    token_required: true,\n  }")
        let vertex = Reading.vertex("github", in: connector)
        XCTAssertEqual([Reading.metadata("protocol", of: vertex), Reading.metadata("endpoint", of: vertex), Reading.metadata("token_required", of: vertex)],
                       ["mcp", "https://api.github.com", "true"])
        let comment = try Reading.diagram("agentflow-beta TB\n  connector github[\"GitHub\"]@{\n    protocol: \"mcp\", # main protocol\n    transport: \"stdio\"\n  }")
        XCTAssertEqual(Reading.metadata("protocol", of: Reading.vertex("github", in: comment)), "mcp")
        let block = try Reading.diagram("agentflow-beta TB\n  a[\"Alpha\"]\n  a@{\n    instruction: |\n      Do a thing,\n      then stop\n    protocol: \"mcp\",\n  }")
        XCTAssertEqual(Reading.metadata("instruction", of: Reading.vertex("a", in: block)), "Do a thing,\nthen stop\n")
        let list = try Reading.diagram("agentflow-beta TB\n  a[\"Alpha\"]\n  a@{\n    tools: [\"read\",\n      \"write\"],\n    protocol: \"mcp\"\n  }")
        XCTAssertEqual(Reading.metadata("tools", of: Reading.vertex("a", in: list)), "read,write")
        let flow = try Reading.diagram("agentflow-beta TB\n  flow f[\"Flow\"]@{\n    model: \"claude-opus-4\",\n    memory: \"shared\",\n  }\n    a --> b\n  end")
        XCTAssertEqual(Reading.metadata("memory", of: Reading.flow("f", in: flow)), "shared")
    }
}
