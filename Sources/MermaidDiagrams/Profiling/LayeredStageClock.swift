/**
 * File: LayeredStageClock.swift
 * -----------------------------
 * Layer: Profiling (prototype only)
 * Description: Accumulates the time spent in the stages of the layered layouts, for the redesign's measurements.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import Foundation

/// Not thread safe: the profiler runs on one thread.
public enum LayeredStageClock {
    public enum Stage: Int, CaseIterable {
        case flowchartCollapsing, flowchartMeasurement, flowchartGraphBuilding, flatPlacement, clusterGraphBuilding, clusterPlacement
        case flowchartPageAssembly, flatLayoutCore, flatPlacementWrapping
        case flatOrient, flatRank, flatGraphBuilding, flatCrossingReduction, flatSpreading, flatPositioning, flatEndSettling, flatRouteRest, flatRecycling
    }
    nonisolated(unsafe) public static var nanoseconds = [UInt64](repeating: 0, count: Stage.allCases.count)
    nonisolated(unsafe) public static var counts = [Int](repeating: 0, count: Stage.allCases.count)
    nonisolated(unsafe) public static var isOn = false
    nonisolated(unsafe) public static var lastSizes = (vertices: 0, segments: 0, maximumRank: 0)

    nonisolated(unsafe) public static var allocations = [UInt64](repeating: 0, count: Stage.allCases.count)
    nonisolated(unsafe) static var allocationStack: [UInt64] = { var stack = [UInt64](); stack.reserveCapacity(64); return stack }()
    public typealias Counter = @convention(c) () -> UInt64
    nonisolated(unsafe) public static var allocationCounter: Counter? = nil

    @inline(__always) static func now() -> UInt64 {
        guard isOn else { return 0 }
        if let allocationCounter { allocationStack.append(allocationCounter()) }
        return clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
    }
    @inline(__always) static func add(_ stage: Stage, since start: UInt64) {
        guard isOn else { return }
        nanoseconds[stage.rawValue] &+= clock_gettime_nsec_np(CLOCK_UPTIME_RAW) &- start
        counts[stage.rawValue] += 1
        if let allocationCounter, let before = allocationStack.popLast() { allocations[stage.rawValue] &+= allocationCounter() &- before }
    }
    public static func reset() {
        nanoseconds = [UInt64](repeating: 0, count: Stage.allCases.count)
        counts = [Int](repeating: 0, count: Stage.allCases.count)
        allocations = [UInt64](repeating: 0, count: Stage.allCases.count)
        allocationStack.removeAll(keepingCapacity: true)
    }
}

/// Captures the graphs the layered layouts are given, to replay them alone.
public enum LayeredStageReplay {
    nonisolated(unsafe) static var isCapturing = false
    nonisolated(unsafe) static var flat: [(LayeredGraph, LayeredSpacing, Int)] = []
    nonisolated(unsafe) static var cluster: [(LayeredClusterGraph, LayeredSpacing, Int)] = []

    public static func startCapturing() { flat = []; cluster = []; isCapturing = true }
    public static func stopCapturing() -> (flat: Int, cluster: Int) { isCapturing = false; return (flat.count, cluster.count) }

    public static func replayFlat() {
        for (graph, spacing, limit) in flat { _ = LayeredLayout.place(graph, spacing: spacing, maximumPointCount: limit) }
    }
    public static func replayCluster() {
        for (graph, spacing, limit) in cluster { _ = try? LayeredClusterLayout.place(graph, spacing: spacing, maximumPointCount: limit) }
    }
    /// Node and edge counts of the captured flat graphs.
    public static func flatSizes() -> [(nodes: Int, edges: Int, labelled: Int)] {
        flat.map { (graph, _, _) in (graph.nodeSizes.count, graph.edges.count, graph.edges.filter { $0.labelSize != nil }.count) }
    }
    public static func clusterSizes() -> [(nodes: Int, edges: Int, clusters: Int)] {
        cluster.map { (graph, _, _) in (graph.nodeSizes.count, graph.edges.count, graph.clusters.count) }
    }
    /// Times each captured flat graph alone, `repeats` times, and returns the mean µs of each.
    public static func timeEachFlat(repeats: Int) -> [Double] {
        flat.map { (graph, spacing, limit) in
            let start = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
            for _ in 0..<repeats { _ = LayeredLayout.place(graph, spacing: spacing, maximumPointCount: limit) }
            return Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - start) / 1_000 / Double(repeats)
        }
    }
    public static func timeEachCluster(repeats: Int) -> [Double] {
        cluster.map { (graph, spacing, limit) in
            let start = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
            for _ in 0..<repeats { _ = try? LayeredClusterLayout.place(graph, spacing: spacing, maximumPointCount: limit) }
            return Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - start) / 1_000 / Double(repeats)
        }
    }
}

extension LayeredStageReplay {
    public static func replayFlat(only index: Int) {
        let (graph, spacing, limit) = flat[index]
        _ = LayeredLayout.place(graph, spacing: spacing, maximumPointCount: limit)
    }
}

/// Experiment 1: one workspace per thread, kept from one layout to the next.
enum LayeredThreadWorkspace {
    nonisolated(unsafe) public static var isOn = false
    nonisolated(unsafe) private static var key: pthread_key_t = {
        var key = pthread_key_t()
        pthread_key_create(&key) { pointer in Unmanaged<LayeredFlatWorkspace>.fromOpaque(pointer).release() }
        return key
    }()

    static func workspace() -> LayeredFlatWorkspace {
        guard isOn else { return LayeredFlatWorkspace() }
        if let pointer = pthread_getspecific(key) { return Unmanaged<LayeredFlatWorkspace>.fromOpaque(pointer).takeUnretainedValue() }
        let workspace = LayeredFlatWorkspace()
        pthread_setspecific(key, Unmanaged.passRetained(workspace).toOpaque())
        return workspace
    }
}

public enum LayeredExperiments {
    public static func setThreadWorkspace(_ isOn: Bool) { LayeredThreadWorkspace.isOn = isOn }
}
