/**
 * File: DiagramWidthFittingTests.swift
 * ------------------------------------
 * Layer: Tests
 * Description: Pele's width fitting: a plot that gives up the overflow, a capped width, a diagram turned to run down
 *              below the breakpoint, a tight layout, and the room a title may take.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics
import XCTest
@testable import MermaidDiagrams

final class DiagramWidthFittingTests: XCTestCase {
    private struct Drawn: Equatable {
        var plot: CGFloat
        var narrow: Bool
        var width: CGFloat
    }

    /// A chart whose labels take 120 points beside a plot.
    private func fit(available: CGFloat?, natural: CGFloat = 500, least: CGFloat = 160) -> (Drawn, [Drawn]) {
        var drawings: [Drawn] = []
        let result = DiagramWidthFitting.fitWidth(availableWidth: available, natural: natural, least: least, width: { (drawn: Drawn) in drawn.width }) { plot, narrow in
            let drawn = Drawn(plot: plot, narrow: narrow, width: plot + 120)
            drawings.append(drawn)
            return drawn
        }
        return (result, drawings)
    }

    func testAPlotThatFitsIsDrawnOnceAndOneWithoutALimitToo() {
        XCTAssertEqual(fit(available: 700).1.count, 1)
        XCTAssertEqual(fit(available: nil).1.count, 1)
        XCTAssertEqual(fit(available: 0).1.count, 1, "A width of zero is no limit, as in Pele")
        XCTAssertEqual(fit(available: -4).1.count, 1)
        XCTAssertEqual(fit(available: .infinity).1.count, 1)
        XCTAssertEqual(fit(available: 620).1.count, 1, "Exactly as wide as the container fits")
    }

    func testAPlotGivesUpTheOverflowAndIsDrawnAgainMarkedNarrow() {
        let (result, drawings) = fit(available: 400)
        XCTAssertEqual(result, Drawn(plot: 280, narrow: true, width: 400))
        XCTAssertEqual(drawings.map(\.plot), [500, 500, 280], "Drawn across, again narrow at its own width, and once more with the overflow taken out")
        XCTAssertEqual(drawings.map(\.narrow), [false, true, true])
    }

    func testAPlotStopsAtItsLeastWidthAndAfterThreeRedraws() {
        let (result, drawings) = fit(available: 200)
        XCTAssertEqual(result.plot, 160, "Not under the least width")
        XCTAssertEqual(drawings.map(\.plot), [500, 500, 160])
        XCTAssertEqual(fit(available: 400, natural: 100).0.plot, 100, "Not wider than its own when the least is more")
        var count = 0
        // A chart whose width falls by half of what its plot gives up never fits: the redraws stop after three.
        let result2 = DiagramWidthFitting.fitWidth(availableWidth: 300, natural: 500, least: 50, width: { (drawn: Drawn) in drawn.width }) { plot, narrow in
            count += 1
            return Drawn(plot: plot, narrow: narrow, width: 100 + plot / 2)
        }
        XCTAssertEqual(count, 5, "The first drawing, the narrow one, and three redraws")
        XCTAssertEqual(result2.width, 306.25)
    }

    func testAFailureOfADrawingIsThrown() {
        enum Refusal: Error { case refused }
        XCTAssertThrowsError(try DiagramWidthFitting.fitWidth(availableWidth: 100, natural: 500, least: 50, width: { (width: CGFloat) in width }) { (plot: CGFloat, _: Bool) throws(Refusal) -> CGFloat in
            if plot < 500 { throw .refused }
            return 500
        }) { error in XCTAssertEqual(error as? Refusal, .refused) }
    }

    func testAWidthIsCappedAtTheContainersAndNotUnderItsLeast() {
        XCTAssertEqual(DiagramWidthFitting.capWidth(availableWidth: nil, natural: 700, least: 240), 700)
        XCTAssertEqual(DiagramWidthFitting.capWidth(availableWidth: 0, natural: 700, least: 240), 700)
        XCTAssertEqual(DiagramWidthFitting.capWidth(availableWidth: 900, natural: 700, least: 240), 700)
        XCTAssertEqual(DiagramWidthFitting.capWidth(availableWidth: 500, natural: 700, least: 240), 500)
        XCTAssertEqual(DiagramWidthFitting.capWidth(availableWidth: 100, natural: 700, least: 240), 240)
        XCTAssertEqual(DiagramWidthFitting.capWidth(availableWidth: 500, natural: 700, least: 240, around: 60), 440)
        XCTAssertEqual(DiagramWidthFitting.capWidth(availableWidth: 100, natural: 200, least: 240), 200, "The least never exceeds the natural width")
    }

    func testADiagramIsTurnedToRunDownOnlyBelowTheBreakpointWhenItDoesNotFitAndDownIsNarrower() {
        func turned(available: CGFloat?, autoDirection: Bool = true, breakpoint: CGFloat? = nil, acrossWidth: CGFloat = 900, downWidth: CGFloat = 300) -> (Bool, Int) {
            var count = 0
            let down = DiagramWidthFitting.turnToFit(availableWidth: available, autoDirection: autoDirection, directionBreakpoint: breakpoint,
                                                     width: { (drawn: (down: Bool, width: CGFloat)) in drawn.width }) { down in
                count += 1
                return (down: down, width: down ? downWidth : acrossWidth)
            }.down
            return (down, count)
        }
        XCTAssertEqual(turned(available: 400).0, true)
        XCTAssertEqual(turned(available: 400).1, 2)
        XCTAssertEqual(turned(available: nil).0, false)
        XCTAssertEqual(turned(available: nil).1, 1)
        XCTAssertEqual(turned(available: 1000).1, 1, "Across fits")
        XCTAssertEqual(turned(available: 400, autoDirection: false).0, false)
        XCTAssertEqual(turned(available: 700).0, false, "Over the 640-point breakpoint, down is not drawn at all")
        XCTAssertEqual(turned(available: 700).1, 1)
        XCTAssertEqual(turned(available: 639).0, true)
        XCTAssertEqual(turned(available: 640).0, false, "At the breakpoint it stays across")
        XCTAssertEqual(turned(available: 700, breakpoint: 800).0, true, "The caller's breakpoint")
        XCTAssertEqual(turned(available: 400, breakpoint: 0).0, true, "A breakpoint of zero is the default one")
        XCTAssertEqual(turned(available: 400, downWidth: 900).0, false, "Down is not narrower")
    }

    func testADiagramIsLaidOutTightlyOnlyWhenLooseDoesNotFitAndTightIsNarrower() {
        func tightened(available: CGFloat?, tightWidth: CGFloat = 300) -> (Bool, Int) {
            var count = 0
            let tight = DiagramWidthFitting.tighten(availableWidth: available, width: { (drawn: (tight: Bool, width: CGFloat)) in drawn.width }) { tight in
                count += 1
                return (tight: tight, width: tight ? tightWidth : 500)
            }.tight
            return (tight, count)
        }
        XCTAssertEqual(tightened(available: 400).0, true)
        XCTAssertEqual(tightened(available: 600).1, 1)
        XCTAssertEqual(tightened(available: nil).1, 1)
        XCTAssertEqual(tightened(available: 400, tightWidth: 500).0, false)
    }

    func testATitleTakesTheContainersWidthLessItsPadding() {
        XCTAssertEqual(DiagramWidthFitting.titleRoom(availableWidth: nil), 4000)
        XCTAssertEqual(DiagramWidthFitting.titleRoom(availableWidth: 0), 4000)
        XCTAssertEqual(DiagramWidthFitting.titleRoom(availableWidth: 300), 284)
        XCTAssertEqual(DiagramWidthFitting.titleRoom(availableWidth: 300, padding: 20), 260)
        XCTAssertEqual(DiagramWidthFitting.titleRoom(availableWidth: 90), 80, "Never under 80 points")
    }
}
