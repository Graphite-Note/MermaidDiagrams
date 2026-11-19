/**
 * File: PacketSyntaxProblem.swift
 * -------------------------------
 * Layer: Core
 * Description: What a packet diagram's text can get wrong that no other diagram can.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// A problem of a packet diagram's own syntax, or a field its bits cannot take. Mermaid's messages carry the same numbers.
public enum PacketSyntaxProblem: Equatable, Sendable {
    /// A whole number of bits was expected: after `+`, or after the `-` of a range.
    case expectedBitNumber
    /// A field's bits are not followed by `:`.
    case expectedColon
    /// A field's `:` is not followed by its label between quotation marks.
    case expectedFieldLabel
    /// A range ends before it starts (`25-20`): its first and last bit.
    case endBeforeStart(firstBit: Int, lastBit: Int)
    /// A field does not start one bit after the field before it: its first and last bit, and the bit it should start at.
    case notContiguous(firstBit: Int, lastBit: Int, expectedFirstBit: Int)
    /// A field of `+0` bits, by the bit it would start at.
    case zeroBitField(firstBit: Int)
}
