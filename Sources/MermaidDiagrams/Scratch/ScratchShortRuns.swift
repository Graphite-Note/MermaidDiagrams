/**
 * File: ScratchShortRuns.swift
 * ----------------------------
 * Layer: Core
 * Description: Fills and copies runs of a few plain values with stores of their own, instead of calling memset or
 *              memmove for each of the many short spans a layout of a small graph takes.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

/// A layout of a graph of a few nodes takes a few dozen spans of a few values each, filled or copied once: the compiler
/// makes each fill or copy written as a loop a call of the C library's memset or memmove, which costs more than the
/// stores themselves. A run of at most `longestShortRun` values is written instead by up to eight stores whose places
/// overlap for shorter runs (the first and last, then the second and the one before the last, and so on), with no loop
/// for the compiler to turn into a call; a longer run keeps the library's call.
enum ScratchShortRuns {
    static let longestShortRun = 8

    /// `count` copies of `value` from `start`.
    @inline(__always)
    static func fill<Element: BitwiseCopyable>(_ start: UnsafeMutablePointer<Element>, count: Int, with value: Element) {
        guard count <= longestShortRun else {
            start.update(repeating: value, count: count)
            return
        }
        if count <= 0 { return }
        start[0] = value
        start[count - 1] = value
        if count <= 2 { return }
        start[1] = value
        start[count - 2] = value
        if count <= 4 { return }
        start[2] = value
        start[3] = value
        start[count - 3] = value
        start[count - 4] = value
    }

    /// The `count` values from `source` copied to `destination`, as `update(from:count:)` copies them: every value is
    /// read before any is written, so the two runs may overlap.
    @inline(__always)
    static func copy<Element: BitwiseCopyable>(from source: UnsafePointer<Element>, to destination: UnsafeMutablePointer<Element>, count: Int) {
        guard count <= longestShortRun else {
            destination.update(from: source, count: count)
            return
        }
        if count <= 0 { return }
        let first = source[0]
        let last = source[count - 1]
        if count <= 2 {
            destination[0] = first
            destination[count - 1] = last
            return
        }
        let second = source[1]
        let secondToLast = source[count - 2]
        if count <= 4 {
            destination[0] = first
            destination[1] = second
            destination[count - 2] = secondToLast
            destination[count - 1] = last
            return
        }
        let third = source[2]
        let fourth = source[3]
        let thirdToLast = source[count - 3]
        let fourthToLast = source[count - 4]
        destination[0] = first
        destination[1] = second
        destination[2] = third
        destination[3] = fourth
        destination[count - 4] = fourthToLast
        destination[count - 3] = thirdToLast
        destination[count - 2] = secondToLast
        destination[count - 1] = last
    }
}
