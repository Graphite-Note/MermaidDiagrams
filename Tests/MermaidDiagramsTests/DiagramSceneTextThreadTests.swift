/**
 * File: DiagramSceneTextThreadTests.swift
 * ---------------------------------------
 * Layer: Tests
 * Description: Scenes painted on many threads at once, each drawing with its own fonts and attributes, are painted to the
 *              pixel as they are painted alone, without antialiasing, which Core Graphics does not do the same way twice
 *              while other threads paint; scenes of many texts and of many shapes painted apart are built in time linear
 *              in their count.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

import CoreGraphics
import Foundation
import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class DiagramSceneTextThreadTests: XCTestCase {
    /// Twelve threads paint the same scenes at once, each in its own order: every picture is the one painted alone. Each
    /// is painted without antialiasing: Core Graphics' antialiased fills and strokes come out a few pixels unlike
    /// themselves, now and then, while other threads paint other shapes (seen on macOS 27.2.1 with Core Graphics alone,
    /// six rounded rectangles in about half of 3,200 pictures, and never with antialiasing off), which no state of the
    /// painter causes; with it off, the same drawing calls are compared, the same fonts, attributes and strings.
    func testScenesPaintedOnManyThreadsAtOnceAreThosePaintedAlone() throws {
        var scenes: [DiagramScene] = []
        for (_, sources) in try OutputDigest.corpora() {
            for source in sources.prefix(2) {
                guard let prepared = try? MermaidDiagramPreparation.prepare(source: source, typography: DiagramSceneSamples.typography,
                                                                            narrowestColumnWidth: nil, now: GanttChartCorpus.now,
                                                                            timeZone: GanttChartCorpus.timeZone) else { continue }
                scenes.append(prepared.scene)
            }
        }
        XCTAssertGreaterThan(scenes.count, 60)
        let alone = scenes.map(Self.paintedWithoutAntialiasing)
        let shared = PaintedScenes(scenes: scenes, alone: alone)
        let tally = PaintingTally()
        DispatchQueue.concurrentPerform(iterations: 12) { thread in
            let count = shared.scenes.count
            for step in 0..<count {
                let index = (thread &* 29 &+ step) % count
                let scene = shared.scenes[index]
                tally.record(Self.paintedWithoutAntialiasing(scene) == shared.alone[index])
            }
        }
        XCTAssertEqual(tally.matchCount, 12 * scenes.count)
        XCTAssertEqual(tally.differenceCount, 0)
    }

    private static func paintedWithoutAntialiasing(_ scene: DiagramScene) -> DiagramScenePixels? {
        DiagramScenePixels(size: scene.size, scale: 1) { context in
            context.setShouldAntialias(false)
            DiagramSceneRenderer.draw(scene, in: context, palette: DiagramScenePaletteSamples.light)
        }
    }

    /// 60,000 texts and 60,000 shapes kept apart: the builder's lists grow by doubling, the scene takes them, and the
    /// whole takes far less than a second, as it would not if a list were copied for each item.
    func testManyTextsAndShapesAreBuiltInLinearTime() throws {
        let measurer = DiagramSceneSamples.typography.measurer(size: 12)
        let block = DiagramTextBlock(label: DiagramLabelDecoder.label(from: "text", form: .plain), measurer: measurer, maximumWidth: 100)
        let square = CGPath(rect: CGRect(x: 0, y: 0, width: 2, height: 2), transform: nil)
        let count = 60_000
        let clock = ContinuousClock()
        var scene: DiagramScene?
        let elapsed = clock.measure {
            var builder = DiagramSceneBuilder()
            for index in 0..<count {
                builder.text(block, .foreground, part: .label)
                builder.fill(square, index % 2 == 0 ? .surface : .accent, part: .node)
            }
            scene = builder.scene(size: CGSize(width: 2, height: 2), font: DiagramFont(postScriptName: nil, size: 12))
        }
        let built = try XCTUnwrap(scene)
        XCTAssertEqual(built.texts.count, count)
        XCTAssertEqual(built.itemCount, 2 * count)
        XCTAssertLessThan(elapsed, .seconds(3))
    }
}

private final class PaintedScenes: @unchecked Sendable {
    let scenes: [DiagramScene]
    let alone: [DiagramScenePixels?]

    init(scenes: [DiagramScene], alone: [DiagramScenePixels?]) {
        self.scenes = scenes
        self.alone = alone
    }
}

/// How many pictures the threads painted as alone and how many differed.
private final class PaintingTally: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var matchCount = 0
    private(set) var differenceCount = 0

    func record(_ isMatch: Bool) {
        lock.lock()
        if isMatch { matchCount += 1 } else { differenceCount += 1 }
        lock.unlock()
    }
}
