/**
 * File: AgentFlowBenchmark.swift
 * ------------------------------
 * Layer: Benchmark
 * Description: Times reading, laying out and painting agent flows on their documentation examples and generated
 *              flows, with the memory a layout holds.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics
import MermaidDiagrams

/// Times reading, laying out and painting agent flows on `AgentFlowCorpus`, with the median and the 99th percentile per
/// diagram, and the memory a layout holds, as the other types' benchmarks do.
enum AgentFlowBenchmark {
    static func run(typography: DiagramTypography) throws {
        let cases: [(name: String, sources: [String])] = [
            ("agentflow documentation examples", try AgentFlowCorpus.documentationExamples()),
            ("agentflow, 6 flows of 8 nodes", [AgentFlowCorpus.generated(flowCount: 6, nodesPerFlow: 8)]),
            ("agentflow, 40 flows of 20 nodes", [AgentFlowCorpus.generated(flowCount: 40, nodesPerFlow: 20)]),
        ]
        for (name, sources) in cases { try report(name, sources: sources, typography: typography) }
        let generated = try read(AgentFlowCorpus.generated(flowCount: 6, nodesPerFlow: 8))
        let bytes = BenchmarkHeap.growth { _ = try? AgentFlowLayoutEngine.layout(generated, typography: typography) }
        print("memory of one laid-out agent flow, 6 flows of 8 nodes: \(bytes) bytes")
    }

    private static func report(_ name: String, sources: [String], typography: DiagramTypography) throws {
        let diagrams = try sources.map(read)
        let layouts = try diagrams.map { diagram in try AgentFlowLayoutEngine.layout(diagram, typography: typography) }
        let count = sources.count
        let measure = MermaidDiagramsBenchmark.measure
        let reading = measure(count) { for source in sources { _ = try? read(source) } }
        let layingOut = measure(count) { for diagram in diagrams { _ = try? AgentFlowLayoutEngine.layout(diagram, typography: typography) } }
        let scenes = layouts.map(DiagramScene.init(layout:))
        let sceneMaking = measure(count) { for layout in layouts { _ = DiagramScene(layout: layout) } }
        let contexts = scenes.map { scene in MermaidDiagramsBenchmark.bitmapContext(size: scene.size) }
        let painting = measure(count) {
            for (scene, context) in zip(scenes, contexts) {
                if let context { DiagramSceneRenderer.draw(scene, in: context, palette: MermaidDiagramsBenchmark.palette) }
            }
        }
        print("\(name): read \(reading); layout \(layingOut); scene \(sceneMaking); painting \(painting)")
    }

    private static func read(_ source: String) throws -> AgentFlowDiagram {
        guard case .agentFlow(let diagram) = try MermaidDiagramReader.read(source, limits: .standard) else { throw NotAnAgentFlow() }
        return diagram
    }

    /// A text of the agent flow corpus that reads as another type.
    struct NotAnAgentFlow: Error {}
}
