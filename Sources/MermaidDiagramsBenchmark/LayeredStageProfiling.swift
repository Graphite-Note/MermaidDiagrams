/**
 * File: LayeredStageProfiling.swift
 * ---------------------------------
 * Layer: Benchmark (prototype only)
 * Description: Prints where the layered types' layout time goes, per stage, on a corpus.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import Foundation
import MermaidDiagrams

enum LayeredStageProfiling {
    static func run(arguments: [String], typography: DiagramTypography) throws {
        let caseName = arguments.first ?? "docs: all examples"
        let seconds = arguments.dropFirst().first.flatMap(Double.init) ?? 2
        let sources: [String]
        if caseName == "docs: all examples" { sources = try FlowchartCorpus.documentationExamples() } else {
            let generated = PeleResults.generatedBenchmarkInputs.filter { input in input.name == caseName }.map(\.source)
            sources = generated.isEmpty ? try PeleResults.sources(ofCorpus: caseName) : generated
        }
        let diagrams = sources.compactMap { source in try? MermaidDiagramReader.read(source, limits: .standard) }
        if arguments.dropFirst(2).first == "each" {
            for diagram in diagrams {
                let start = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
                for _ in 0..<1000 { _ = DiagramSceneBenchmark.laidOut(diagram, typography: typography) }
                let microseconds = Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - start) / 1_000_000
                if case .flowchart(let flowchart) = diagram {
                    print("each \(flowchart.nodes.count) \(flowchart.edges.count) \(flowchart.subgraphs.count) \(String(format: "%.3f", microseconds))")
                } else { print("each - - - \(String(format: "%.3f", microseconds))") }
            }
            return
        }
        // Warm.
        for diagram in diagrams { _ = DiagramSceneBenchmark.laidOut(diagram, typography: typography) }
        // Untimed rounds, then timed rounds with the clock on.
        func rounds(clockOn: Bool) -> (Int, Double) {
            LayeredStageClock.isOn = clockOn
            LayeredStageClock.reset()
            let clock = ContinuousClock()
            let start = clock.now
            let end = start + .milliseconds(Int(seconds * 1_000))
            var count = 0
            while clock.now < end {
                for diagram in diagrams { _ = DiagramSceneBenchmark.laidOut(diagram, typography: typography) }
                count += 1
            }
            let elapsed = clock.now - start
            let microseconds = Double(elapsed.components.seconds) * 1e6 + Double(elapsed.components.attoseconds) / 1e12
            LayeredStageClock.isOn = false
            return (count, microseconds / Double(max(count * diagrams.count, 1)))
        }
        let (_, plain) = rounds(clockOn: false)
        if let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "counting_allocation_count") {
            LayeredStageClock.allocationCounter = unsafeBitCast(symbol, to: LayeredStageClock.Counter.self)
        }
        let (count, clocked) = rounds(clockOn: true)
        print("\(caseName): \(diagrams.count) diagrams; layout alone (no clock) \(String(format: "%.3f", plain)) µs, with clock \(String(format: "%.3f", clocked)) µs a diagram")
        for stage in LayeredStageClock.Stage.allCases {
            let total = Double(LayeredStageClock.nanoseconds[stage.rawValue]) / 1_000
            let calls = LayeredStageClock.counts[stage.rawValue]
            guard calls > 0 else { continue }
            print("  \(stage): \(String(format: "%.3f", total / Double(count * diagrams.count))) µs a diagram, \(calls / count) calls a round, \(String(format: "%.1f", Double(LayeredStageClock.allocations[stage.rawValue]) / Double(count * diagrams.count))) allocations a diagram")
        }
    }
}

/// `--layered-replay <case> flat|cluster|each [seconds]`: lays out only the layered graphs the case's layouts hand the
/// layered layout, for a sampler.
enum LayeredReplayProfiling {
    static func run(arguments: [String], typography: DiagramTypography) throws {
        let caseName = arguments.first ?? "docs: all examples"
        let mode = arguments.dropFirst().first ?? "flat"
        let seconds = arguments.dropFirst(2).first.flatMap(Double.init) ?? 3
        let sources: [String]
        if caseName == "docs: all examples" { sources = try FlowchartCorpus.documentationExamples() } else {
            let generated = PeleResults.generatedBenchmarkInputs.filter { input in input.name == caseName }.map(\.source)
            sources = generated.isEmpty ? try PeleResults.sources(ofCorpus: caseName) : generated
        }
        let diagrams = sources.compactMap { source in try? MermaidDiagramReader.read(source, limits: .standard) }
        LayeredStageReplay.startCapturing()
        for diagram in diagrams { _ = DiagramSceneBenchmark.laidOut(diagram, typography: typography) }
        let (flatCount, clusterCount) = LayeredStageReplay.stopCapturing()
        if mode == "allocations" {
            typealias Counter = @convention(c) () -> UInt64
            guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "counting_allocation_count") else { print("no counter: run with DYLD_INSERT_LIBRARIES"); return }
            let counter = unsafeBitCast(symbol, to: Counter.self)
            var before = counter()
            LayeredStageReplay.replayFlat()
            let flatAllocations = counter() - before
            before = counter()
            LayeredStageReplay.replayCluster()
            let clusterAllocations = counter() - before
            before = counter()
            for diagram in diagrams { _ = DiagramSceneBenchmark.laidOut(diagram, typography: typography) }
            let wholeAllocations = counter() - before
            before = counter()
            for source in sources { _ = try? MermaidDiagramReader.read(source, limits: .standard) }
            let readingAllocations = counter() - before
            print("\(caseName): allocations a graph: flat \(Double(flatAllocations) / Double(max(flatCount, 1))) (\(flatCount) graphs), cluster \(Double(clusterAllocations) / Double(max(clusterCount, 1))) (\(clusterCount) graphs); whole layout a diagram \(Double(wholeAllocations) / Double(diagrams.count)), reading a diagram \(Double(readingAllocations) / Double(diagrams.count))")
            let sizes = LayeredStageReplay.flatSizes()
            for index in 0..<flatCount where sizes[index].nodes >= 2 {
                before = counter()
                LayeredStageReplay.replayFlat(only: index)
                print("  flat \(index) (\(sizes[index].nodes) nodes, \(sizes[index].edges) edges): \(counter() - before) allocations")
                if index > 40 { break }
            }
            return
        }
        if mode == "ranking" {
            print(LayeredArenaRankingCheck.run(rounds: Int(seconds)))
            return
        }
        if mode == "flatstages" || mode == "clusterstages" {
            LayeredStageClock.reset()
            LayeredStageClock.isOn = true
            let clock = ContinuousClock()
            let end = clock.now + .milliseconds(Int(seconds * 1_000))
            var rounds = 0
            while clock.now < end {
                if mode == "flatstages" { LayeredStageReplay.replayFlat() } else { LayeredStageReplay.replayCluster() }
                rounds += 1
            }
            LayeredStageClock.isOn = false
            print("  last flat graph: \(LayeredStageClock.lastSizes)")
            let graphs = mode == "flatstages" ? flatCount : clusterCount
            for stage in LayeredStageClock.Stage.allCases where LayeredStageClock.counts[stage.rawValue] > 0 {
                let total = Double(LayeredStageClock.nanoseconds[stage.rawValue]) / 1_000
                print("  \(stage): \(String(format: "%.3f", total / Double(rounds * graphs))) µs a graph, \(LayeredStageClock.counts[stage.rawValue] / rounds) calls a round")
            }
            return
        }
        if mode == "each" {
            let flatTimes = LayeredStageReplay.timeEachFlat(repeats: 2000)
            for (index, (size, time)) in zip(LayeredStageReplay.flatSizes(), flatTimes).enumerated() {
                print("flat \(index): \(size.nodes) nodes \(size.edges) edges \(size.labelled) labelled: \(String(format: "%.2f", time)) µs")
            }
            let clusterTimes = LayeredStageReplay.timeEachCluster(repeats: 500)
            for (index, (size, time)) in zip(LayeredStageReplay.clusterSizes(), clusterTimes).enumerated() {
                print("cluster \(index): \(size.nodes) nodes \(size.edges) edges \(size.clusters) clusters: \(String(format: "%.2f", time)) µs")
            }
            return
        }
        let clock = ContinuousClock()
        let start = clock.now
        let end = start + .milliseconds(Int(seconds * 1_000))
        var rounds = 0
        while clock.now < end {
            if mode == "flat" { LayeredStageReplay.replayFlat() } else { LayeredStageReplay.replayCluster() }
            rounds += 1
        }
        let elapsed = clock.now - start
        let microseconds = Double(elapsed.components.seconds) * 1e6 + Double(elapsed.components.attoseconds) / 1e12
        let graphs = mode == "flat" ? flatCount : clusterCount
        print("\(caseName) \(mode): \(graphs) graphs, \(String(format: "%.3f", microseconds / Double(max(rounds * graphs, 1)))) µs a graph, \(String(format: "%.3f", microseconds / Double(max(rounds * diagrams.count, 1)))) µs a diagram")
    }
}
