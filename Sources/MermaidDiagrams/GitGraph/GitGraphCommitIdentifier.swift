/**
 * File: GitGraphCommitIdentifier.swift
 * ------------------------------------
 * Layer: Core
 * Description: The id of a commit no `id:` names, as Pele makes it up, written byte by byte: the commit's place in
 *              the graph, a hyphen and seven hexadecimal digits of a multiplicative hash of the place.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

/// The id of a commit no `id:` names, as Pele makes it up: the commit's place in the graph, a hyphen and seven
/// hexadecimal digits (`3-1c6f6a1`). Mermaid takes the digits at random; Pele derives them from the place, so that the
/// same text always gives the same ids, and so does this.
enum GitGraphCommitIdentifier {
    /// The multiplier of Knuth's multiplicative hash, 2³² divided by the golden ratio, which spreads the places' bits.
    static let hashMultiplier: UInt32 = 0x9E37_79B1
    /// The digits a 32-bit hash is written in, and those an id keeps.
    static let hashDigitCount = 8
    static let digitCount = 7

    /// The id of the commit at `sequenceNumber` (0 for the first commit), the first of Pele's candidates that `isTaken`
    /// does not refuse: each next candidate adds the multiplier to the hashed number, in 32-bit arithmetic.
    static func generated(sequenceNumber: Int, isTaken: (String) -> Bool) -> String {
        var salt = UInt32(truncatingIfNeeded: sequenceNumber + 1)
        while true {
            let identifier = text(sequenceNumber: sequenceNumber, hash: salt &* hashMultiplier)
            if !isTaken(identifier) { return identifier }
            salt &+= hashMultiplier
        }
    }

    /// `sequenceNumber` in decimal, a hyphen, and the first `digitCount` of the `hashDigitCount` lowercase hexadecimal
    /// digits of `hash` padded with zeros, as `"\(sequenceNumber)-\(padded.prefix(digitCount))"` writes them.
    private static func text(sequenceNumber: Int, hash: UInt32) -> String {
        withUnsafeTemporaryAllocation(of: UInt8.self, capacity: 21 + 1 + digitCount) { buffer in
            var count = 0
            // The decimal digits, the place being never negative, written backwards then turned around.
            var remaining = sequenceNumber.magnitude
            repeat {
                buffer[count] = UInt8(ascii: "0") + UInt8(remaining % 10)
                remaining /= 10
                count += 1
            } while remaining > 0
            if sequenceNumber < 0 {
                buffer[count] = MermaidByte.hyphen
                count += 1
            }
            buffer[0..<count].reverse()
            buffer[count] = MermaidByte.hyphen
            count += 1
            for digit in 0..<digitCount {
                let nibble = UInt8(truncatingIfNeeded: hash >> UInt32(4 * (hashDigitCount - 1 - digit))) & 0xF
                buffer[count] = nibble < 10 ? UInt8(ascii: "0") + nibble : UInt8(ascii: "a") + nibble - 10
                count += 1
            }
            return String(decoding: UnsafeBufferPointer(rebasing: buffer[0..<count]), as: UTF8.self)
        }
    }
}
