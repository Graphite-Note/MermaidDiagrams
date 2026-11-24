/**
 * File: DiagramScratchArenaTests.swift
 * ------------------------------------
 * Layer: Tests
 * Description: The scratch arena keeps spans where they are while it grows, gives back exactly what was taken after a
 *              mark, lets calls nest on one thread, keeps no more than its limit between uses, and gives each thread its
 *              own arena; spans and lists hold what was written.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import Foundation
import XCTest
@testable import MermaidDiagrams

final class DiagramScratchArenaTests: XCTestCase {
    /// Spans taken while the arena adds chunk after chunk keep their values: growth never moves a span.
    func testSpansStayWhereTheyAreWhileTheArenaGrows() {
        let arena = DiagramScratchArena()
        defer { arena.deallocate() }
        var spans: [ScratchSpan<Int>] = []
        for index in 0..<200 {
            let span = arena.span(count: 37 * index + 1, repeating: index)
            spans.append(span)
        }
        XCTAssertGreaterThan(arena.chunkCount, 1)
        for (index, span) in spans.enumerated() {
            XCTAssertEqual(span.count, 37 * index + 1)
            XCTAssertTrue(span.allSatisfy { value in value == index }, "span \(index)")
            XCTAssertEqual(Int(bitPattern: span.start) % DiagramScratchArena.alignment, 0)
        }
    }

    /// Releasing to a mark gives back what was taken after it, so the next span starts where the first after the mark
    /// did, and leaves what was taken before it as it was.
    func testReleaseToAMarkGivesBackOnlyWhatCameAfterIt() {
        let arena = DiagramScratchArena()
        defer { arena.deallocate() }
        let before = arena.span(count: 100, repeating: 7.5)
        let mark = arena.mark()
        let first = arena.span(count: 50, repeating: 1)
        _ = arena.span(count: 100_000, repeating: UInt8(2))
        arena.release(to: mark)
        let again = arena.span(count: 50, repeating: 3)
        XCTAssertEqual(again.start, first.start)
        XCTAssertTrue(before.allSatisfy { value in value == 7.5 })
        XCTAssertTrue(again.allSatisfy { value in value == 3 })
    }

    /// A call within another on the same thread gives back only what it took, and the outer call's spans keep their
    /// values; the outermost call gives everything back.
    func testNestedCallsOnOneThreadGiveBackOnlyTheirOwnSpans() {
        DiagramScratchArena.withCurrentThread { outer in
            let kept = outer.span(count: 64, repeating: 11)
            let cursorAfterKept = outer.mark()
            DiagramScratchArena.withCurrentThread { inner in
                XCTAssertEqual(inner, outer)
                _ = inner.span(count: 300_000, repeating: 5)
            }
            XCTAssertTrue(kept.allSatisfy { value in value == 11 })
            let next: ScratchSpan<Int> = outer.uninitializedSpan(count: 1)
            outer.release(to: cursorAfterKept)
            let nextAgain: ScratchSpan<Int> = outer.uninitializedSpan(count: 1)
            XCTAssertEqual(next.start, nextAgain.start)
        }
        let afterward: ScratchSpan<Int> = DiagramScratchArena.current.uninitializedSpan(count: 1)
        DiagramScratchArena.current.reset()
        XCTAssertNotNil(afterward.first)
    }

    /// After a use that took far more than the limit, resetting keeps no more than the limit, and the arena still hands
    /// out room as before.
    func testResetKeepsAtMostTheRetainedLimit() {
        let arena = DiagramScratchArena()
        defer { arena.deallocate() }
        for size in [1_000, 40_000, 200_000, 3_000_000, 10] { _ = arena.span(count: size, repeating: UInt8(1)) }
        XCTAssertGreaterThan(arena.heldByteCount, DiagramScratchArena.retainedByteLimit)
        arena.reset()
        XCTAssertLessThanOrEqual(arena.heldByteCount, DiagramScratchArena.retainedByteLimit)
        let span = arena.span(count: 1_000_000, repeating: 0.25)
        XCTAssertTrue(span.allSatisfy { value in value == 0.25 })
    }

    /// Releasing a thread's arena frees all but its first chunk, and does nothing while a call is using it.
    func testReleasingTheThreadArenaFreesItsChunksWhenNotInUse() {
        DiagramScratchArena.withCurrentThread { arena in
            _ = arena.span(count: 100_000, repeating: 1)
            DiagramScratchArena.releaseCurrentThreadArena()
            XCTAssertGreaterThan(arena.chunkCount, 1)
        }
        DiagramScratchArena.releaseCurrentThreadArena()
        XCTAssertEqual(DiagramScratchArena.current.chunkCount, 1)
        XCTAssertEqual(DiagramScratchArena.current.heldByteCount, DiagramScratchArena.firstChunkByteCount)
    }

    /// Each thread has an arena of its own: spans taken at the same time on several threads keep each its own values.
    func testEachThreadHasItsOwnArena() {
        let results = ConcurrentResults()
        DispatchQueue.concurrentPerform(iterations: 8) { iteration in
            DiagramScratchArena.withCurrentThread { arena in
                let span = arena.span(count: 10_000, repeating: iteration)
                usleep(2_000)
                results.add(span.allSatisfy { value in value == iteration })
            }
        }
        XCTAssertEqual(results.all, [Bool](repeating: true, count: 8))
    }

    /// A list grows inside the arena past any room it was given, keeping every value in order, and empties without
    /// losing its room.
    func testListsGrowInTheArenaAndKeepTheirValues() {
        let arena = DiagramScratchArena()
        defer { arena.deallocate() }
        var list = arena.list(capacity: 2, of: Int.self)
        for value in 0..<10_000 { list.append(value) }
        XCTAssertEqual(Array(list), Array(0..<10_000))
        let room = list.capacity
        list.removeAll()
        XCTAssertTrue(list.isEmpty)
        XCTAssertEqual(list.capacity, room)
        list.append(contentsOf: 5..<9)
        list.append(contentsOf: arena.span(count: 3, repeating: -1))
        XCTAssertEqual(Array(list), [5, 6, 7, 8, -1, -1, -1])
        XCTAssertEqual(list.removeLast(), -1)
        XCTAssertEqual(list.popLast(), -1)
        XCTAssertEqual(Array(list.elements), [5, 6, 7, 8, -1])
    }

    /// A span reads and writes through any copy of it, reverses a range, copies another's values and sorts integers.
    func testSpansAreSharedViewsOfTheirValues() {
        let arena = DiagramScratchArena()
        defer { arena.deallocate() }
        let span = arena.span(count: 6, repeating: 0)
        let copy = span
        for index in span.indices { copy[index] = index * 10 }
        XCTAssertEqual(Array(span), [0, 10, 20, 30, 40, 50])
        span.reverse(1..<5)
        XCTAssertEqual(Array(span), [0, 40, 30, 20, 10, 50])
        let own = arena.copy(of: span)
        span.fill(with: 1)
        XCTAssertEqual(Array(own), [0, 40, 30, 20, 10, 50])
        own.sortAscending()
        XCTAssertEqual(Array(own), [0, 10, 20, 30, 40, 50])
        XCTAssertEqual(Array(own.part(2..<4)), [20, 30])
    }
}

/// Results gathered from several threads under a lock.
private final class ConcurrentResults: @unchecked Sendable {
    // Every read and write of `results` holds `lock`.
    private let lock = NSLock()
    private var results: [Bool] = []

    func add(_ result: Bool) {
        lock.lock()
        results.append(result)
        lock.unlock()
    }

    var all: [Bool] {
        lock.lock()
        defer { lock.unlock() }
        return results
    }
}
