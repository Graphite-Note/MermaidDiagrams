/**
 * File: UseCaseEdgeEndsEquivalenceTests.swift
 * -------------------------------------------
 * Layer: Tests
 * Description: The ends of a use case diagram's lines are spread along their nodes' sides as the 0.7.0 UseCaseEdgeEnds
 *              spreads them, to the bit, on routes made up over the nodes of the documentation examples: many ends on
 *              one side, ends that go next to the same place (which keep the order they were found in), routes of two
 *              points and of one.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import CoreGraphics
import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class UseCaseEdgeEndsEquivalenceTests: XCTestCase {
    /// SplitMix64: the same values on every run.
    private struct SeededGenerator: RandomNumberGenerator {
        private var state: UInt64

        init(seed: UInt64) {
            state = seed
        }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var mixed = state
            mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
            mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
            return mixed ^ (mixed >> 31)
        }
    }

    /// A route of `pointCount` points whose coordinates come from a few values, so that many ends go next to the same place.
    private func route(pointCount: Int, random: inout SeededGenerator) -> LayeredClusterRoute {
        let values: [CGFloat] = [-40, 0, 12.5, 30, 30, 75]
        let points = (0..<pointCount).map { _ in CGPoint(x: values.randomElement(using: &random)!, y: values.randomElement(using: &random)!) }
        let runs = (0..<max(pointCount - 1, 1)).map { _ in Bool.random(using: &random) }
        return LayeredClusterRoute(points: points, segmentsRunVertically: runs)
    }

    func testEndsAreSpreadAsTheReferenceSpreadsThem() throws {
        var random = SeededGenerator(seed: 0xE4D5_0F11)
        var comparedCount = 0
        for source in try UseCaseCorpus.documentationExamples() {
            guard case .useCase(let diagram) = try MermaidDiagramReader.read(source, limits: .standard) else { continue }
            var measurers = UseCaseTextMeasurers(typography: DiagramSceneSamples.typography)
            let views = UseCaseLayoutPass(diagram: diagram, measurers: &measurers).views
            guard !views.isEmpty else { continue }
            for _ in 0..<40 {
                let routeCount = Int.random(in: 1...24, using: &random)
                var routes = (0..<routeCount).map { _ in route(pointCount: Int.random(in: 1...5, using: &random), random: &random) }
                // Few nodes, so that many ends meet one side.
                let nodeCount = min(views.count, Int.random(in: 1...3, using: &random))
                let sources = (0..<routeCount).map { _ in Int.random(in: 0..<nodeCount, using: &random) }
                let targets = (0..<routeCount).map { _ in Int.random(in: 0..<nodeCount, using: &random) }
                let centers = views.indices.map { _ in CGPoint(x: CGFloat.random(in: 0...300, using: &random), y: CGFloat.random(in: 0...300, using: &random)) }
                var reference = routes
                ReferenceUseCaseEdgeEnds.attach(&reference, sources: sources, targets: targets, centers: centers, views: views)
                UseCaseEdgeEnds.attach(&routes, sources: sources, targets: targets, centers: centers, views: views)
                XCTAssertEqual(routes.map { route in route.points.map { point in [point.x.bitPattern, point.y.bitPattern] } },
                               reference.map { route in route.points.map { point in [point.x.bitPattern, point.y.bitPattern] } })
                comparedCount += 1
            }
        }
        XCTAssertGreaterThan(comparedCount, 500)
    }
}
