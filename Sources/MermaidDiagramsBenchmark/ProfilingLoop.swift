/**
 * File: ProfilingLoop.swift
 * -------------------------
 * Layer: Benchmark
 * Description: Repeats the reading and layout, the whole preparation or the painting of one of the Pele comparison's
 *              cases for a few seconds, so that a sampler (sample, Instruments' Time Profiler) sees only that work.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import CoreGraphics
import Foundation
import MermaidDiagrams

/// `--profile <case> [reading|preparation|painting] [seconds]`: the case is a name of Pele's benchmark (`tree: 500
/// nodes`) or a documentation corpus (`treemap-docs`); the work repeats until the seconds (5 by default) are spent,
/// then prints how many rounds it made.
enum ProfilingLoop {
    enum Work: String {
        case reading
        case preparation
        case painting
    }

    static func run(arguments: [String], typography: DiagramTypography) throws {
        guard let caseName = arguments.first else {
            print("--profile needs a case: a name of Pele's benchmark or a documentation corpus")
            return
        }
        let work = arguments.dropFirst().first.flatMap(Work.init(rawValue:)) ?? .reading
        let seconds = arguments.dropFirst(2).first.flatMap(Double.init) ?? 5
        let sources = try sources(of: caseName)
        let round = try workRound(work, sources: sources, typography: typography)
        let clock = ContinuousClock()
        let end = clock.now + .milliseconds(Int(seconds * 1_000))
        var roundCount = 0
        while clock.now < end {
            round()
            roundCount += 1
        }
        print("\(caseName), \(work.rawValue): \(roundCount) rounds of \(sources.count) inputs in \(seconds) s")
    }

    private static func sources(of caseName: String) throws -> [String] {
        if caseName == "docs: all examples" { return try FlowchartCorpus.documentationExamples() }
        let generated = PeleResults.generatedBenchmarkInputs.filter { input in input.name == caseName }.map(\.source)
        return generated.isEmpty ? try PeleResults.sources(ofCorpus: caseName) : generated
    }

    private static func workRound(_ work: Work, sources: [String], typography: DiagramTypography) throws -> () -> Void {
        switch work {
        case .reading:
            return {
                for source in sources {
                    _ = (try? MermaidDiagramReader.read(source, limits: .standard)).map { diagram in
                        DiagramSceneBenchmark.laidOut(diagram, typography: typography)
                    }
                }
            }
        case .preparation:
            return {
                for source in sources {
                    _ = try? MermaidDiagramPreparation.prepare(source: source, typography: typography, narrowestColumnWidth: nil,
                                                               now: GanttChartCorpus.now, timeZone: GanttChartCorpus.timeZone).svgDocument()
                }
            }
        case .painting:
            let scenes = sources.compactMap { source in
                (try? MermaidDiagramReader.read(source, limits: .standard)).flatMap { diagram in DiagramSceneBenchmark.laidOut(diagram, typography: typography) }?.scene()
            }
            let contexts = scenes.map { scene in MermaidDiagramsBenchmark.bitmapContext(size: scene.size) }
            return {
                for (scene, context) in zip(scenes, contexts) {
                    if let context { DiagramSceneRenderer.draw(scene, in: context, palette: MermaidDiagramsBenchmark.palette) }
                }
            }
        }
    }
}
