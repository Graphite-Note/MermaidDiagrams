/**
 * File: LaneLayoutTests.swift
 * ---------------------------
 * Layer: Tests
 * Description: The lane layout's cases of Pele's `tests/layout/lanes.test.ts`: lanes side by side in their order, the flow
 *              in its direction, a chain kept straight, a decision's paths on three sides, handoffs apart and around a
 *              lane's margin, a longer link at its length, and random graphs well formed and laid out alike every time.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class LaneLayoutTests: XCTestCase {
    static let spacing = LayeredSpacing(nodeSeparation: 40, edgeSeparation: 16, rankSeparation: 48)
    static let directions: [LayeredDirection] = [.topToBottom, .bottomToTop, .leftToRight, .rightToLeft]

    static func node(_ width: CGFloat, _ height: CGFloat, in parent: Int? = nil) -> LaneLayoutBox {
        LaneLayoutBox(size: CGSize(width: width, height: height), parent: parent, isGroup: false)
    }

    /// Pele's test group: 20 points of padding on the sides and below, 36 above, at least 60 wide.
    static func group(in parent: Int? = nil) -> LaneLayoutBox {
        LaneLayoutBox(size: .zero, parent: parent, isGroup: true, padding: LayeredClusterPadding(side: 20, top: 36, bottom: 20), minimumWidth: 60)
    }

    static func edge(_ source: Int, _ target: Int, label: CGSize? = nil, span: Int = 1) -> LaneLayoutEdge {
        LaneLayoutEdge(source: source, target: target, minimumRankSpan: span, labelSize: label)
    }

    /// The side of `frame` a route's end is on, as Pele's `endSide` finds it: 0 top, 1 right, 2 bottom, 3 left, -1 none.
    static func endSide(_ point: CGPoint, of frame: CGRect) -> Int {
        let offset = CGPoint(x: point.x - frame.midX, y: point.y - frame.midY)
        if abs(abs(offset.y) - frame.height / 2) < 0.5 { return offset.y < 0 ? 0 : 2 }
        if abs(abs(offset.x) - frame.width / 2) < 0.5 { return offset.x < 0 ? 3 : 1 }
        return -1
    }

    func testNothingIsLaidOutAsNothing() {
        let placement = LaneLayout.place(LaneLayoutGraph(boxes: [], edges: [], direction: .topToBottom), spacing: Self.spacing)
        XCTAssertEqual(placement.size, .zero)
    }

    func testLanesSitSideBySideAcrossTheFlowInTheOrderWritten() {
        for direction in Self.directions {
            let boxes = [Self.node(60, 30, in: 3), Self.node(60, 30, in: 2), Self.group(), Self.group()]
            let placement = LaneLayout.place(LaneLayoutGraph(boxes: boxes, edges: [Self.edge(0, 1)], direction: direction), spacing: Self.spacing)
            let (first, second) = (placement.frames[3], placement.frames[2])
            if direction.runsVertically {
                XCTAssertLessThan(first.midX, second.midX)
                XCTAssertEqual(first.height, placement.size.height)
                XCTAssertEqual(first.width + second.width, placement.size.width, accuracy: 1e-6)
            } else {
                XCTAssertLessThan(first.midY, second.midY)
                XCTAssertEqual(first.width, placement.size.width)
                XCTAssertEqual(first.height + second.height, placement.size.height, accuracy: 1e-6)
            }
        }
    }

    func testTheFlowRunsTheWayAskedFor() {
        func centers(_ direction: LayeredDirection) -> (CGPoint, CGPoint) {
            let placement = LaneLayout.place(LaneLayoutGraph(boxes: [Self.node(60, 30, in: 2), Self.node(60, 30, in: 2), Self.group()],
                                                             edges: [Self.edge(0, 1)], direction: direction), spacing: Self.spacing)
            return (CGPoint(x: placement.frames[0].midX, y: placement.frames[0].midY), CGPoint(x: placement.frames[1].midX, y: placement.frames[1].midY))
        }
        XCTAssertLessThan(centers(.topToBottom).0.y, centers(.topToBottom).1.y)
        XCTAssertGreaterThan(centers(.bottomToTop).0.y, centers(.bottomToTop).1.y)
        XCTAssertLessThan(centers(.leftToRight).0.x, centers(.leftToRight).1.x)
        XCTAssertGreaterThan(centers(.rightToLeft).0.x, centers(.rightToLeft).1.x)
    }

    func testAChainInOneLaneRunsStraight() {
        let boxes = [Self.node(50, 30, in: 3), Self.node(120, 30, in: 3), Self.node(70, 30, in: 3), Self.group()]
        let placement = LaneLayout.place(LaneLayoutGraph(boxes: boxes, edges: [Self.edge(0, 1), Self.edge(1, 2)], direction: .topToBottom), spacing: Self.spacing)
        XCTAssertEqual(placement.frames[0].midX, placement.frames[1].midX, accuracy: 1e-6)
        XCTAssertEqual(placement.frames[1].midX, placement.frames[2].midX, accuracy: 1e-6)
    }

    func testADecisionsIncomingAcceptedAndReturnedPathsLeaveByThreeSides() {
        for direction in Self.directions {
            let boxes = [Self.node(60, 40, in: 8), Self.node(80, 40, in: 7), Self.node(70, 70, in: 7), Self.node(80, 40, in: 6), Self.node(80, 40, in: 6),
                         Self.node(60, 40, in: 8), Self.group(), Self.group(), Self.group()]
            let label = CGSize(width: 70, height: 20)
            let edges = [Self.edge(0, 1, label: label), Self.edge(1, 2), Self.edge(2, 3, label: CGSize(width: 50, height: 20)), Self.edge(3, 4),
                         Self.edge(4, 5), Self.edge(2, 0, label: label)]
            let placement = LaneLayout.place(LaneLayoutGraph(boxes: boxes, edges: edges, direction: direction), spacing: Self.spacing)
            let decision = placement.frames[2]
            let incoming = Self.endSide(placement.routes[1]?.points.last ?? .zero, of: decision)
            let accepted = Self.endSide(placement.routes[2]?.points.first ?? .zero, of: decision)
            let returned = Self.endSide(placement.routes[5]?.points.first ?? .zero, of: decision)
            XCTAssertEqual(Set([incoming, accepted, returned]).count, 3, "\(direction)")
            XCTAssertFalse([incoming, accepted, returned].contains(-1), "\(direction)")
            let back = placement.routes[5]?.points ?? []
            for (start, end) in zip(back, back.dropFirst()) { XCTAssertTrue(start.x == end.x || start.y == end.y, "\(direction): straight stretches") }
            let text = CGRect(x: placement.labelCenters[5].x - 35, y: placement.labelCenters[5].y - 10, width: 70, height: 20)
            for frame in placement.frames[0..<6] { XCTAssertFalse(text.insetBy(dx: 0.01, dy: 0.01).intersects(frame), "\(direction): its text clear of the steps") }
        }
    }

    func testAHandoffIntoAStepLeavesFromAnotherSideThanTheHandoffOutOfIt() {
        for direction in Self.directions {
            let boxes = [Self.node(110, 38, in: 5), Self.node(110, 38, in: 5), Self.node(100, 38, in: 4), Self.node(110, 38, in: 4), Self.group(), Self.group()]
            let placement = LaneLayout.place(LaneLayoutGraph(boxes: boxes, edges: [Self.edge(2, 3), Self.edge(0, 3), Self.edge(3, 1)], direction: direction),
                                             spacing: Self.spacing)
            let into = placement.routes[1]?.points.last ?? .zero
            let out = placement.routes[2]?.points.first ?? .zero
            XCTAssertNotEqual(Self.endSide(into, of: placement.frames[3]), Self.endSide(out, of: placement.frames[3]), "\(direction)")
        }
    }

    func testAReturnPastTheStepsBetweenGoesAroundTheMarginOfItsLane() {
        for direction in Self.directions {
            let boxes = [Self.node(140, 44, in: 8), Self.node(140, 44, in: 8), Self.node(140, 44, in: 7), Self.node(120, 76, in: 7), Self.node(140, 44, in: 6),
                         Self.node(140, 44, in: 6), Self.group(), Self.group(), Self.group()]
            let label = CGSize(width: 30, height: 20)
            let edges = [Self.edge(0, 1), Self.edge(1, 2), Self.edge(2, 3), Self.edge(3, 4, label: label), Self.edge(4, 5), Self.edge(3, 0, label: label)]
            let placement = LaneLayout.place(LaneLayoutGraph(boxes: boxes, edges: edges, direction: direction), spacing: Self.spacing)
            let back = placement.routes[5]?.points ?? []
            let sides = [Self.endSide(placement.routes[2]?.points.last ?? .zero, of: placement.frames[3]),
                         Self.endSide(placement.routes[3]?.points.first ?? .zero, of: placement.frames[3]), Self.endSide(back.first ?? .zero, of: placement.frames[3])]
            XCTAssertEqual(Set(sides).count, 3, "\(direction)")
            for (start, end) in zip(back, back.dropFirst()) {
                XCTAssertTrue(start.x == end.x || start.y == end.y, "\(direction)")
                let stretch = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
                for box in [1, 2, 4, 5] { XCTAssertFalse(stretch.intersects(placement.frames[box].insetBy(dx: 0.01, dy: 0.01)), "\(direction): past box \(box)") }
            }
            let along = { (frame: CGRect) in direction.runsVertically ? frame.midY : frame.midX }
            let depth = { (frame: CGRect) in direction.runsVertically ? frame.height : frame.width }
            func gap(_ first: Int, _ second: Int) -> CGFloat {
                abs(along(placement.frames[second]) - along(placement.frames[first])) - (depth(placement.frames[first]) + depth(placement.frames[second])) / 2
            }
            XCTAssertLessThan(gap(1, 2), gap(0, 1), "\(direction): ranks closed up where only handoffs pass")
            XCTAssertEqual(gap(0, 1), Self.spacing.rankSeparation, accuracy: 1e-6)
        }
    }

    func testALinkAskedToBeLongerKeepsItsLengthBesideAHandoff() {
        for direction in Self.directions {
            let boxes = [Self.node(80, 40, in: 5), Self.node(80, 40, in: 5), Self.node(80, 40, in: 5), Self.node(80, 40, in: 4), Self.group(), Self.group()]
            let placement = LaneLayout.place(LaneLayoutGraph(boxes: boxes, edges: [Self.edge(0, 1, span: 2), Self.edge(1, 2), Self.edge(2, 3)], direction: direction),
                                             spacing: Self.spacing)
            func gap(_ first: Int, _ second: Int) -> CGFloat {
                direction.runsVertically ? abs(placement.frames[second].midY - placement.frames[first].midY) - 40
                                         : abs(placement.frames[second].midX - placement.frames[first].midX) - 80
            }
            XCTAssertEqual(gap(0, 1), 2 * Self.spacing.rankSeparation, accuracy: 1e-6, "\(direction)")
            XCTAssertEqual(gap(1, 2), Self.spacing.rankSeparation, accuracy: 1e-6, "\(direction)")
        }
    }
}
