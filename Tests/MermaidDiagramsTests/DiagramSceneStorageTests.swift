/**
 * File: DiagramSceneStorageTests.swift
 * ------------------------------------
 * Layer: Tests
 * Description: A scene keeps each shape's elements as Core Graphics gives them out, a move after a move and an empty path
 *              included; its fast reading and its compatibility views agree; builders record into their thread's blocks,
 *              a builder made while another records gets blocks of its own, large blocks are freed, and scenes built on
 *              many threads at once are those built alone; paths longer than the SVG writer's room made at once are
 *              written as 0.7.0 wrote them; a shape's view kept after its scene still reads its elements.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 24/11/2026
 */

import CoreGraphics
import Foundation
import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class DiagramSceneStorageTests: XCTestCase {
    private let font = DiagramFont(postScriptName: nil, size: 16)

    /// The elements of a Core Graphics path as it gives them out: a verb and its points' bits.
    private func elements(of path: CGPath) -> [[UInt64]] {
        var elements: [[UInt64]] = []
        path.applyWithBlock { element in
            let count: Int
            switch element.pointee.type {
            case .moveToPoint, .addLineToPoint: count = 1
            case .addQuadCurveToPoint: count = 2
            case .addCurveToPoint: count = 3
            default: count = 0
            }
            var entry = [UInt64(element.pointee.type.rawValue)]
            for index in 0..<count { entry += [UInt64(element.pointee.points[index].x.bitPattern), UInt64(element.pointee.points[index].y.bitPattern)] }
            elements.append(entry)
        }
        return elements
    }

    private func elements(of shape: DiagramSceneShapeView) -> [[UInt64]] {
        var elements: [[UInt64]] = []
        shape.forEachElement { verb, points in
            var entry = [UInt64(verb.rawValue)]
            for index in 0..<verb.pointCount { entry += [UInt64(points[index].x.bitPattern), UInt64(points[index].y.bitPattern)] }
            elements.append(entry)
        }
        return elements
    }

    /// Paths of every kind Core Graphics holds or builds: shapes held whole, an arc, a move after a move, an empty path,
    /// paths joined into one.
    private func samplePaths() -> [CGPath] {
        let rounded = CGPath(roundedRect: CGRect(x: 3.3, y: 4.7, width: 90, height: 31), cornerWidth: 4, cornerHeight: 4, transform: nil)
        let arc = CGMutablePath()
        arc.addArc(center: CGPoint(x: 10, y: 10), radius: 7.5, startAngle: 0.3, endAngle: 2.9, clockwise: false)
        let lone = CGMutablePath()
        lone.move(to: CGPoint(x: 1, y: 1))
        let twoMoves = CGMutablePath()
        twoMoves.addPath(lone)
        let next = CGMutablePath()
        next.move(to: CGPoint(x: 5, y: 5))
        next.addLine(to: CGPoint(x: 6, y: 9))
        twoMoves.addPath(next)
        let joined = CGMutablePath()
        joined.addPath(rounded)
        joined.addPath(CGPath(ellipseIn: CGRect(x: 100, y: 0, width: 20, height: 10), transform: nil))
        joined.addQuadCurve(to: CGPoint(x: 140, y: 3), control: CGPoint(x: 130, y: -8))
        joined.closeSubpath()
        return [rounded, arc, lone, twoMoves, CGMutablePath(), joined, CGPath(rect: CGRect(x: -2, y: 1, width: -4, height: 6), transform: nil)]
    }

    func testItemsCopiedIntoASceneAreReadBackElementForElement() throws {
        let paths = samplePaths()
        var block = DiagramTextBlock(label: DiagramLabel("a"), measurer: UniformWidthTextMeasurer(), maximumWidth: 100)
        block.center = CGPoint(x: 5, y: 5)
        var items: [DiagramSceneItem] = []
        for (index, path) in paths.enumerated() {
            items.append(.shape(DiagramSceneShape(path: path, painting: .fill(.series(index)), part: .node)))
            if index.isMultiple(of: 2) { items.append(.text(DiagramSceneText(block: block, paint: .foreground, part: .label))) }
        }
        let scene = DiagramScene(size: CGSize(width: 200, height: 50), font: font, items: items)
        XCTAssertEqual(scene.itemCount, items.count)
        XCTAssertEqual(scene.texts.count, 4)
        var shapeIndex = 0
        var itemIndex = 0
        scene.forEachItem { item in
            switch (item, items[itemIndex]) {
            case (.shape(let view), .shape(let original)):
                XCTAssertEqual(elements(of: view), elements(of: original.path), "path \(shapeIndex)")
                XCTAssertEqual(view.elementCount, elements(of: original.path).count)
                XCTAssertEqual(view.painting, original.painting)
                shapeIndex += 1
            case (.text(let text), .text(let original)):
                XCTAssertEqual(text.block.center, original.block.center)
            default:
                XCTFail("item \(itemIndex) changed kind")
            }
            itemIndex += 1
        }
        XCTAssertEqual(shapeIndex, paths.count)
        for (shape, path) in zip(scene.shapes, paths) {
            XCTAssertEqual(elements(of: shape.path), elements(of: path), "a path made again from the elements has them all, a move after a move too")
        }
    }

    /// A shape's view kept after `forEachItem` returned and after its scene is gone still reads its own elements: it
    /// holds the scene's storage instead of pointers into it, which would point at freed memory once the scene went.
    func testAShapeViewKeptAfterItsSceneReadsItsElements() throws {
        let paths = samplePaths()
        var views: [DiagramSceneShapeView] = []
        do {
            let items = paths.enumerated().map { index, path in DiagramSceneItem.shape(DiagramSceneShape(path: path, painting: .fill(.series(index)), part: .node)) }
            DiagramScene(size: CGSize(width: 200, height: 50), font: font, items: items).forEachItem { item in
                if case .shape(let view) = item { views.append(view) }
            }
        }
        // Scenes made and dropped meanwhile reuse freed memory, which a view pointing into its scene's block would read.
        for _ in 0..<20 {
            let other = CGPath(rect: CGRect(x: 7, y: 7, width: 3, height: 3), transform: nil)
            _ = DiagramScene(size: .zero, font: font, items: Array(repeating: .shape(DiagramSceneShape(path: other, painting: .fill(.accent), part: .edge)),
                                                                count: 40))
        }
        XCTAssertEqual(views.count, paths.count)
        for (index, (view, path)) in zip(views, paths).enumerated() {
            XCTAssertEqual(elements(of: view), elements(of: path), "path \(index)")
            XCTAssertEqual(view.elementCount, elements(of: path).count)
            XCTAssertEqual(elements(of: view.makePath()), elements(of: path))
            XCTAssertEqual(view.painting, .fill(.series(index)))
        }
    }

    func testABuilderMadeWhileAnotherRecordsHasBlocksOfItsOwn() throws {
        let square = CGPath(rect: CGRect(x: 0, y: 0, width: 10, height: 10), transform: nil)
        var outer = DiagramSceneBuilder()
        outer.fill(square, .surface, part: .node)
        outer.keepNextShapeApart()
        var inner = DiagramSceneBuilder()
        inner.stroke(CGPath(ellipseIn: CGRect(x: 0, y: 0, width: 4, height: 4), transform: nil), .border, DiagramStroke(lineWidth: 1), part: .edge)
        let innerScene = inner.scene(size: CGSize(width: 4, height: 4), font: font)
        outer.fill(square, .accent, part: .cluster)
        let outerScene = outer.scene(size: CGSize(width: 10, height: 10), font: font)
        XCTAssertEqual(innerScene.shapes.map(\.painting), [.stroke(.border, DiagramStroke(lineWidth: 1))])
        XCTAssertEqual(outerScene.shapes.map(\.painting), [.fill(.surface), .fill(.accent)])
        XCTAssertEqual(outerScene.shapes.map { shape in elements(of: shape.path) }, [elements(of: square), elements(of: square)])
    }

    func testBlocksGrownPastAMebibyteAreFreedForTheNextScene() {
        var builder = DiagramSceneBuilder()
        let path = CGMutablePath()
        for index in 0..<120_000 { path.addRect(CGRect(x: CGFloat(index), y: 0, width: 1, height: 1)) }
        builder.fill(path, .surface, part: .node)
        let large = builder.scene(size: CGSize(width: 120_000, height: 1), font: font)
        XCTAssertEqual(large.shapes.first.map { shape in elements(of: shape.path).count }, 600_000)
        _ = consume builder
        let buffers = DiagramSceneRecordBuffers.borrow()
        defer { buffers.giveBack() }
        XCTAssertLessThanOrEqual(buffers.capacityByteCount, DiagramSceneRecordBuffers.largestKeptByteCount)
    }

    /// Paths of as many elements as the writer makes room for at once, one fewer and one more, and many times as many,
    /// with numbers of the most digits a path element takes, are written as 0.7.0's writer wrote them.
    func testPathsAroundTheElementsWrittenTogetherAreWrittenAsBefore() {
        for elementCount in [1, 2, 63, 64, 65, 127, 128, 129, 1_000] {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -123_456_789.87, y: 987_654_321.25))
            for index in 1..<elementCount {
                let offset = CGFloat(index) * 1.37
                switch index % 3 {
                case 0: path.addLine(to: CGPoint(x: -99_999_999.99 + offset, y: 12.5))
                case 1: path.addCurve(to: CGPoint(x: offset, y: -88_888_888.88), control1: CGPoint(x: -77_777_777.77, y: offset),
                                      control2: CGPoint(x: 0.125, y: -0.125))
                default: path.addQuadCurve(to: CGPoint(x: 9_998.995, y: -9_999.005), control: CGPoint(x: CGFloat.nan, y: CGFloat.infinity))
                }
            }
            let scene = DiagramScene(size: CGSize(width: 10, height: 10), font: font,
                                     items: [.shape(DiagramSceneShape(path: path, painting: .stroke(.line, DiagramStroke(lineWidth: 1)), part: .edge))])
            XCTAssertEqual(DiagramSVGWriter().document(of: scene, diagramType: "flowchart"),
                           ReferenceSVGWriter().document(of: scene, diagramType: "flowchart"), "\(elementCount) elements")
        }
    }

    /// Sixteen threads prepare the same diagrams at once, each in its own order: every scene's SVG is the one prepared
    /// alone on one thread, so that no thread records into another's blocks or lanes.
    func testScenesBuiltOnManyThreadsAtOnceAreThoseBuiltAlone() throws {
        var sources: [String] = []
        for (_, corpus) in try OutputDigest.corpora() { sources += corpus.prefix(6) }
        let typography = DiagramSceneSamples.typography
        func document(_ source: String) -> String? {
            (try? MermaidDiagramPreparation.prepare(source: source, typography: typography, narrowestColumnWidth: nil, now: GanttChartCorpus.now,
                                                    timeZone: GanttChartCorpus.timeZone)).map { prepared in prepared.svgDocument() }
        }
        let expected = sources.map(document)
        XCTAssertGreaterThan(expected.compactMap { $0 }.count, 150)
        let shared = SharedSources(sources: sources, expected: expected)
        let tally = StorageThreadTally()
        DispatchQueue.concurrentPerform(iterations: 16) { thread in
            for step in 0..<shared.sources.count {
                let index = (thread &* 53 &+ step) % shared.sources.count
                tally.record(document(shared.sources[index]) == shared.expected[index])
            }
        }
        XCTAssertEqual(tally.differenceCount, 0)
        XCTAssertEqual(tally.matchCount, 16 * sources.count)
    }
}

private final class SharedSources: @unchecked Sendable {
    let sources: [String]
    let expected: [String?]

    init(sources: [String], expected: [String?]) {
        self.sources = sources
        self.expected = expected
    }
}

private final class StorageThreadTally: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var matchCount = 0
    private(set) var differenceCount = 0

    func record(_ matches: Bool) {
        lock.lock()
        if matches { matchCount += 1 } else { differenceCount += 1 }
        lock.unlock()
    }
}
