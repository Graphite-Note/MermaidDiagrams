/**
 * File: SwimlaneNarrowLayoutTests.swift
 * -------------------------------------
 * Layer: Tests
 * Description: A swimlane diagram's narrow layout fitted without laying its regular layout out again, against the
 *              0.7.0 fitting that laid out every layout it tried, over the corpora, generated processes and every
 *              narrow width; the lane layout read in the arena on twelve threads at once.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import CoreGraphics
import Foundation
import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class SwimlaneNarrowLayoutTests: XCTestCase {
    /// The 0.7.0 fitting: across and down, each loose then tight, every one laid out and measured afresh.
    private static func referenceFitted(_ diagram: FlowchartDiagram, typography: DiagramTypography, availableWidth: CGFloat?) -> SwimlaneLayout {
        func fitted(_ diagram: FlowchartDiagram) -> SwimlaneLayout {
            DiagramWidthFitting.tighten(availableWidth: availableWidth, width: { (layout: SwimlaneLayout) in layout.size.width }) { isTight in
                SwimlaneLayoutEngine.layout(diagram, typography: typography, spacing: isTight ? .compact : .standard, columnWidth: availableWidth)
            }
        }
        guard let turned = diagram.swimlaneTurnedToRunDown else { return fitted(diagram) }
        return DiagramWidthFitting.turnToFit(availableWidth: availableWidth, width: { (layout: SwimlaneLayout) in layout.size.width }) { isDown in
            fitted(isDown ? turned : diagram)
        }
    }

    private static func diagrams() throws -> [FlowchartDiagram] {
        var readingLimits = MermaidDiagramLimits.standard
        readingLimits.maximumSourceBytes = 1_000_000
        var sources = try OutputDigest.corpora().flatMap(\.sources) + SwimlaneCorpus.documentationExamples()
        for direction in ["LR", "TD", "RL", "BT"] {
            sources.append(SwimlaneCorpus.process(laneCount: 4, stepCount: 30, direction: direction))
        }
        return sources.compactMap { source in
            guard case .swimlane(let diagram)? = try? MermaidDiagramReader.read(source, limits: readingLimits) else { return nil }
            return diagram
        }
    }

    /// Where the regular layout is kept the narrow one is refused, as no narrow scene is drawn for it; anywhere else it is
    /// the layout the 0.7.0 fitting chose, to the bit; and the public fitting gives the same as before.
    func testTheNarrowLayoutIsTheOneTheReferenceFittingChose() throws {
        let typography = DiagramSceneSamples.typography
        let diagrams = try Self.diagrams()
        XCTAssertGreaterThan(diagrams.count, 12)
        var refusals = 0
        for (index, diagram) in diagrams.enumerated() {
            let regular = SwimlaneLayoutEngine.layout(diagram, typography: typography)
            for width in OutputDigest.narrowColumnWidths + [120, 1_000] {
                let reference = Self.referenceFitted(diagram, typography: typography, availableWidth: width)
                XCTAssertEqual(SwimlaneLayoutEngine.layout(diagram, typography: typography, availableWidth: width), reference, "diagram \(index), \(width) wide")
                do {
                    let narrow = try SwimlaneLayoutEngine.narrowLayout(diagram, typography: typography, availableWidth: width, regularWidth: regular.size.width)
                    XCTAssertEqual(narrow, reference, "diagram \(index), \(width) wide")
                } catch {
                    refusals += 1
                    XCTAssertEqual(reference, regular, "diagram \(index), \(width) wide: refused, so the reference kept the regular layout")
                }
            }
        }
        XCTAssertGreaterThan(refusals, 0)
    }

    /// The lane layout's placement is read where it lies in each thread's arena: twelve threads laying out at once lay
    /// each diagram out as one thread does alone.
    func testSwimlaneLayoutsOnTwelveThreadsAtOnceMatchOneThread() throws {
        let typography = DiagramSceneSamples.typography
        let diagrams = try Self.diagrams()
        let expected = diagrams.map { diagram in SwimlaneLayoutEngine.layout(diagram, typography: typography, availableWidth: 280) }
        let mismatches = ThreadSafeCount()
        DispatchQueue.concurrentPerform(iterations: 12) { thread in
            for offset in diagrams.indices {
                let index = (offset + thread * 5) % diagrams.count
                if SwimlaneLayoutEngine.layout(diagrams[index], typography: typography, availableWidth: 280) != expected[index] { mismatches.add() }
            }
        }
        XCTAssertEqual(mismatches.value, 0)
    }
}
