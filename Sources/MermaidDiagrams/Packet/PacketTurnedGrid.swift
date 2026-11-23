/**
 * File: PacketTurnedGrid.swift
 * ----------------------------
 * Layer: Core
 * Description: The bits to a row and the width of a bit of a packet diagram turned to fit a narrow container, as
 *              Pele's packet renderer sets them when it draws the diagram down.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import CoreGraphics

/// How many bits a packet's row holds and how wide a bit is drawn: the diagram's own, or, for a container too narrow for
/// it, as Pele's `draw` with `down` sets them (packet/render.ts): as many bits as the container holds at 18 points (or
/// the bit's own width when narrower), rounded down to a power of two but not under a byte nor over the diagram's own
/// row, and each bit as wide as the container gives it, not under 18 points nor over its own width.
struct PacketTurnedGrid: Equatable {
    let bitsPerRow: Int
    let bitWidth: CGFloat

    /// The narrowest a bit is made, and the narrowest a turned row's bit count is reckoned at.
    static let narrowestBitWidth: CGFloat = 18
    /// The fewest bits a turned row holds: a byte.
    static let fewestBitsPerRow = 8
    /// The most rows a turned packet may have; past it the diagram keeps its own rows (Pele's 10,000).
    static let mostRows = 10_000
    /// The container's width when none is given (Pele's `options.maxWidth ?? 320`).
    static let unmeasuredWidth: CGFloat = 320

    init(bitsPerRow: Int, bitWidth: CGFloat) {
        self.bitsPerRow = bitsPerRow
        self.bitWidth = bitWidth
    }

    /// The grid of `diagram` turned for a container `availableWidth` wide, with `padding` on each side of the page.
    init(_ diagram: PacketDiagram, availableWidth: CGFloat?, padding: CGFloat) {
        let options = diagram.options
        let room = (DiagramWidthFitting.limit(availableWidth) ?? Self.unmeasuredWidth) - 2 * padding
        let count = max(1, (room / min(options.bitWidth, Self.narrowestBitWidth)).rounded(.down))
        let powerOfTwo = count >= 1 ? Self.largestPowerOfTwo(notOver: count) : 1
        var bitsPerRow = min(options.bitsPerRow, max(Self.fewestBitsPerRow, powerOfTwo))
        let lastBit = diagram.fields.last?.lastBit ?? 0
        if (lastBit + 1 + bitsPerRow - 1) / bitsPerRow > Self.mostRows { bitsPerRow = options.bitsPerRow }
        self.bitsPerRow = bitsPerRow
        bitWidth = min(options.bitWidth, max(Self.narrowestBitWidth, room / CGFloat(bitsPerRow)))
    }

    /// 2 to the power of the floor of `count`'s base-two logarithm, `count` being at least 1: at most 2^62.
    private static func largestPowerOfTwo(notOver count: CGFloat) -> Int {
        var power = 1
        while power <= Int.max / 2, CGFloat(power * 2) <= count { power *= 2 }
        return power
    }
}
