/**
 * File: DiagramSVGColors.swift
 * ----------------------------
 * Layer: Core
 * Description: How a scene's paints are written in SVG: in a palette's colors, or as Pele's CSS variables with Pele's
 *              colors as their fallbacks; each paint's text as a String, which the document's writer writes as bytes
 *              (DiagramSVGPaintWriter), and colors in sRGB hexadecimal.
 *
 * Authors: Bahey Shalash
 * Version: 0.5
 * Date: 24/11/2026
 */

import CoreGraphics

/// How an SVG names its colors.
public enum DiagramSVGColors: Sendable {
    /// Every color written out in a palette's colors, as plain SVG 1.1: the drawing looks the same wherever it is shown.
    case palette(DiagramPalette)
    /// Every role written as Pele's CSS variable with Pele's own color as its fallback (`var(--pele-bg,#fff)`), and a
    /// mixture as CSS's `color-mix`, so that an Obsidian theme or a page's style colors the drawing as it colors Pele's.
    case peleVariables
}

/// A paint as SVG writes it: its color and the opacity it is painted at.
struct DiagramSVGPaintText {
    let color: String
    let opacity: CGFloat
}

extension DiagramSVGColors {
    /// Pele's private aliases of its variables, set once on the root element so that each use is short.
    static let peleRootStyle = "--_bg:var(--pele-bg,#fff);--_fg:var(--pele-fg,#1f1f1f);--_m:var(--pele-muted,#6e6e6e);"
        + "--_l:var(--pele-line,#1f1f1f);--_s:var(--pele-surface,#f3f3f3);--_a:var(--pele-surface-alt,#e6e6e6);"
        + "--_b:var(--pele-border,#8a8a8a);--_c:var(--pele-accent,#5b7bd5);color:var(--_fg)"

    func text(of paint: DiagramPaint) -> DiagramSVGPaintText {
        switch self {
        case .palette(let palette):
            let components = Self.sRGBComponents(of: paint.color(in: palette))
            return DiagramSVGPaintText(color: Self.hexadecimal(components: components), opacity: components.opacity)
        case .peleVariables:
            switch paint.source {
            case .role(let role): return DiagramSVGPaintText(color: Self.variable(role), opacity: paint.opacity)
            case .mixture(let from, let to, let share):
                let percentage = DiagramSVGSyntax.number(share * 100)
                return DiagramSVGPaintText(color: "color-mix(in srgb,\(Self.variable(from)),\(Self.variable(to)) \(percentage)%)", opacity: paint.opacity)
            case .color(let written):
                return DiagramSVGPaintText(color: Self.hexadecimal(written.cgColor), opacity: CGFloat(written.alpha) * paint.opacity)
            }
        }
    }

    /// The colors a scene is written in: a palette with the series the diagram's theme variables set in their colors, or
    /// Pele's variables, whose series the writer declares on the root's style as Pele does (`;--pele-series-1:#ffeb3b`,
    /// `DiagramSeriesColors.styleDeclarations`).
    func overSeriesColors(of scene: DiagramScene) -> DiagramSVGColors {
        switch self {
        case .palette(let palette): .palette(scene.palette(over: palette))
        case .peleVariables: .peleVariables
        }
    }

    /// The root's colors in this mode: Pele's aliases, or nothing when every color is written out.
    var rootStyle: String {
        switch self {
        case .palette: ""
        case .peleVariables: Self.peleRootStyle + ";"
        }
    }

    /// A role as Pele's variable, through its alias where Pele sets one: the literal the document's writer writes
    /// (`DiagramSVGPaintWriter.variable(_:)`), a series' with its color as the fallback (`var(--pele-series-1,#4c78a8)`).
    static func variable(_ role: DiagramPaletteRole) -> String {
        DiagramSVGPaintWriter.variable(role).withUTF8Buffer { bytes in String(decoding: bytes, as: UTF8.self) }
    }

    /// Which of Pele's eight series variables a series index takes, the colors taken in turn.
    static func seriesSlot(_ index: Int) -> Int {
        ((index % DiagramPalette.peleSeries.count) + DiagramPalette.peleSeries.count) % DiagramPalette.peleSeries.count
    }

    /// `#rrggbb` in sRGB; black for a color with no sRGB form.
    static func hexadecimal(_ color: CGColor) -> String {
        hexadecimal(components: sRGBComponents(of: color))
    }

    /// `#rrggbb` of sRGB components, each clamped to 0...1, written through a table of digits.
    static func hexadecimal(components: SRGBComponents) -> String {
        let packed = packedHexadecimal(components: components)
        return String(unsafeUninitializedCapacity: 7) { characters in
            for index in 0..<7 { characters[index] = UInt8(truncatingIfNeeded: packed >> (index * 8)) }
            return 7
        }
    }

    /// `#rrggbb` of sRGB components as the low seven bytes of a word, the first byte lowest, as the document's writer
    /// stores it.
    static func packedHexadecimal(components: SRGBComponents) -> UInt64 {
        UInt64(UInt8(ascii: "#")) | channelDigits(components.red) << 8 | channelDigits(components.green) << 24 | channelDigits(components.blue) << 40
    }

    /// The two hexadecimal digits of a component clamped to 0...1, as a channel of 0 to 255, the first lowest.
    @inline(__always)
    private static func channelDigits(_ component: CGFloat) -> UInt64 {
        let channel = Int((min(1, max(0, component)) * 255).rounded())
        let digits = hexadecimalDigits.utf8Start
        return UInt64(digits[channel >> 4]) | UInt64(digits[channel & 0xF]) << 8
    }

    /// The sixteen hexadecimal digits in lower case, as `String(_:radix:)` writes them.
    private static let hexadecimalDigits: StaticString = "0123456789abcdef"

    /// The sRGB color space every color is converted to, made once.
    private static let sRGBColorSpace = CGColorSpace(name: CGColorSpace.sRGB)

    /// A color's red, green, blue and opacity in sRGB.
    struct SRGBComponents {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let opacity: CGFloat
    }

    /// Red, green, blue and opacity in sRGB; opaque black for a color with no sRGB form.
    static func sRGBComponents(of color: CGColor) -> SRGBComponents {
        guard let space = sRGBColorSpace,
              let components = color.converted(to: space, intent: .defaultIntent, options: nil)?.components, components.count == 4 else {
            return SRGBComponents(red: 0, green: 0, blue: 0, opacity: 1)
        }
        return SRGBComponents(red: components[0], green: components[1], blue: components[2], opacity: components[3])
    }
}
