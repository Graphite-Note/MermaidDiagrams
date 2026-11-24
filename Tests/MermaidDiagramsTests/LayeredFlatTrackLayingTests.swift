/**
 * File: LayeredFlatTrackLayingTests.swift
 * ---------------------------------------
 * Layer: Tests
 * Description: The tracks and levels the layered layout gives the pieces of one gap: a lone piece and two that cross.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */
import XCTest
@testable import MermaidDiagrams

/// `LayeredFlatTracks.lay` and `assignLevels` give a gap of one piece its answer at once, without weighing the pieces
/// (speed-layered-workspace). These tests hold that answer to the one the weighing gave: a lone piece on straight
/// tracks takes the first track, its group one track high; a lone curve turns onto no level and leaves its gap as it
/// was. Two pieces that cross take the general path, so the same checks cover the weighing itself.
final class LayeredFlatTrackLayingTests: XCTestCase {
    /// One piece across each of two gaps, on straight tracks: each takes track 0 in a group one track high, and each
    /// gap counts one track.
    func testLonePieceOnStraightTracksTakesTheFirstTrackOneTrackHigh() {
        let arena = DiagramScratchArena()
        var tracks = Self.tracks(arena: arena, from: [0, 40], to: [100, -60], rank: [0, 1], isCurved: false, room: [50, 50, 0])
        tracks.assign()
        XCTAssertEqual(Array(tracks.pieces.track), [0, 0])
        XCTAssertEqual(Array(tracks.pieces.levels), [1, 1])
        XCTAssertEqual(Array(tracks.trackCount), [1, 1, 0])
        XCTAssertEqual(Array(tracks.tallGap), [0, 0, 0])
    }

    /// One curve far across its gap, alone there: it has nothing to be told apart from, so it takes no level and the
    /// gap keeps its height.
    func testLoneCurveTakesNoLevelAndLeavesItsGapAsItWas() {
        let arena = DiagramScratchArena()
        var tracks = Self.tracks(arena: arena, from: [0], to: [300], rank: [0], isCurved: true, room: [20, 0])
        tracks.assign()
        XCTAssertEqual(Array(tracks.pieces.track), [-1])
        XCTAssertEqual(Array(tracks.pieces.levels), [0])
        XCTAssertEqual(Array(tracks.trackCount), [0, 0])
        XCTAssertEqual(Array(tracks.tallGap), [0, 0])
    }

    /// Two pieces of one gap that cross, neither above the other making fewer crossings: they clash, so the first in
    /// the list takes track 0 and the second track 1, both in one group two tracks high.
    func testTwoCrossingPiecesTakeTracksOfTheirOwnInOneGroup() {
        let arena = DiagramScratchArena()
        var tracks = Self.tracks(arena: arena, from: [0, 100], to: [100, 0], rank: [0, 0], isCurved: false, room: [50, 0])
        tracks.assign()
        XCTAssertEqual(Array(tracks.pieces.track), [0, 1])
        XCTAssertEqual(Array(tracks.pieces.levels), [2, 2])
        XCTAssertEqual(Array(tracks.trackCount), [2, 0])
    }

    /// The tracks of pieces running from `from` to `to` across the gap under `rank`, with `room` in each gap, wide where
    /// they run more than twice their gap's room across, as the bands mark them, in spans of `arena`.
    private static func tracks(arena: DiagramScratchArena, from: [Double], to: [Double], rank: [Int], isCurved: Bool, room: [Double]) -> LayeredFlatTracks {
        var pieces = LayeredEdgePieces(capacity: from.count, arena: arena)
        for piece in from.indices { pieces.append(from: from[piece], to: to[piece], rank: rank[piece], lower: -1) }
        pieces.isWide = arena.span(count: from.count, repeating: false)
        for piece in from.indices { pieces.isWide[piece] = abs(from[piece] - to[piece]) > LayeredFlatConstants.levelWideFactor * room[rank[piece]] }
        let roomSpan = arena.span(count: room.count, repeating: 0.0)
        for gap in room.indices { roomSpan[gap] = room[gap] }
        return LayeredFlatTracks(pieces: pieces, isCurved: isCurved, room: roomSpan, rankCount: room.count, arena: arena)
    }
}
