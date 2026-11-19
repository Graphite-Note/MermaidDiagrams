/**
 * File: PacketOptions.swift
 * -------------------------
 * Layer: Core
 * Description: The options of a packet diagram its front matter (`config:`, `packet:`) and its directives set.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// The options of packet diagrams a diagram's front matter (`config:`, then `packet:`) and its `%%{init: …}%%` directives
/// set, a directive's over the front matter's. A number below its least, or of the wrong kind, is left at its default;
/// one above its largest is cut to it, as Pele reads them.
public struct PacketOptions: Equatable, Sendable {
    /// `bitsPerRow`: how many bits a row holds, a whole number from 1 to 4096.
    public internal(set) var bitsPerRow = 32
    /// `rowHeight`: a row's height in points, 1 to 400.
    public internal(set) var rowHeight: CGFloat = 32
    /// `bitWidth`: one bit's width in points, 1 to 400.
    public internal(set) var bitWidth: CGFloat = 32
    /// `paddingX`: the gap between two fields of a row, 0 to 400; never as wide as a bit.
    public internal(set) var horizontalPadding: CGFloat = 5
    /// `paddingY`: the gap between two rows, 0 to 400.
    public internal(set) var verticalPadding: CGFloat = 5
    /// `showBits`: whether the first and last bit of each field are written above it.
    public internal(set) var showsBitNumbers = true
    /// `bitOrder: descending`: the bits of a row count from the right.
    public internal(set) var isDescending = false

    /// Options that set nothing: 32 bits of 32 points in rows of 32 points, bit numbers shown, counting from the left.
    public init() {}

    init(_ options: MermaidConfigurationOptions) {
        bitsPerRow = Int(options.boundedNumber("bitsPerRow", fallback: 32, least: 1, largest: 4_096).rounded(.down))
        rowHeight = CGFloat(options.boundedNumber("rowHeight", fallback: 32, least: 1, largest: 400))
        bitWidth = CGFloat(options.boundedNumber("bitWidth", fallback: 32, least: 1, largest: 400))
        horizontalPadding = CGFloat(options.boundedNumber("paddingX", fallback: 5, least: 0, largest: 400))
        verticalPadding = CGFloat(options.boundedNumber("paddingY", fallback: 5, least: 0, largest: 400))
        if case .boolean(false) = options.values["showBits"] { showsBitNumbers = false }
        if case .text("descending") = options.values["bitOrder"] { isDescending = true }
    }
}
