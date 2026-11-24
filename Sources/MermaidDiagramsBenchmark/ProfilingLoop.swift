/**
 * File: ProfilingLoop.swift
 * -------------------------
 * Layer: Benchmark
 * Description: Repeats the reading alone, the reading and layout, the whole preparation (with its SVG, or with the
 *              narrow scene Graphite asks for) or the painting of one of the Pele comparison's cases for a few seconds,
 *              so that a sampler (sample, Instruments' Time Profiler) sees only that work, and prints the time a round
 *              took per input.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 23/11/2026
 */

import CoreGraphics
import Foundation
import MermaidDiagrams

/// `--profile <case> [parsing|reading|preparation|narrow|painting] [seconds]`: the case is a name of Pele's benchmark
/// (`tree: 500 nodes`) or a documentation corpus (`treemap-docs`); `parsing` reads the text into its model and lays
/// nothing out, `reading` reads and lays out; `preparation` prepares without a narrow scene and writes the SVG,
/// as the comparison with Pele times it, and `narrow` prepares with the narrow scene for Graphite's narrowest column and
/// reads it, so that it is laid out, and writes no SVG, as Graphite prepares a diagram it shows in a narrow column; the
/// work repeats until the seconds (5 by default) are spent, then prints how many rounds it made and the mean time of a
/// round per input, in microseconds.
enum ProfilingLoop {
    enum Work: String {
        case parsing
        case reading
        case preparation
        case narrow
        case painting
        /// The design prototype's flat reading (FlatMermaidReadingPrototype), and the same made into the present model.
        case flat
        case flatMaterialized = "flatmaterialized"
        case frontEnd = "frontend"
        case flatFrontEnd = "flatfrontend"
        /// The prototype's reading made into the present model, then laid out as `reading` lays it out.
        case flatLayout = "flatlayout"
    }

