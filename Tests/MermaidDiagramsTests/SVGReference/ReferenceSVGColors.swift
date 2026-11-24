/**
 * File: ReferenceSVGColors.swift
 * ------------------------------
 * Layer: Tests
 * Description: 0.7.0's paint texts and sRGB hexadecimal colors (DiagramSVGColors of de81532), kept unchanged but
 *              for their names as part of the reference writer.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// A paint as SVG writes it: its color and the opacity it is painted at.
struct ReferenceSVGPaintText {
    let color: String
    let opacity: CGFloat
}

extension DiagramSVGColors {
    /// Pele's private aliases of its variables, set once on the root element so that each use is short.
    static let referencePeleRootStyle = "--_bg:var(--pele-bg,#fff);--_fg:var(--pele-fg,#1f1f1f);--_m:var(--pele-muted,#6e6e6e);"
        + "--_l:var(--pele-line,#1f1f1f);--_s:var(--pele-surface,#f3f3f3);--_a:var(--pele-surface-alt,#e6e6e6);"
        + "--_b:var(--pele-border,#8a8a8a);--_c:var(--pele-accent,#5b7bd5);color:var(--_fg)"

    func referenceText(of paint: DiagramPaint) -> ReferenceSVGPaintText {
        switch self {
        case .palette(let palette):
            let components = Self.referenceSRGBComponents(of: paint.color(in: palette))
            return ReferenceSVGPaintText(color: Self.referenceHexadecimal(components: components), opacity: components.opacity)
        case .peleVariables:
            switch paint.source {
            case .role(let role): return ReferenceSVGPaintText(color: Self.referenceVariable(role), opacity: paint.opacity)
            case .mixture(let from, let to, let share):
                let percentage = ReferenceSVGBuffer.number(share * 100)
                return ReferenceSVGPaintText(color: "color-mix(in srgb,\(Self.referenceVariable(from)),\(Self.referenceVariable(to)) \(percentage)%)", opacity: paint.opacity)
            case .color(let written):
                return ReferenceSVGPaintText(color: Self.referenceHexadecimal(written.cgColor), opacity: CGFloat(written.alpha) * paint.opacity)
            }
        }
    }

    /// The colors a scene is written in: a palette with the series the diagram's theme variables set in their colors, or
    /// Pele's variables, whose series the writer declares on the root's style as Pele does (`;--pele-series-1:#ffeb3b`,
    /// `DiagramSeriesColors.styleDeclarations`).
    func referenceOverSeriesColors(of scene: DiagramScene) -> DiagramSVGColors {
        switch self {
        case .palette(let palette): .palette(scene.palette(over: palette))
        case .peleVariables: .peleVariables
        }
    }

    /// The root's colors in this mode: Pele's aliases, or nothing when every color is written out.
    var referenceRootStyle: String {
        switch self {
        case .palette: ""
        case .peleVariables: Self.referencePeleRootStyle + ";"
        }
    }

    /// A role as Pele's variable, through its alias where Pele sets one.
    static func referenceVariable(_ role: DiagramPaletteRole) -> String {
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
        case .series(let index): referencePeleSeriesVariables[referenceSeriesSlot(index)]
        }
    }

    /// Pele's eight series variables, each with its color as the fallback (`var(--pele-series-1,#4c78a8)`):
    /// `DiagramPalette.peleSeries` in sRGB hexadecimal, as `referenceHexadecimal(_:)` writes them (which a test checks), so that a
    /// series paint is not spelled out again in every document.
    static let referencePeleSeriesVariables = [
        "var(--pele-series-1,#4c78a8)", "var(--pele-series-2,#f58518)", "var(--pele-series-3,#54a24b)", "var(--pele-series-4,#e45756)",
        "var(--pele-series-5,#72b7b2)", "var(--pele-series-6,#eeca3b)", "var(--pele-series-7,#b279a2)", "var(--pele-series-8,#9d755d)"
    ]

    /// Which of Pele's eight series variables a series index takes, the colors taken in turn.
    private static func referenceSeriesSlot(_ index: Int) -> Int {
        ((index % DiagramPalette.peleSeries.count) + DiagramPalette.peleSeries.count) % DiagramPalette.peleSeries.count
    }

    /// `#rrggbb` in sRGB; black for a color with no sRGB form.
    static func referenceHexadecimal(_ color: CGColor) -> String {
        referenceHexadecimal(components: referenceSRGBComponents(of: color))
    }

    /// `#rrggbb` of sRGB components, each clamped to 0...1, written through a table of digits.
    private static func referenceHexadecimal(components: ReferenceSRGBComponents) -> String {
        String(unsafeUninitializedCapacity: 7) { characters in
            characters[0] = UInt8(ascii: "#")
            referenceWriteChannel(components.red, into: characters, at: 1)
            referenceWriteChannel(components.green, into: characters, at: 3)
            referenceWriteChannel(components.blue, into: characters, at: 5)
            return 7
        }
    }

    /// The two hexadecimal digits of a component clamped to 0...1, as a channel of 0 to 255.
    private static func referenceWriteChannel(_ component: CGFloat, into characters: UnsafeMutableBufferPointer<UInt8>, at index: Int) {
        let channel = Int((min(1, max(0, component)) * 255).rounded())
        let digits = referenceHexadecimalDigits.utf8Start
        characters[index] = digits[channel >> 4]
        characters[index + 1] = digits[channel & 0xF]
    }

    /// The sixteen hexadecimal digits in lower case, as `String(_:radix:)` writes them.
    private static let referenceHexadecimalDigits: StaticString = "0123456789abcdef"

    /// The sRGB color space every color is converted to, made once.
    private static let referenceSRGBColorSpace = CGColorSpace(name: CGColorSpace.sRGB)

    /// A color's red, green, blue and opacity in sRGB.
    struct ReferenceSRGBComponents {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let opacity: CGFloat
    }

    /// Red, green, blue and opacity in sRGB; opaque black for a color with no sRGB form.
    private static func referenceSRGBComponents(of color: CGColor) -> ReferenceSRGBComponents {
        guard let space = referenceSRGBColorSpace,
              let components = color.converted(to: space, intent: .defaultIntent, options: nil)?.components, components.count == 4 else {
            return ReferenceSRGBComponents(red: 0, green: 0, blue: 0, opacity: 1)
        }
        return ReferenceSRGBComponents(red: components[0], green: components[1], blue: components[2], opacity: components[3])
    }
}

/// The text of each paint of one document, worked out the first time the paint is written: a palette's colors are
/// converted to sRGB and a mixture or a written color is spelled out once, not for every shape and text. With Pele's
/// variables a role's text is fixed (a series' from its table) and is never looked up. A document has few paints, so the
/// first ones are found by comparing them in turn, which hashes nothing; past `scannedPaintCount` they are hashed.
struct ReferenceSVGPaintTexts {
    let colors: DiagramSVGColors
    private var scannedPaints: [(paint: DiagramPaint, text: ReferenceSVGPaintText)] = []
    private var textsByPaint: [DiagramPaint: ReferenceSVGPaintText] = [:]

    /// How many paints are kept to be compared in turn before the rest are hashed.
    static let scannedPaintCount = 24

    init(colors: DiagramSVGColors) {
        self.colors = colors
    }

    mutating func referenceText(of paint: DiagramPaint) -> ReferenceSVGPaintText {
        if case .peleVariables = colors, case .role(let role) = paint.source {
            return ReferenceSVGPaintText(color: DiagramSVGColors.referenceVariable(role), opacity: paint.opacity)
        }
        for entry in scannedPaints where entry.paint == paint { return entry.text }
        if scannedPaints.count < Self.scannedPaintCount {
            let text = colors.referenceText(of: paint)
            if scannedPaints.isEmpty { scannedPaints.reserveCapacity(Self.scannedPaintCount) }
            scannedPaints.append((paint, text))
            return text
        }
        if let text = textsByPaint[paint] { return text }
        let text = colors.referenceText(of: paint)
        textsByPaint[paint] = text
        return text
    }
}
