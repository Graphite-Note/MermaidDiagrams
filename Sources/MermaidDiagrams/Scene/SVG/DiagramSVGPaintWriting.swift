/**
 * File: DiagramSVGPaintWriting.swift
 * ----------------------------------
 * Layer: Core
 * Description: Writes a paint's color as SVG names it straight into the document's bytes: Pele's variables as literals,
 *              a mixture spelled out, a written color from its own sRGB channels, a palette's colors converted once per
 *              document.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics

/// The colors of one document's paints, written as `DiagramSVGColors.text(of:)` spells them, without a String: with
/// Pele's variables a role is a literal (a series' from a table), a mixture is spelled out where it is written, and a
/// color the diagram's text gave is spelled from its own sRGB channels, which is what converting its `CGColor` to sRGB
/// gives (`DiagramSVGWriterSpeedTests` checks it); with a palette, each paint's color is converted to sRGB the first time
/// the paint is written and kept for the document, the first paints compared in turn and the rest hashed.
struct DiagramSVGPaintWriter {
    let colors: DiagramSVGColors
    let isPeleVariables: Bool
    private var convertedPaints: [ConvertedPaint] = []
    private var convertedPaintsByPaint: [DiagramPaint: ConvertedPaint] = [:]

    /// How many paints are kept to be compared in turn before the rest are hashed.
    static let scannedPaintCount = 24
    /// The most bytes a color takes: a mixture of two series variables at a share of two decimals.
    static let largestColorByteCount = 128

    /// A palette's color converted: `#rrggbb` in the low seven bytes, and the opacity it is painted at.
    private struct ConvertedPaint {
        let paint: DiagramPaint
        let hexadecimal: UInt64
        let opacity: CGFloat
    }

    init(colors: DiagramSVGColors) {
        self.colors = colors
        if case .peleVariables = colors { isPeleVariables = true } else { isPeleVariables = false }
    }

    /// Writes `paint`'s color into `buffer`, whose room holds `largestColorByteCount` bytes more, and returns the
    /// opacity it is painted at.
    @inline(__always)
    mutating func writeColor(of paint: DiagramPaint, into buffer: inout DiagramSVGBuffer) -> CGFloat {
        guard isPeleVariables else { return writePaletteColor(of: paint, into: &buffer) }
        switch paint.source {
        case .role(let role):
            buffer.write(Self.variable(role))
            return paint.opacity
        case .mixture(let from, let to, let share):
            buffer.write("color-mix(in srgb,")
            buffer.write(Self.variable(from))
            buffer.write(byte: UInt8(ascii: ","))
            buffer.write(Self.variable(to))
            buffer.write(byte: UInt8(ascii: " "))
            buffer.write(number: share * 100)
            buffer.write("%)")
            return paint.opacity
        case .color(let written):
            Self.writeHexadecimal(Self.writtenColorHexadecimal(written), into: &buffer)
            return CGFloat(written.alpha) * paint.opacity
        }
    }

    /// `#rrggbb` of a color the diagram's text gave: from its own channels when each lies in 0...1, which converting
    /// its `CGColor` from sRGB to sRGB leaves as they are, else through that conversion.
    static func writtenColorHexadecimal(_ written: DiagramColor) -> UInt64 {
        guard (0...1).contains(written.red), (0...1).contains(written.green), (0...1).contains(written.blue) else {
            return DiagramSVGColors.packedHexadecimal(components: DiagramSVGColors.sRGBComponents(of: written.cgColor))
        }
        return DiagramSVGColors.packedHexadecimal(components: DiagramSVGColors.SRGBComponents(red: written.red, green: written.green,
                                                                                               blue: written.blue, opacity: written.alpha))
    }

    /// `#rrggbb`, stored as one word of which the last byte is left for what follows to overwrite.
    @inline(__always)
    private static func writeHexadecimal(_ packed: UInt64, into buffer: inout DiagramSVGBuffer) {
        buffer.write(packedBytes: packed, count: 7)
    }

    private mutating func writePaletteColor(of paint: DiagramPaint, into buffer: inout DiagramSVGBuffer) -> CGFloat {
        let converted = convertedPaint(of: paint)
        Self.writeHexadecimal(converted.hexadecimal, into: &buffer)
        return converted.opacity
    }

    private mutating func convertedPaint(of paint: DiagramPaint) -> ConvertedPaint {
        for converted in convertedPaints where converted.paint == paint { return converted }
        if let converted = convertedPaintsByPaint[paint] { return converted }
        guard case .palette(let palette) = colors else { preconditionFailure("palette colors are converted in palette mode") }
        let components = DiagramSVGColors.sRGBComponents(of: paint.color(in: palette))
        let converted = ConvertedPaint(paint: paint, hexadecimal: DiagramSVGColors.packedHexadecimal(components: components), opacity: components.opacity)
        if convertedPaints.count < Self.scannedPaintCount {
            if convertedPaints.isEmpty { convertedPaints.reserveCapacity(Self.scannedPaintCount) }
            convertedPaints.append(converted)
        } else {
            convertedPaintsByPaint[paint] = converted
        }
        return converted
    }

    /// A role as Pele's variable, through its alias where Pele sets one (`DiagramSVGColors.variable(_:)` is its text).
    @inline(__always)
    static func variable(_ role: DiagramPaletteRole) -> StaticString {
        switch role {
        case .background: "var(--_bg)"
        case .foreground: "var(--_fg)"
        case .line: "var(--_l)"
        case .surface: "var(--_s)"
        case .border: "var(--_b)"
        case .accent: "var(--_c)"
        case .critical: "var(--pele-critical,#e45756)"
        case .muted: "var(--_m)"
        case .alternateSurface: "var(--_a)"
        case .series(let index): seriesVariable(slot: DiagramSVGColors.seriesSlot(index))
        }
    }

    /// Pele's eight series variables, each with its color as the fallback: `DiagramPalette.peleSeries` in sRGB
    /// hexadecimal, as `DiagramSVGColors.hexadecimal(_:)` writes them (which a test checks).
    private static func seriesVariable(slot: Int) -> StaticString {
        switch slot {
        case 0: "var(--pele-series-1,#4c78a8)"
        case 1: "var(--pele-series-2,#f58518)"
        case 2: "var(--pele-series-3,#54a24b)"
        case 3: "var(--pele-series-4,#e45756)"
        case 4: "var(--pele-series-5,#72b7b2)"
        case 5: "var(--pele-series-6,#eeca3b)"
        case 6: "var(--pele-series-7,#b279a2)"
        default: "var(--pele-series-8,#9d755d)"
        }
    }
}
