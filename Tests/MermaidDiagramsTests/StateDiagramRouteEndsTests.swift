/**
 * File: StateDiagramRouteEndsTests.swift
 * --------------------------------------
 * Layer: Tests
 * Description: A transition's end moved from the layout's place onto its state as Pele's attach moves it, and the
 *              ends of laid-out state diagrams where Pele's layout settles them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class StateDiagramRouteEndsTests: XCTestCase {
    private let center = CGPoint(x: 100, y: 100)

    func testAnEndOnTheTopOfAPlaceTallerThanItsStateMovesDownOntoTheStateKeepingItsPlaceAcross() {
        // A place 40 tall around a state 30 tall: the end at the place's top moves 5 down.
        let end = StateDiagramRouteEnds.attached(CGPoint(x: 92, y: 80), next: CGPoint(x: 50, y: 40), center: center,
                                                 layoutSize: CGSize(width: 120, height: 40), drawnSize: CGSize(width: 60, height: 30), isBar: false)
        XCTAssertEqual(end, CGPoint(x: 92, y: 85))
    }

    func testAnEndOnTheRightOfAPlaceWidenedForLoopsMovesInOntoTheState() {
        let end = StateDiagramRouteEnds.attached(CGPoint(x: 160, y: 104), next: CGPoint(x: 200, y: 104), center: center,
                                                 layoutSize: CGSize(width: 120, height: 30), drawnSize: CGSize(width: 60, height: 30), isBar: false)
        XCTAssertEqual(end, CGPoint(x: 130, y: 104))
    }

    func testAnEndOnABarTakesItsNextPointsPlaceAcrossShortOfTheBarsEnds() {
        let bar = CGSize(width: 70, height: 10)
        let within = StateDiagramRouteEnds.attached(CGPoint(x: 100, y: 105), next: CGPoint(x: 120, y: 150), center: center,
                                                    layoutSize: bar, drawnSize: bar, isBar: true)
        XCTAssertEqual(within, CGPoint(x: 120, y: 105))
        let beyond = StateDiagramRouteEnds.attached(CGPoint(x: 100, y: 105), next: CGPoint(x: 10, y: 150), center: center,
                                                    layoutSize: bar, drawnSize: bar, isBar: true)
        XCTAssertEqual(beyond, CGPoint(x: 71, y: 105), "6 points inside the bar's left end")
    }

    func testAnEndOnNoSideOfThePlaceIsLeftWhereItIs() {
        let end = StateDiagramRouteEnds.attached(CGPoint(x: 100, y: 100), next: CGPoint(x: 100, y: 150), center: center,
                                                 layoutSize: CGSize(width: 60, height: 30), drawnSize: CGSize(width: 60, height: 30), isBar: false)
        XCTAssertEqual(end, CGPoint(x: 100, y: 100))
    }

    func testTransitionsBetweenTwoStatesMeetThemWhereTheLayoutSettledThemAsPelesDo() throws {
        // state-docs#18: Pele draws Still --> Moving and Moving --> Still as two straight lines, settled 16 points apart,
        // where spreading them along each side apart from the layout bent both.
        let laidOut = try StateDiagramUniformLayout.layout("stateDiagram-v2\n[*] --> Still\nStill --> [*]\nStill --> Moving\nMoving --> Still\nMoving --> Crash\nCrash --> [*]")
        for transition in laidOut.transitions.dropFirst(2).prefix(2) {
            let points = transition.path.allPoints
            XCTAssertEqual(try XCTUnwrap(points.first).x, try XCTUnwrap(points.last).x, accuracy: 0.01, "A straight transition")
        }
    }
}
