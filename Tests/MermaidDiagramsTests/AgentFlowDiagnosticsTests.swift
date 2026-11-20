/**
 * File: AgentFlowDiagnosticsTests.swift
 * -------------------------------------
 * Layer: Tests
 * Description: The diagnostics, refusals, element positions and limits of agent flows, from the inputs of Mermaid's
 *              agentflow specs and fixtures as Pele ports them (diagnostics, shape catalogue, mappings, blank-line
 *              fold, upstream fixtures) and Pele's own render and stress tests.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class AgentFlowDiagnosticsTests: XCTestCase {
    private typealias Reading = AgentFlowReading

    func testRemovedAndUnsupportedShapesFallBackWithTheirDiagnostics() throws {
        let removed = try Reading.diagram("%% removed\nagentflow-beta TB\n  input[\"q\"]\n  input@{ shape: input }\n  store[\"Store\"]\n  store@{ shape: \"cylinder\" }\n  input --> store")
        XCTAssertEqual(removed.diagnostics.map { diagnostic in [diagnostic.identifier.rawValue, diagnostic.nodeIdentifier ?? ""] }, [["SHAPE_REMOVED", "store"]])
        XCTAssertEqual(removed.diagnostics.first?.severity, .error)
        XCTAssertEqual(removed.diagnostics.first?.position?.startLine, 5)
        XCTAssertEqual(Reading.node("store", in: removed)?.shape, "roundedRect")
        let unsupported = try Reading.diagram("agentflow-beta TB\n  a[\"A\"]@{ shape: tri }")
        XCTAssertEqual(unsupported.diagnostics.map(\.identifier), [.shapeUnsupported])
        XCTAssertEqual(unsupported.diagnostics.first?.message, "shape \"tri\" is not supported, using \"roundedRect\"")
        XCTAssertEqual(unsupported.diagnostics.first?.severity, .warning)
        for (written, shape) in [("a([\"A\"])", "stadium"), ("a((\"A\"))", "circle"), ("a[(\"A\")]", "cylinder"), ("a>\"A\"]", "odd")] {
            let diagram = try Reading.diagram("agentflow-beta TB\n  \(written)")
            XCTAssertEqual(diagram.diagnostics.map(\.message), ["shape \"\(shape)\" was removed in v0.8.1, using \"roundedRect\""], written)
        }
        let allowed = try Reading.diagram("agentflow-beta TB\n  a[[\"T\"]]\n  b{{\"H\"}}\n  c{\"D\"}\n  d[\"I\"]@{ shape: input }")
        XCTAssertEqual(allowed.diagnostics, [])
        XCTAssertEqual(allowed.graph.nodes.map(\.shape), ["subroutine", "hexagon", "diamond", "lean-right"])
        // The bracket form of an input leans as `lean_right`, a name the agent flow does not take.
        XCTAssertEqual(try Reading.diagram("agentflow-beta TB\n  d[/\"I\"/]").diagnostics.map(\.message),
                       ["shape \"lean_right\" is not supported, using \"roundedRect\""])
        XCTAssertTrue(AgentFlowDiagnostic.Identifier.allCases.filter(\.isEmitted).map(\.rawValue).elementsEqual(
            ["SHAPE_UNSUPPORTED", "SHAPE_REMOVED", "CONTAINMENT_VIOLATION"]))
    }

    func testShapeNamesMermaidRefusesAndBrokenMetadataAreErrorsOnTheirLines() {
        XCTAssertEqual(Reading.readError("agentflow-beta TB\n  a[\"A\"]\n  a@{ shape: Tool }"), .invalidSyntax(line: 3, problem: .agentFlow(.shapeNameNotLowercase("Tool"))))
        XCTAssertEqual(Reading.readError("agentflow-beta TB\n  a@{ shape: lean_right }"), .invalidSyntax(line: 2, problem: .agentFlow(.shapeNameNotLowercase("lean_right"))))
        XCTAssertEqual(Reading.problem("agentflow-beta TB\n  a@{ shape: nothing-like-it }"), .unknownShape("nothing-like-it"))
        XCTAssertEqual(Reading.problem("agentflow-beta TB\n  a@{ shape: 5 }"), .unknownShape("5"))
        XCTAssertEqual(Reading.readError("agentflow-beta TB\n  a --> b\n  a@{ key: [unclosed }"), .invalidSyntax(line: 3, problem: .agentFlow(.metadataNotYAML(identifier: "a"))))
        XCTAssertEqual(Reading.readError("---\ntitle: T\n---\nagentflow-beta TB\n  a --> b\n  linkStyle 3 stroke:red"),
                       .invalidSyntax(line: 6, problem: .agentFlow(.linkStyleIndexOutOfBounds(index: "3", edgeCount: 1))))
    }

    func testSyntaxErrorsNameJisonsTokensOnTheLineTheyBreak() {
        // Pele's upstream fixture: a flow with no `end`.
        XCTAssertEqual(Reading.readError("%% no end\nagentflow-beta TB\n  flow orphan[\"Orphan\"]\n    a[\"Alpha\"]\n    a --> b\n"),
                       .invalidSyntax(line: 5, problem: .agentFlow(.unexpectedToken(found: "$end", expected: "'end'"))))
        XCTAssertEqual(Reading.readError("agentflow-beta TB\n  a[\"A\"]@{ shape: rounded }\n\n  b[\"B\"]@{ shape: rounded }\n\n  c[\"C\"]\"]\n"),
                       .invalidSyntax(line: 6, problem: .agentFlow(.unexpectedToken(found: "STR", expected: "'COMMENT', 'SEMI', 'NEWLINE', 'EOF'"))))
        XCTAssertEqual(Reading.problem("agentflow-beta TB\n  a ~ b"), .unrecognizedText)
        XCTAssertEqual(Reading.problem("agentflow-beta XX\n  a"), .unrecognizedText)
        XCTAssertNil(Reading.readError("agentflow-beta TB\n  a[\"A\"]@{ shape: rounded }   \n\n  b[\"B\"]"))
    }

    func testElementPositionsCountTheFrontMatterAndSpanTheirStatements() throws {
        let plain = try Reading.diagram("agentflow-beta TB\n  a[\"Alpha\"] --> b\n  flow pipeline[\"P\"]\n    c\n  end")
        XCTAssertEqual(plain.mappings.map { mapping in [mapping.identifier, mapping.kind.rawValue] },
                       [["a", "vertex"], ["b", "vertex"], ["b", "edge"], ["c", "vertex"], ["pipeline", "subgraph"]])
        XCTAssertEqual(plain.mappings[0].position, AgentFlowElementPosition(startLine: 2, startColumn: 2, endLine: 2, endColumn: 12))
        let flow = try XCTUnwrap(plain.mappings.last)
        XCTAssertEqual([flow.position.startLine, flow.position.endLine], [3, 5])
        let shifted = try Reading.diagram("---\ntitle: T\n---\nagentflow-beta TB\n  a[\"Alpha\"]")
        XCTAssertEqual(shifted.mappings.first?.position.startLine, 5)
        XCTAssertEqual(shifted.title, "T")
        let folded = try Reading.diagram("agentflow-beta\nflow f[\"F\"]\n  a[\"A\"]@{ shape: rounded }\n\n\n  b[\"B\"]\nend")
        XCTAssertEqual(folded.mappings.first { mapping in mapping.identifier == "b" }?.position.startLine, 6)
        let attached = try Reading.diagram("agentflow-beta TB\n  a\n  a@{ description: \"x\" }")
        XCTAssertEqual(attached.mappings.map(\.kind), [.vertex, .attachment])
    }

    func testCountsPastTheLimitsAreRefusedBeforeAnythingIsMade() {
        var limits = MermaidDiagramLimits.standard
        limits.maximumNodeCount = 10
        limits.maximumEdgeCount = 10
        XCTAssertEqual(Reading.readError("agentflow-beta TB\n" + (0..<11).map { node in "  n\(node)\n" }.joined(), limits: limits), .tooManyNodes(limit: 10))
        XCTAssertEqual(Reading.readError("agentflow-beta TB\n" + (0..<11).map { flow in "  flow f\(flow)\n  end\n" }.joined(), limits: limits),
                       .tooManyNodes(limit: 10))
        XCTAssertEqual(Reading.readError("agentflow-beta TB\n  a & b & c & d --> e & f & g", limits: limits), .tooManyEdges(limit: 10))
    }

    func testPelesStressCasesAreReadAndLaidOutQuickly() throws {
        let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))
        let chain = "agentflow-beta LR\n" + (0..<2_000).map { node in "  n\(node) --> n\(node + 1)\n" }.joined()
        let fan = "agentflow-beta TB\n  a --> " + (0..<1_500).map { node in "b\(node)" }.joined(separator: " & ") + "\n"
        let nested = "agentflow-beta TB\n" + (0..<1_000).map { level in "flow f\(level)\n" }.joined() + "a --> b\n" + String(repeating: "end\n", count: 1_000)
        let metadata = "agentflow-beta TB\n" + (0..<600).map { node in "  n\(node)@{ shape: tool, label: \"Tool \(node)\" }\n" }.joined()
        for source in [chain, fan, nested, metadata] {
            XCTAssertLessThanOrEqual(source.utf8.count, MermaidDiagramLimits.standard.maximumSourceBytes)
            let start = Date()
            let diagram = try Reading.diagram(source)
            _ = try? AgentFlowLayoutEngine.layout(diagram, typography: typography)
            XCTAssertLessThan(Date().timeIntervalSince(start), 20, String(source.prefix(40)))
        }
    }
}
