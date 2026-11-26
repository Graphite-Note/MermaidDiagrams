/**
 * File: TimelineLayoutEquivalenceTests.swift
 * ------------------------------------------
 * Layer: Tests
 * Description: The flat timeline layout and its scene, regular and fitted to narrow widths, against 0.7.0's frozen
 *              layout and scene, on every corpus timeline, the specification's, generated, hostile, random and changed
 *              texts, in faces that sum exactly and one that does not, and on twelve threads.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class TimelineLayoutEquivalenceTests: XCTestCase {
    /// 16 points (the corpora's), 12 points, which sums exactly too, and 12.8 points, which does not.
    private static var typographies: [DiagramTypography] { [DiagramSceneSamples.typography, DiagramTypography(font: DiagramFont(postScriptName: nil, size: 12)),
                                       DiagramTypography(font: DiagramFont(postScriptName: nil, size: 12.8))] }

    /// The texts whose layouts or scenes differ from the reference's, at most five, and how many timelines were laid out.
    private func differences(in sources: [String], typographies: [DiagramTypography] = typographies,
                             widths: [CGFloat?] = [nil, 220, 390, 639]) -> (laidOut: Int, differences: [String]) {
        var found: [String] = []
        var laidOut = 0
        for source in sources {
            guard let (model, reference) = TimelineEquivalence.models(source) else { continue }
            laidOut += 1
            for typography in typographies {
                for width in widths {
                    let layout = width.map { width in TimelineLayoutEngine.layout(model, typography: typography, availableWidth: width) }
                        ?? TimelineLayoutEngine.layout(model, typography: typography)
                    let expected = width.map { width in ReferenceTimelineLayoutEngine.layout(reference, typography: typography, availableWidth: width) }
                        ?? ReferenceTimelineLayoutEngine.layout(reference, typography: typography)
                    if !TimelineEquivalence.same(layout, expected) || !TimelineEquivalence.sameScene(layout, expected) {
                        found.append("\(typography.font.size) pt, width \(width.map { "\($0)" } ?? "none"): \(String(source.prefix(160)).debugDescription)")
                    }
                }
            }
            if found.count >= 5 { break }
        }
        return (laidOut, found)
    }

    func testEveryCorpusAndSpecificationTimelineIsLaidOutAndDrawnAsZeroSevenDidIt() throws {
        let sources = try ChartReadingEquivalence.corpusSources(keywords: ["timeline"]) + TimelineReadingEquivalenceTests.specificationTexts
        let (laidOut, found) = differences(in: sources)
        XCTAssertGreaterThanOrEqual(laidOut, 23)
        XCTAssertEqual(found, [])
    }

    func testGeneratedAndHostileTimelinesAreLaidOutAsZeroSevenLaidThemOut() {
        let generated = [3, 20, 120].flatMap { count in
            [TimelineCorpus.generated(periodCount: count), TimelineCorpus.generated(periodCount: count, periodsPerSection: 3, isDown: true)]
        }
        let (laidOut, found) = differences(in: generated + TimelineEquivalence.hostileTexts(), typographies: [Self.typographies[0], Self.typographies[2]],
                                           widths: [nil, 300])
        XCTAssertEqual(laidOut, 11)
        XCTAssertEqual(found, [])
    }

    func testRandomTimelinesAreLaidOutAsZeroSevenLaidThemOut() {
        let (laidOut, found) = differences(in: TimelineEquivalence.randomTexts(count: 1_500, seed: 0x7141_E11E))
        XCTAssertGreaterThan(laidOut, 700)
        XCTAssertEqual(found, [])
    }

    func testChangedTimelinesAreLaidOutAsZeroSevenLaidThemOut() throws {
        let sources = try ChartReadingEquivalence.corpusSources(keywords: ["timeline"])
        var mutations = ChartTextMutations(seed: 0x7141_C4A6)
        var changed: [String] = []
        for index in 0..<1_500 {
            let source = sources[index % sources.count]
            changed.append(index % 2 == 0 ? mutations.mutated(source) : mutations.spliced(source))
        }
        let (laidOut, found) = differences(in: changed, typographies: [Self.typographies[0], Self.typographies[2]], widths: [nil, 390])
        XCTAssertGreaterThan(laidOut, 700)
        XCTAssertEqual(found, [])
    }

    /// The layouts and scenes made on twelve threads at once are the ones made alone: the measured lines and the text
    /// storage each thread fills stay its own.
    func testTwelveThreadsLayTimelinesOutAsOneThreadDoes() throws {
        let sources = try ChartReadingEquivalence.corpusSources(keywords: ["timeline"]) + TimelineEquivalence.randomTexts(count: 60, seed: 0x12_7141)
        let typography = DiagramSceneSamples.typography
        let expected = sources.map { source in
            TimelineEquivalence.models(source).map { model, _ in
                DiagramSVGWriter().document(of: DiagramScene(layout: TimelineLayoutEngine.layout(model, typography: typography)), diagramType: "timeline")
            }
        }
        let tally = TrackFlatThreadTally()
        DispatchQueue.concurrentPerform(iterations: 12) { thread in
            let typography = DiagramSceneSamples.typography
            for round in 0..<6 {
                for (index, source) in sources.enumerated() where (index + round + thread) % 3 == 0 {
                    let document = TimelineEquivalence.models(source).map { model, _ in
                        DiagramSVGWriter().document(of: DiagramScene(layout: TimelineLayoutEngine.layout(model, typography: typography)), diagramType: "timeline")
                    }
                    tally.record(document == expected[index])
                }
            }
        }
        XCTAssertGreaterThan(tally.matchCount, 12 * sources.count)
        XCTAssertEqual(tally.differenceCount, 0)
    }
}
