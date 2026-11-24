/**
 * File: DiagramSVGWriterThreadTests.swift
 * ---------------------------------------
 * Layer: Tests
 * Description: The SVG writer's per-thread block and kept root style hold up when many threads write at once, as
 *              Graphite prepares diagrams on many threads: every document written on sixteen threads together is the
 *              one 0.7.0's writer writes alone; and a host whose closure throws gives the thread's block back.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
import Foundation
import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class DiagramSVGWriterThreadTests: XCTestCase {
    /// Sixteen threads write the same documents at once, each in its own order and switching between Pele's variables
    /// and a palette and between fonts (so that each thread's kept root style changes under it): every document is the
    /// reference writer's, written alone on one thread.
    func testDocumentsWrittenOnManyThreadsAtOnceAreThoseWrittenAlone() throws {
        let typography = DiagramSceneSamples.typography
        var scenes: [(scene: DiagramScene, type: String)] = []
        for (_, sources) in try OutputDigest.corpora() {
            for source in sources.prefix(4) {
                guard let prepared = try? MermaidDiagramPreparation.prepare(source: source, typography: typography, narrowestColumnWidth: nil,
                                                                            now: GanttChartCorpus.now, timeZone: GanttChartCorpus.timeZone) else { continue }
                scenes.append((prepared.scene, prepared.kind.peleName))
            }
        }
        var samples = DiagramSVGSceneSamples(seed: 0x7_4EAD)
        for _ in 0..<60 { scenes.append((samples.scene(), samples.text())) }
        XCTAssertGreaterThan(scenes.count, 150)
        let writers = [DiagramSVGWriter(), DiagramSVGWriter(colors: .palette(DiagramScenePaletteSamples.dark), identifierPrefix: "thread", paintsBackground: true)]
        let references = [ReferenceSVGWriter(), ReferenceSVGWriter(colors: .palette(DiagramScenePaletteSamples.dark), identifierPrefix: "thread", paintsBackground: true)]
        let expected = scenes.map { scene in references.map { reference in reference.document(of: scene.scene, diagramType: scene.type, title: "T") } }
        let shared = SharedScenes(scenes: scenes, writers: writers, expected: expected)
        let tally = ThreadTally()
        DispatchQueue.concurrentPerform(iterations: 16) { thread in
            let count = shared.scenes.count
            for step in 0..<(count * 2) {
                let index = (thread &* 37 &+ step) % count
                let writerIndex = (thread &+ step) % 2
                let scene = shared.scenes[index]
                let written = shared.writers[writerIndex].document(of: scene.scene, diagramType: scene.type, title: "T")
                tally.record(written == shared.expected[index][writerIndex])
            }
        }
        XCTAssertEqual(tally.matchCount, 16 * scenes.count * 2)
        XCTAssertEqual(tally.differenceCount, 0)
    }

    /// A host whose closure throws gets the error, and the thread's block is given back: the next document is written
    /// into it again, not into a block of its own.
    func testAHostThatThrowsGivesTheThreadsBlockBack() {
        struct HostFailure: Error {}
        let scene = DiagramScene(size: CGSize(width: 10, height: 10), font: DiagramFont(postScriptName: nil, size: 12),
                                 items: [.shape(DiagramSceneShape(path: CGPath(rect: CGRect(x: 0, y: 0, width: 4, height: 4), transform: nil),
                                                                  painting: .fill(.accent), part: .node))])
        let writer = DiagramSVGWriter()
        let document = writer.document(of: scene, diagramType: "x")
        XCTAssertThrowsError(try writer.withDocumentBytes(of: scene, diagramType: "x") { _ in throw HostFailure() }) { error in
            XCTAssertTrue(error is HostFailure)
        }
        let writtenInPlace = writer.withDocumentBytes(of: scene, diagramType: "x") { bytes in
            (UnsafeMutablePointer(mutating: bytes.baseAddress) == DiagramSVGScratch.current.blockAddress, Array(bytes))
        }
        XCTAssertTrue(writtenInPlace.0, "the thread's block is lent again after a host threw")
        XCTAssertEqual(writtenInPlace.1, Array(document.utf8))
    }
}

/// The scenes, writers and expected documents the threads share; read only once made.
private final class SharedScenes: @unchecked Sendable {
    let scenes: [(scene: DiagramScene, type: String)]
    let writers: [DiagramSVGWriter]
    let expected: [[String]]

    init(scenes: [(scene: DiagramScene, type: String)], writers: [DiagramSVGWriter], expected: [[String]]) {
        self.scenes = scenes
        self.writers = writers
        self.expected = expected
    }
}

/// How many documents the threads wrote as expected and how many differed.
private final class ThreadTally: @unchecked Sendable {
    private let lock = NSLock()
    private var matches = 0
    private var differences = 0

    func record(_ isMatch: Bool) {
        lock.lock()
        if isMatch { matches += 1 } else { differences += 1 }
        lock.unlock()
    }

    var matchCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return matches
    }

    var differenceCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return differences
    }
}