    /// `--flat-pairs <case> <seconds> <pairs>`: alternates rounds of the present reader and of the prototype in this one
    /// process, `seconds` each, and prints each pair's two times an input and their ratio, then the medians.
    static func runPairs(arguments: [String]) throws {
        let caseName = arguments.first ?? "docs: all examples"
        let seconds = arguments.dropFirst().first.flatMap(Double.init) ?? 0.5
        let pairs = arguments.dropFirst(2).first.flatMap(Int.init) ?? 7
        let sources = try sources(of: caseName)
        func timed(_ round: () -> Void) -> Double {
            let clock = ContinuousClock()
            let start = clock.now
            let end = start + .milliseconds(Int(seconds * 1_000))
            var rounds = 0
            while clock.now < end {
                round()
                rounds += 1
            }
            let elapsed = clock.now - start
            let microseconds = Double(elapsed.components.seconds) * 1e6 + Double(elapsed.components.attoseconds) / 1e12
            return microseconds / Double(max(rounds * sources.count, 1))
        }
        var present: [Double] = []
        var flat: [Double] = []
        var materialized: [Double] = []
        for pair in 0..<pairs {
            let presentTime = timed { FlatMermaidReadingPrototype.readAllWithPresentReader(sources) }
            let flatTime = timed { FlatMermaidReadingPrototype.readAll(sources) }
            let materializedTime = timed { FlatMermaidReadingPrototype.readAndMaterializeAll(sources) }
            present.append(presentTime)
            flat.append(flatTime)
            materialized.append(materializedTime)
            print(String(format: "%@ pair %d: present %.3f µs, flat %.3f µs (%.2fx), flat made into the present model %.3f µs (%.2fx)", caseName, pair,
                         presentTime, flatTime, presentTime / flatTime, materializedTime, presentTime / materializedTime))
        }
        func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }
        let ratios = zip(present, flat).map { pair in pair.0 / pair.1 }
        print(String(format: "%@ medians: present %.3f µs, flat %.3f µs, flat made into the present model %.3f µs, median ratio %.2fx", caseName,
                     median(present), median(flat), median(materialized), median(ratios)))
    }

    /// `--flat-each <case> <rounds>`: each input's time with the present reader and with the prototype, median of
    /// `rounds` alternating measurements of 2,000 readings each, one line per input, then the totals.
    static func runEach(arguments: [String]) throws {
        let caseName = arguments.first ?? "docs: all examples"
        let rounds = arguments.dropFirst().first.flatMap(Int.init) ?? 5
        let sources = try sources(of: caseName)
        let clock = ContinuousClock()
        func time(_ body: () -> Void) -> Double {
            let start = clock.now
            for _ in 0..<2_000 { body() }
            let elapsed = clock.now - start
            return (Double(elapsed.components.seconds) * 1e6 + Double(elapsed.components.attoseconds) / 1e12) / 2_000
        }
        var presentTotal = 0.0
        var flatTotal = 0.0
        var flatTimes: [Double] = []
        for source in sources {
            var present: [Double] = []
            var flat: [Double] = []
            for _ in 0..<rounds {
                present.append(time { FlatMermaidReadingPrototype.readAllWithPresentReader([source]) })
                flat.append(time { FlatMermaidReadingPrototype.readAll([source]) })
            }
            let presentMedian = present.sorted()[rounds / 2]
            let flatMedian = flat.sorted()[rounds / 2]
            presentTotal += presentMedian
            flatTotal += flatMedian
            flatTimes.append(flatMedian)
            let firstLine = source.split(separator: "\n").prefix(3).joined(separator: " / ").prefix(70)
            print(String(format: "%8.3f %8.3f %5.1fx %5d B  ", presentMedian, flatMedian, presentMedian / flatMedian, source.utf8.count) + firstLine)
        }
        let sorted = flatTimes.sorted()
        print(String(format: "mean present %.3f µs, mean flat %.3f µs, median input flat %.3f µs", presentTotal / Double(sources.count),
                     flatTotal / Double(sources.count), sorted[sorted.count / 2]))
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
        let start = clock.now
        let end = start + .milliseconds(Int(seconds * 1_000))
        var roundCount = 0
        while clock.now < end {
            round()
            roundCount += 1
        }
        let elapsed = clock.now - start
        let microseconds = Double(elapsed.components.seconds) * 1e6 + Double(elapsed.components.attoseconds) / 1e12
        let perInput = microseconds / Double(max(roundCount * sources.count, 1))
        print("\(caseName), \(work.rawValue): \(roundCount) rounds of \(sources.count) inputs in \(seconds) s, \(String(format: "%.3f", perInput)) µs an input")
    }

    static func sources(of caseName: String) throws -> [String] {
        if caseName == "docs: all examples" { return try FlowchartCorpus.documentationExamples() }
        if caseName.hasPrefix("file:") {
            return try JSONDecoder().decode([String].self, from: Data(contentsOf: URL(fileURLWithPath: String(caseName.dropFirst(5)))))
        }
        let generated = PeleResults.generatedBenchmarkInputs.filter { input in input.name == caseName }.map(\.source)
        return generated.isEmpty ? try PeleResults.sources(ofCorpus: caseName) : generated
    }

    private static func workRound(_ work: Work, sources: [String], typography: DiagramTypography) throws -> () -> Void {
        switch work {
        case .parsing:
            return {
                for source in sources { _ = try? MermaidDiagramReader.read(source, limits: .standard) }
            }
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
        case .narrow:
            return {
                for source in sources {
                    _ = try? MermaidDiagramPreparation.prepare(source: source, typography: typography,
                                                               narrowestColumnWidth: PreparedMermaidDiagram.standardNarrowestColumnWidth,
                                                               now: GanttChartCorpus.now, timeZone: GanttChartCorpus.timeZone).narrowScene
                }
            }
        case .painting:
            return paintingRound(sources: sources, typography: typography)
        case .flat:
            return { FlatMermaidReadingPrototype.readAll(sources) }
        case .flatMaterialized:
            return { FlatMermaidReadingPrototype.readAndMaterializeAll(sources) }
        case .frontEnd:
            return { FlatMermaidReadingPrototype.presentFrontEnd(sources) }
        case .flatFrontEnd:
            return { FlatMermaidReadingPrototype.flatFrontEnd(sources) }
        case .flatLayout:
            return {
                for source in sources {
                    _ = FlatMermaidReadingPrototype.readMaterialized(source).map { diagram in DiagramSceneBenchmark.laidOut(diagram, typography: typography) }
                }
            }
        }
    }

    /// Paints the scenes of the sources, laid out once, each in a bitmap of its own.
    private static func paintingRound(sources: [String], typography: DiagramTypography) -> () -> Void {
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
