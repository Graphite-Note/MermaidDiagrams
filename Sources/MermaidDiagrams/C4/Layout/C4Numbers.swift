/**
 * File: C4Numbers.swift
 * ---------------------
 * Layer: Core
 * Description: Up to nine numbers kept in place rather than in a list: a C4 route's candidate corners, the places
 *              across a gap a lane may take, the ports free on a side of a box.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics

/// Up to nine numbers, in the order appended, with no allocation: what the C4 router tries for each relation (a line's
/// corners as x and y in turn, the places across a gap, the ports on a side) is made and dropped many times a route.
struct C4Numbers: RandomAccessCollection {
    static let capacity = 9

    private(set) var count = 0
    private var storage: (CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0, 0, 0, 0, 0, 0)

    init() {}

    /// A line of two points: their x and y in turn.
    init(_ first: CGFloat, _ second: CGFloat, _ third: CGFloat, _ fourth: CGFloat) {
        storage = (first, second, third, fourth, 0, 0, 0, 0, 0)
        count = 4
    }

    /// A line of four points: their x and y in turn.
    init(_ first: CGFloat, _ second: CGFloat, _ third: CGFloat, _ fourth: CGFloat, _ fifth: CGFloat, _ sixth: CGFloat, _ seventh: CGFloat,
         _ eighth: CGFloat) {
        storage = (first, second, third, fourth, fifth, sixth, seventh, eighth, 0)
        count = 8
    }

    var startIndex: Int { 0 }
    var endIndex: Int { count }

    subscript(index: Int) -> CGFloat {
        precondition(index >= 0 && index < count, "Index out of range of the numbers")
        return withUnsafeBytes(of: storage) { bytes in bytes.load(fromByteOffset: index * MemoryLayout<CGFloat>.stride, as: CGFloat.self) }
    }

    mutating func append(_ value: CGFloat) {
        precondition(count < Self.capacity, "Nine numbers at most")
        let offset = count * MemoryLayout<CGFloat>.stride
        withUnsafeMutableBytes(of: &storage) { bytes in bytes.storeBytes(of: value, toByteOffset: offset, as: CGFloat.self) }
        count += 1
    }
}
