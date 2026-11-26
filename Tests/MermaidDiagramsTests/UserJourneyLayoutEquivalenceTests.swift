/**
 * File: UserJourneyLayoutEquivalenceTests.swift
 * ---------------------------------------------
 * Layer: Tests
 * Description: The flat user journey layout, its scene and its column for narrow widths against 0.7.0's frozen layout
 *              and scene, on every corpus journey, the specification's, generated, hostile and random texts, in faces
 *              that sum exactly and one that does not, and on twelve threads.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class UserJourneyLayoutEquivalenceTests: XCTestCase {
    /// 16 points (the corpora's), 12 points, which sums exactly too, and 12.8 points, which does not.
    private static var typographies: [DiagramTypography] {
        [DiagramSceneSamples.typography, DiagramTypography(font: DiagramFont(postScriptName: nil, size: 12)),
         DiagramTypography(font: DiagramFont(postScriptName: nil, size: 12.8))]
    }

    private static func same(_ layout: UserJourneyLayout, _ reference: ReferenceUserJourneyLayout) -> Bool {
        layout.size == reference.size && layout.font == reference.font && layout.sections == reference.sections && layout.tasks == reference.tasks
            && layout.scaleLevels == reference.scaleLevels && layout.scoreLine == reference.scoreLine && layout.legend == reference.legend
            && layout.title == reference.title
    }

    private static func sameScene(_ layout: UserJourneyLayout, _ reference: ReferenceUserJourneyLayout) -> Bool {
        let writer = DiagramSVGWriter()
        return writer.document(of: DiagramScene(layout: layout), diagramType: "journey")
            == writer.document(of: ReferenceUserJourneySceneRecording.scene(reference), diagramType: "journey")
    }

    /// The texts whose layouts, scenes or columns differ from the reference's, at most five, and how many were laid out.
    private func differences(in sources: [String], typographies: [DiagramTypography] = typographies) -> (laidOut: Int, differences: [String]) {
        var found: [String] = []
        var laidOut = 0
        for source in sources {
            guard case .userJourney(let diagram) = try? MermaidDiagramReader.read(source, limits: .standard) else { continue }
            laidOut += 1
            for typography in typographies {
                let layout = UserJourneyLayoutEngine.layout(diagram, typography: typography)
                let expected = ReferenceUserJourneyLayoutEngine.layout(diagram, typography: typography)
                if !Self.same(layout, expected) || !Self.sameScene(layout, expected) {
                    found.append("\(typography.font.size) pt: \(String(source.prefix(160)).debugDescription)")
                }
                for width: CGFloat in [200, 390, 639]
                where UserJourneyLayoutEngine.columnLayout(diagram, typography: typography, availableWidth: width)
                    != ReferenceUserJourneyLayoutEngine.columnLayout(diagram, typography: typography, availableWidth: width) {
                    found.append("\(typography.font.size) pt column at \(width): \(String(source.prefix(160)).debugDescription)")
                }
            }
            if found.count >= 5 { break }
        }
        return (laidOut, found)
    }

    func testEveryCorpusAndSpecificationJourneyIsLaidOutAndDrawnAsZeroSevenDidIt() throws {
        let sources = try ChartReadingEquivalence.corpusSources(keywords: ["journey"]) + UserJourneyReadingEquivalenceTests.specificationTexts
        let (laidOut, found) = differences(in: sources)
        XCTAssertGreaterThanOrEqual(laidOut, 10)
        XCTAssertEqual(found, [])
    }

    /// Generated journeys, many sections of one name in a row, every task without actors, and a hundred actors.
    func testGeneratedAndHostileJourneysAreLaidOutAsZeroSevenLaidThemOut() {
        let sameNames = "journey\n" + (0..<60).map { index in "  section \(index % 3 == 0 ? "A" : "B")\n  task \(index): \(index % 7): Me, Cat" }.joined(separator: "\n")
        let noActors = "journey\n  title " + String(repeating: "long title ", count: 80) + "\n" + (0..<40).map { index in "  t\(index): \(index % 6)" }.joined(separator: "\n")
        let manyActors = "journey\n  section s\n  everyone: 5: " + (0..<100).map { index in "actor \(index)" }.joined(separator: ", ") + "\n  word "
            + String(repeating: "W", count: 400) + ": 1: Me"
        let sources = [5, 30, 150].map { count in UserJourneyCorpus.generated(taskCount: count) } + [sameNames, noActors, manyActors]
        let (laidOut, found) = differences(in: sources, typographies: [Self.typographies[0], Self.typographies[2]])
        XCTAssertEqual(laidOut, 6)
        XCTAssertEqual(found, [])
    }

    func testRandomJourneysAreLaidOutAsZeroSevenLaidThemOut() {
        var statements = UserJourneyRandomStatements(seed: 0x1A_7041_EE)
        let sources = (0..<1_500).map { index in statements.text(statementCount: 1 + index % 12) }
        let (laidOut, found) = differences(in: sources)
        XCTAssertGreaterThan(laidOut, 500)
        XCTAssertEqual(found, [])
    }

    /// The scenes made on twelve threads at once are the ones made alone.
    func testTwelveThreadsLayJourneysOutAsOneThreadDoes() throws {
        var statements = UserJourneyRandomStatements(seed: 0x12_7041)
        let sources = try ChartReadingEquivalence.corpusSources(keywords: ["journey"]) + (0..<60).map { index in statements.text(statementCount: 2 + index % 9) }
        @Sendable func document(_ source: String) -> String? {
            guard case .userJourney(let diagram) = try? MermaidDiagramReader.read(source, limits: .standard) else { return nil }
            return DiagramSVGWriter().document(of: DiagramScene(layout: UserJourneyLayoutEngine.layout(diagram, typography: DiagramSceneSamples.typography)),
                                               diagramType: "journey")
        }
        let expected = sources.map(document)
        let tally = TrackFlatThreadTally()
        DispatchQueue.concurrentPerform(iterations: 12) { thread in
            for round in 0..<6 {
                for (index, source) in sources.enumerated() where (index + round + thread) % 3 == 0 { tally.record(document(source) == expected[index]) }
            }
        }
        XCTAssertGreaterThan(tally.matchCount, 12 * sources.count)
        XCTAssertEqual(tally.differenceCount, 0)
    }
}
