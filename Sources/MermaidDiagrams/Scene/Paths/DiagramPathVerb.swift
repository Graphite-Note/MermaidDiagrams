/**
 * File: DiagramPathVerb.swift
 * ---------------------------
 * Layer: Core
 * Description: The kinds of element a path lane records, one byte each, as Core Graphics names a path's elements, with
 *              how many points each takes.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics

/// One element of a path lane, as Core Graphics names them (`CGPathElementType`): a move, a line, a quadratic curve, a
/// cubic curve or a close. Its points follow it in the lane's points, its end after its control points.
enum DiagramPathVerb: UInt8, Sendable {
    case move = 0
    case line = 1
    case quadraticCurve = 2
    case cubicCurve = 3
    case close = 4

    /// How many points the element takes from the lane's points.
    @inline(__always)
    var pointCount: Int {
        switch self {
        case .move, .line: 1
        case .quadraticCurve: 2
        case .cubicCurve: 3
        case .close: 0
        }
    }
}
