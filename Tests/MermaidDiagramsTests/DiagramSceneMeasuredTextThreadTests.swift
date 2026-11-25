/**
 * File: DiagramSceneMeasuredTextThreadTests.swift
 * -----------------------------------------------
 * Layer: Tests
 * Description: Checks that scenes built from texts measured from their source's bytes on twelve threads at once, each
 *              thread copying the texts into its own text storage, are the scenes built alone: their SVG and the lines of
 *              each of their texts, in three faces at three widths.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import CoreGraphics
import Foundation
@testable import MermaidDiagrams
import XCTest

final class DiagramSceneMeasuredTextThreadTests: XCTestCase {
    private static let threadCount = 12
    private static let measurers = [CoreTextDiagramTextMeasurer(font: DiagramFont(postScriptName: nil, size: 16)),
                                    CoreTextDiagramTextMeasurer(font: DiagramFont(postScriptName: nil, size: 12)),
                                    CoreTextDiagramTextMeasurer(font: DiagramFont(postScriptName: nil, size: 12.8))]
    private static let widths: [CGFloat] = [.infinity, 80, 0]

    /// The scenes each thread builds, built first one thread after another and then on twelve threads at once: the same
    /// SVG and scene lines.
    func testScenesOfMeasuredTextsBuiltOnTwelveThreadsAtOnceAreThoseBuiltAlone() throws {
        let sources = MeasuredTextSources(Array(try DiagramFlatTextMeasuringTests.corpusTexts().prefix(900)))
        func scenes(ofThread thread: Int) -> [MeasuredScene] {
            sources.measuredScenes(measurer: Self.measurers[thread % Self.measurers.count], maximumWidth: Self.widths[(thread / 3) % Self.widths.count])
        }
        let alone = (0..<Self.threadCount).map { thread in scenes(ofThread: thread) }
        XCTAssertGreaterThan(alone[0].count, 4)
        let together = ThreadScenes(count: Self.threadCount)
        DispatchQueue.concurrentPerform(iterations: Self.threadCount) { thread in together.set(scenes(ofThread: thread), at: thread) }
        for thread in 0..<Self.threadCount {
            XCTAssertEqual(together.scenes(at: thread), alone[thread], "thread \(thread)")
        }
    }
}

/// A scene built from measured texts, as compared: its SVG and the lines of each of its texts.
struct MeasuredScene: Equatable {
    let document: String
    let textLines: [[DiagramSceneTextLine]]
}

extension MeasuredTextSources {
    /// Every text measured from its bytes and drawn into scenes of 150 texts each, plain, bold or turned in turn.
    func measuredScenes<Measurer: DiagramTextMeasuring>(measurer: Measurer, maximumWidth: CGFloat) -> [MeasuredScene] {
        let flat = DiagramFlatMeasurer(measurer)
        let writer = DiagramSVGWriter()
        var scenes: [MeasuredScene] = []
        bytes.withUnsafeBufferPointer { source in
            var start = 0
            while start < texts.count {
                let batch = texts[start..<min(start + 150, texts.count)]
                var lines = DiagramMeasuredLines()
                var builder = DiagramSceneBuilder()
                for (offset, text) in batch.enumerated() {
                    let measured = DiagramFlatTextMeasuring.measure(source, text.range, form: text.form, measurer: flat, maximumWidth: maximumWidth,
                                                                    into: &lines)
                        .centered(at: CGPoint(x: CGFloat(offset % 5) * 40, y: CGFloat(offset) * 2))
                    builder.text(measured, of: lines, source: source, .foreground, isBold: offset % 3 == 1, rotation: offset % 4 == 2 ? -.pi / 2 : nil,
                                 part: .label)
                }
                let scene = builder.scene(size: CGSize(width: 300, height: 300), font: SceneComparison.font)
                scenes.append(MeasuredScene(document: writer.document(of: scene, diagramType: "test"), textLines: scene.texts.map(\.lines)))
                start += batch.count
            }
        }
        return scenes
    }
}

/// The scenes each thread built, kept under a lock.
private final class ThreadScenes: @unchecked Sendable {
    private let lock = NSLock()
    private var found: [[MeasuredScene]]

    init(count: Int) {
        found = Array(repeating: [], count: count)
    }

    func set(_ scenes: [MeasuredScene], at thread: Int) {
        lock.lock()
        found[thread] = scenes
        lock.unlock()
    }

    func scenes(at thread: Int) -> [MeasuredScene] {
        lock.lock()
        defer { lock.unlock() }
        return found[thread]
    }
}
