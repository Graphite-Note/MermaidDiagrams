/**
 * File: TrackLinesInPlaceTests.swift
 * ----------------------------------
 * Layer: Tests
 * Description: The groups of lines the sequence, journey, timeline, railroad and event modeling scenes record straight
 *              into their lanes hold, element for element and bit for bit, what adding each line through a Core Graphics
 *              path of its own gives (the drawing parts' route), on every corpus input of those types, each with a line
 *              left out, and their narrow layouts.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import CoreGraphics
import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class TrackLinesInPlaceTests: XCTestCase {
    private let typography = DiagramSceneSamples.typography

    /// The elements of a path, each verb with its points' bits.
    private static func elements(of path: CGPath) -> [String] {
        var elements: [String] = []
        path.applyWithBlock { element in
            let points = element.pointee.points
            let count: Int
            switch element.pointee.type {
            case .moveToPoint, .addLineToPoint: count = 1
            case .addQuadCurveToPoint: count = 2
            case .addCurveToPoint: count = 3
            case .closeSubpath: count = 0
            @unknown default: count = 0
            }
            elements.append("\(element.pointee.type.rawValue)" + (0..<count).map { index in ":\(points[index].x.bitPattern),\(points[index].y.bitPattern)" }.joined())
        }
        return elements
    }

    /// The elements a lane holds, as the scene's storage copies them (a path made of it would join its moves).
    private static func elements(of lane: DiagramPathLane) -> [String] {
        var elements: [String] = []
        lane.forEachElement { verb, points in
            elements.append("\(verb.rawValue)" + (0..<verb.pointCount).map { index in ":\(points[index].x.bitPattern),\(points[index].y.bitPattern)" }.joined())
        }
        return elements
    }

    /// The line groups of `source`'s layouts recorded into lanes and into Core Graphics paths, as pairs; nil when the
    /// source is not one of these types.
    private func lineGroups(_ source: String) -> [(lane: [String], coreGraphics: [String])]? {
        guard let diagram = try? MermaidDiagramReader.read(source, limits: .standard) else { return nil }
        return DiagramSceneWorkspace.withRecording { workspace in
            let paths = DiagramCoreGraphicsPaths()
            switch diagram {
            case .sequence(let sequence):
                let layouts = [try? SequenceLayoutEngine.layout(sequence, typography: typography),
                               try? SequenceLayoutEngine.layout(sequence, typography: typography, availableWidth: 280)].compactMap { $0 }
                return layouts.flatMap { layout -> [([String], [String])] in
                    let lanes = SequenceDrawingPaths(layout: layout, making: workspace).messages
                    let made = SequenceDrawingPaths(layout: layout, making: paths).messages
                    let groups = [(lanes.lines, made.lines)] + zip(lanes.inkedLines, made.inkedLines).map { ($0, $1) }
                    return groups.flatMap { lane, path in
                        [(Self.elements(of: lane.solidLines), Self.elements(of: path.solidLines.path)),
                         (Self.elements(of: lane.dottedLines), Self.elements(of: path.dottedLines.path))]
                    }
                }
            case .railroad(let railroad):
                return [RailroadLayoutEngine.layout(railroad, typography: typography), RailroadLayoutEngine.layout(railroad, typography: typography, columnWidth: 280)]
                    .map { layout in
                        (Self.elements(of: RailroadDrawingPaths(layout: layout, making: workspace).track),
                         Self.elements(of: RailroadDrawingPaths(layout: layout, making: paths).track.path))
                    }
            case .eventModel(let model):
                return [EventModelLayoutEngine.layout(model, typography: typography), EventModelLayoutEngine.layout(model, typography: typography, columnWidth: 280)]
                    .map { layout in
                        (Self.elements(of: EventModelDrawingPaths(layout: layout, making: workspace).relationLines),
                         Self.elements(of: EventModelDrawingPaths(layout: layout, making: paths).relationLines.path))
                    }
            case .timeline(let timeline):
                return [TimelineLayoutEngine.layout(timeline, typography: typography), TimelineLayoutEngine.layout(timeline, typography: typography, availableWidth: 280)]
                    .map { layout in
                        (Self.elements(of: TimelineDrawingPaths(layout: layout, making: workspace).connectors),
                         Self.elements(of: TimelineDrawingPaths(layout: layout, making: paths).connectors.path))
                    }
            case .userJourney(let journey):
                let layout = UserJourneyLayoutEngine.layout(journey, typography: typography)
                let lanes = UserJourneyDrawingPaths(layout: layout, making: workspace)
                // 0.7.0's route: each stem and scale line through a path of its own.
                let stems = paths.makePath()
                for task in layout.tasks { paths.addEdgeLine(task.stem, to: stems) }
                let scaleLines = paths.makePath()
                for level in layout.scaleLevels { paths.addEdgeLine(level.line, to: scaleLines) }
                return [(Self.elements(of: lanes.stems), Self.elements(of: stems.path)),
                        (Self.elements(of: lanes.scaleLines), Self.elements(of: scaleLines.path))]
            default:
                return nil
            }
        }
    }

    /// The corpus inputs, and each with one of its lines left out.
    private func sources() throws -> [String] {
        let corpus = try OutputDigest.corpora().flatMap(\.sources)
        return corpus + corpus.flatMap { source -> [String] in
            let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
            return (1..<max(lines.count, 1)).map { leftOut in
                var kept = lines
                kept.remove(at: leftOut)
                return kept.joined(separator: "\n")
            }
        }
    }

    func testLinesRecordedInPlaceAreThoseAddedThroughPathsOfTheirOwn() throws {
        var comparedCount = 0
        var lineCount = 0
        for source in try sources() {
            guard let groups = lineGroups(source) else { continue }
            for (lane, coreGraphics) in groups {
                XCTAssertEqual(lane, coreGraphics, String(source.prefix(120)))
                lineCount += lane.count
            }
            comparedCount += 1
        }
        XCTAssertGreaterThan(comparedCount, 500, "sequences, railroad diagrams, event models, timelines and journeys")
        XCTAssertGreaterThan(lineCount, 5_000, "elements compared")
    }

    /// A line of no segment, a move alone, is followed by the next line's move as adding it through its own path
    /// follows it: kept, not taken the place of.
    func testALineOfAMoveAloneKeepsTheMoveAfterIt() {
        let lines = [DiagramPath(start: CGPoint(x: 1, y: 2), segments: []), DiagramPath(start: CGPoint(x: 3, y: 4), segments: [.line(to: CGPoint(x: 5, y: 6))]),
                     DiagramPath(start: CGPoint(x: 7, y: 8), segments: []), DiagramPath(start: CGPoint(x: 9, y: 9), segments: [])]
        let paths = DiagramCoreGraphicsPaths()
        let made = paths.makePath()
        for line in lines { paths.addEdgeLine(line, to: made) }
        let recorded = DiagramSceneWorkspace.withRecording { workspace in
            let lane = workspace.makeLane()
            for line in lines { workspace.addEdgeLineInPlace(line, to: lane) }
            return Self.elements(of: lane)
        }
        XCTAssertEqual(recorded, Self.elements(of: made.path))
    }
}
