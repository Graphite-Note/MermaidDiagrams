/**
 * File: DiagramSVGColors.swift
 * ----------------------------
 * Layer: Core
 * Description: How a scene's paints are written in SVG: in a palette's colors, or as Pele's CSS variables with Pele's
 *              colors as their fallbacks; each paint's text worked out once per document.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 23/11/2026
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
            return DiagramSVGPaintText(color: Self.hexadecimal(components: components), opacity: components[3])
        case .peleVariables:
            switch paint.source {
            case .role(let role): return DiagramSVGPaintText(color: Self.variable(role), opacity: paint.opacity)
            case .mixture(let from, let to, let share):
                let percentage = DiagramSVGSyntax.number(share * 100)
                return DiagramSVGPaintText(color: "color-mix(in srgb,\(Self.variable(from)),\(Self.variable(to)) \(percentage)%)", opacity: paint.opacity)
            case .color(let written):
                return DiagramSVGPaintText(color: Self.hexadecimal(written), opacity: CGFloat(written.alpha) * paint.opacity)
            }
        }
    }

    /// The colors a scene is written in: a palette with the series the diagram's theme variables set in their colors, or
    /// Pele's variables, which `seriesStyle(of:)` sets.
    func overSeriesColors(of scene: DiagramScene) -> DiagramSVGColors {
        switch self {
        case .palette(let palette): .palette(scene.palette(over: palette))
        case .peleVariables: .peleVariables
        }
    }

    /// The declarations of the series the diagram's theme variables set, as Pele ends its root's style with them
    /// (`;--pele-series-1:#ffeb3b`), with Pele's variables; nothing when every color is written out.
    func seriesStyle(of scene: DiagramScene) -> String {
        switch self {
        case .palette: ""
        case .peleVariables: scene.seriesColors.styleDeclarations
        }
    }

    /// The root's colors in this mode: Pele's aliases, or nothing when every color is written out.
    var rootStyle: String {
        switch self {
        case .palette: ""
        case .peleVariables: Self.peleRootStyle + ";"
        }
    }

    /// A role as Pele's variable, through its alias where Pele sets one.
    static func variable(_ role: DiagramPaletteRole) -> String {
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
        case .series(let index): seriesVariables[seriesSlot(index)]
        }
    }

    /// Pele's eight series variables with Pele's colors as their fallbacks (`var(--pele-series-1,#…)`), spelled out once.
    private static let seriesVariables: [String] = DiagramPalette.peleSeries.indices.map { slot in
        "var(--pele-series-\(slot + 1),\(hexadecimal(DiagramPalette.peleSeries[slot])))"
    }

    /// Which of Pele's eight series variables a series index takes, the colors taken in turn.
    private static func seriesSlot(_ index: Int) -> Int {
        ((index % DiagramPalette.peleSeries.count) + DiagramPalette.peleSeries.count) % DiagramPalette.peleSeries.count
    }

    /// `#rrggbb` in sRGB; black for a color with no sRGB form.
    static func hexadecimal(_ color: CGColor) -> String {
        hexadecimal(components: sRGBComponents(of: color))
    }

    /// `#rrggbb` of a written color, whose components are already sRGB's: Core Graphics gives a color made in sRGB the
    /// same components back when it converts it to sRGB.
    static func hexadecimal(_ color: DiagramColor) -> String {
        hexadecimal(red: color.red, green: color.green, blue: color.blue)
    }

    /// `#rrggbb` of the first three of sRGB components, each clamped to 0...1.
    private static func hexadecimal(components: [CGFloat]) -> String {
        hexadecimal(red: components[0], green: components[1], blue: components[2])
    }

    /// `#rrggbb` of three sRGB components, each clamped to 0...1 and rounded to a byte, in lowercase digits.
    private static func hexadecimal(red: CGFloat, green: CGFloat, blue: CGFloat) -> String {
        let digits: StaticString = "0123456789abcdef"
        var text = [UInt8](repeating: UInt8(ascii: "#"), count: 7)
        for (index, component) in [red, green, blue].enumerated() {
            let channel = Int((min(1, max(0, component)) * 255).rounded())
            text[1 + 2 * index] = digits.utf8Start[channel >> 4]
            text[2 + 2 * index] = digits.utf8Start[channel & 0xF]
        }
        return String(decoding: text, as: UTF8.self)
    }

    /// The sRGB color space every color is converted to, made once.
    private static let sRGBColorSpace = CGColorSpace(name: CGColorSpace.sRGB)

    /// Red, green, blue and opacity in sRGB; opaque black for a color with no sRGB form.
    private static func sRGBComponents(of color: CGColor) -> [CGFloat] {
        guard let space = sRGBColorSpace,
              let components = color.converted(to: space, intent: .defaultIntent, options: nil)?.components, components.count == 4 else {
            return [0, 0, 0, 1]
        }
        return components
    }
}

/// The text of each paint of one document, worked out the first time the paint is written: a palette's colors are
/// converted to sRGB and a series or mixture is spelled out once, not for every shape and text.
struct DiagramSVGPaintTexts {
    let colors: DiagramSVGColors
    private var textsByPaint: [DiagramPaint: DiagramSVGPaintText] = [:]

    init(colors: DiagramSVGColors) {
        self.colors = colors
    }

    mutating func text(of paint: DiagramPaint) -> DiagramSVGPaintText {
        if case .peleVariables = colors, case .role(let role) = paint.source, role.isNamedByPeleAlone {
            return DiagramSVGPaintText(color: DiagramSVGColors.variable(role), opacity: paint.opacity)
        }
        if let text = textsByPaint[paint] { return text }
        let text = colors.text(of: paint)
        textsByPaint[paint] = text
        return text
    }
}

private extension DiagramPaletteRole {
    /// Whether Pele's variable for the role is a fixed text (every role but a series, whose text carries its color).
    var isNamedByPeleAlone: Bool {
        if case .series = self { return false }
        return true
    }
}
