/**
 * File: C4SceneEquivalenceTests.swift
 * -----------------------------------
 * Layer: Tests
 * Description: The C4 scene painted from the layout's flat records (heading lines, measured texts over the diagram's
 *              bytes and the lines' derived bytes, one list of segments) against the 0.7.0 scene painted from the frozen
 *              0.7.0 layout's value types, over every corpus input, random, changed and generated texts and hostile ones;
 *              and C4, use case and swimlane diagrams prepared on twelve threads at once against those prepared alone.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics
import Foundation
import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class C4SceneEquivalenceTests: XCTestCase {
    /// A face whose advances add up exactly and one whose do not, so that wrapping takes the full path.
    static var typographies: [DiagramTypography] {
        [16, 12.8].map { size in DiagramTypography(font: DiagramFont(postScriptName: nil, size: CGFloat(size))) }
    }

    func testScenesOfTheCorporaAndOfPelesCompatibilityTestsAreTheReferenceScenes() throws {
        let sources = try OutputDigest.corpora().flatMap(\.sources) + PeleResults.compatInputs().sorted { $0.key < $1.key }.flatMap(\.value)
        XCTAssertGreaterThanOrEqual(Self.assertSameScenes(sources), 27)
    }

    func testScenesOfRandomChangedGeneratedAndHostileTextsAreTheReferenceScenes() throws {
        var generator = C4RandomTexts(seed: 0xC4_5CE7E)
        var sources = (0..<400).map { _ in generator.text() }
        let originals = try C4Corpus.documentationExamples() + PeleResults.compatInputs().filter { $0.key.hasPrefix("c4/") }.sorted { $0.key < $1.key }
            .flatMap(\.value)
        for round in 0..<600 { sources.append(generator.mutated(originals[round % originals.count])) }
        var diagrams = RandomC4Diagrams(seed: 0x5CE7E)
        for _ in 0..<200 { sources.append(diagrams.text()) }
        sources += C4HostileTexts.all
        XCTAssertGreaterThan(Self.assertSameScenes(sources), 250)
    }

    /// Twelve threads prepare the same C4, use case and swimlane diagrams at once, each starting at another input,
    /// regular and at two narrow widths: every SVG, narrow SVG and spoken text is the one prepared alone, before the
    /// threads start.
    func testC4UseCaseAndSwimlaneDiagramsPreparedOnManyThreadsAtOnceAreThosePreparedAlone() throws {
        let typography = DiagramSceneSamples.typography
        var sources: [String] = []
        for name in ["c4-docs", "usecase-docs", "swimlane-docs"] { sources += try PeleResults.sources(ofCorpus: name) }
        sources += C4HostileTexts.all
        var useCaseTexts = UseCaseRandomTexts(seed: 0x7_4EAD)
        for _ in 0..<60 { sources.append(useCaseTexts.text(statementCount: 24)) }
        XCTAssertGreaterThan(sources.count, 100)
        let widths: [CGFloat] = [280, 390]
        let expected = sources.map { source in OutputDigest.Outcome(source: source, typography: typography, narrowColumnWidths: widths).summaryLine }
        let shared = C4SceneThreadSharedInputs(sources: sources, expected: expected, typography: typography, widths: widths)
        let differences = ThreadSafeCount()
        let matches = ThreadSafeCount()
        DispatchQueue.concurrentPerform(iterations: 12) { thread in
            let count = shared.sources.count
            for step in 0..<count {
                let index = (thread &* 31 &+ step) % count
                let outcome = OutputDigest.Outcome(source: shared.sources[index], typography: shared.typography, narrowColumnWidths: shared.widths)
                if outcome.summaryLine == shared.expected[index] { matches.add() } else { differences.add() }
            }
        }
        XCTAssertEqual(matches.value, 12 * sources.count)
        XCTAssertEqual(differences.value, 0)
    }

    /// Paints each C4 source both ways, as written, tight in a column of 320 points and fitted to it, in every face, and
    /// fails for each scene that differs; returns how many sources the reference read as C4.
    @discardableResult
    static func assertSameScenes(_ sources: [String], file: StaticString = #filePath, line: UInt = #line) -> Int {
        var checked = 0
        var mismatches = 0
        for source in sources {
            guard case .c4(let expected)? = try? ReferenceC4Reading.read(source, limits: .standard),
                  case .c4(let diagram)? = try? MermaidDiagramReader.read(source, limits: .standard) else { continue }
            checked += 1
            for typography in typographies {
                let pairs: [(String, ReferenceC4Layout?, C4Layout?)] = [
                    ("as written", try? ReferenceC4LayoutEngine.layout(expected, typography: typography), try? C4LayoutEngine.layout(diagram, typography: typography)),
                    ("tight", try? ReferenceC4LayoutEngine.tightLayout(expected, typography: typography, columnWidth: 320),
                     try? C4LayoutEngine.tightLayout(diagram, typography: typography, columnWidth: 320)),
                    ("fitted", try? ReferenceC4LayoutEngine.layout(expected, typography: typography, fittingWidth: 320),
                     try? C4LayoutEngine.layout(diagram, typography: typography, fittingWidth: 320)),
                ]
                for (name, reference, layout) in pairs {
                    guard let reference, let layout else {
                        if (reference == nil) != (layout == nil) {
                            mismatches += 1
                            XCTFail("\(name): one layout refused, the other not:\n\(source.prefix(400))", file: file, line: line)
                        }
                        continue
                    }
                    let recorded = DiagramSceneTranscript.lines(of: DiagramScene(layout: layout))
                    guard recorded != DiagramSceneTranscript.lines(of: ReferenceC4Scene.scene(layout: reference)) else { continue }
                    mismatches += 1
                    if mismatches <= 5 { XCTFail("\(name) scene differs (size \(typography.font.size)):\n\(source.prefix(400))", file: file, line: line) }
                }
            }
        }
        XCTAssertEqual(mismatches, 0, file: file, line: line)
        return checked
    }
}

/// The inputs and expected outcomes the threads share; read only once made.
private final class C4SceneThreadSharedInputs: @unchecked Sendable {
    let sources: [String]
    let expected: [String]
    let typography: DiagramTypography
    let widths: [CGFloat]

    init(sources: [String], expected: [String], typography: DiagramTypography, widths: [CGFloat]) {
        self.sources = sources
        self.expected = expected
        self.typography = typography
        self.widths = widths
    }
}
