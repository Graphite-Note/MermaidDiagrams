/**
 * File: ScratchShortRunsTests.swift
 * ---------------------------------
 * Layer: Tests
 * Description: Short runs filled and copied with stores of their own hold what the standard library's fill and copy
 *              write, at every length around the short-run limit, between overlapping runs too, and touch nothing
 *              outside the run.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import CoreGraphics
import XCTest
@testable import MermaidDiagrams

final class ScratchShortRunsTests: XCTestCase {
    /// The room either side of each run, so that a store outside it shows.
    private static let margin = 4
    private static let lengths = 0...(ScratchShortRuns.longestShortRun + 5)

    /// Every length fills as `update(repeating:count:)` does, for values of one, eight and sixteen bytes.
    func testFillWritesWhatTheLibraryWritesAndNothingElse() {
        for count in Self.lengths {
            XCTAssertEqual(Self.filled(count: count, value: 7 as Int, background: -1), Self.libraryFilled(count: count, value: 7 as Int, background: -1),
                           "Int run of \(count)")
            XCTAssertEqual(Self.filled(count: count, value: true, background: false), Self.libraryFilled(count: count, value: true, background: false),
                           "Bool run of \(count)")
            let point = CGPoint(x: -0.0, y: .nan)
            XCTAssertEqual(Self.filled(count: count, value: point, background: .zero).map(Self.bits),
                           Self.libraryFilled(count: count, value: point, background: .zero).map(Self.bits), "CGPoint run of \(count)")
        }
    }

    /// Every length copies as `update(from:count:)` does, between separate runs and between runs that overlap either way.
    func testCopyWritesWhatTheLibraryWritesBetweenSeparateAndOverlappingRuns() {
        for count in Self.lengths {
            for shift in [-3, -1, 0, 1, 3, 40] {
                XCTAssertEqual(Self.copied(count: count, shift: shift, isLibrary: false), Self.copied(count: count, shift: shift, isLibrary: true),
                               "run of \(count) copied \(shift) places along")
            }
        }
    }

    /// A span's fill and copy and a list's append go through the short runs.
    func testSpansAndListsHoldWhatWasFilledCopiedAndAppended() {
        let arena = DiagramScratchArena()
        defer { arena.deallocate() }
        for count in Self.lengths {
            let span = arena.span(count: count, repeating: 3.5)
            XCTAssertEqual(Array(span), Array(repeating: 3.5, count: count))
            let source = arena.uninitializedSpan(count: count) as ScratchSpan<Int>
            for index in 0..<count { source[index] = 10 * index + 1 }
            let copy = arena.copy(of: source)
            XCTAssertEqual(Array(copy), Array(source))
            var list = arena.list(capacity: 2, of: Int.self)
            list.append(99)
            list.append(contentsOf: source)
            XCTAssertEqual(Array(list), [99] + Array(source))
        }
    }

    private static func filled<Element: BitwiseCopyable>(count: Int, value: Element, background: Element) -> [Element] {
        var room = Array(repeating: background, count: count + 2 * margin)
        room.withUnsafeMutableBufferPointer { buffer in
            ScratchShortRuns.fill(buffer.baseAddress.unsafelyUnwrapped + margin, count: count, with: value)
        }
        return room
    }

    private static func libraryFilled<Element: BitwiseCopyable>(count: Int, value: Element, background: Element) -> [Element] {
        var room = Array(repeating: background, count: count + 2 * margin)
        room.withUnsafeMutableBufferPointer { buffer in
            (buffer.baseAddress.unsafelyUnwrapped + margin).update(repeating: value, count: count)
        }
        return room
    }

    /// A run of `count` distinct values copied `shift` places along within one block of memory.
    private static func copied(count: Int, shift: Int, isLibrary: Bool) -> [Int] {
        let base = 50
        var room = Array(0..<(2 * base + count))
        room.withUnsafeMutableBufferPointer { buffer in
            let source = UnsafePointer(buffer.baseAddress.unsafelyUnwrapped + base)
            let destination = buffer.baseAddress.unsafelyUnwrapped + base + shift
            if isLibrary {
                destination.update(from: source, count: count)
            } else {
                ScratchShortRuns.copy(from: source, to: destination, count: count)
            }
        }
        return room
    }

    private static func bits(_ point: CGPoint) -> [UInt64] { [Double(point.x).bitPattern, Double(point.y).bitPattern] }
}
