/**
 * File: DiagramSeriesColors.swift
 * -------------------------------
 * Layer: Core
 * Description: The series colors a diagram's own theme variables set and the label ink on each, carried by its scene so
 *              that whatever palette paints it, those series are painted in the diagram's colors, as Pele's style sets them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import CoreGraphics

/// The colors a diagram's theme variables give its eight series (`pie1` … for a pie chart, `git0` … for a Git graph,
/// `cScale0` … for a timeline, radar chart and treemap, `cScale1` … for a mindmap, `venn1` … repeated for a Venn diagram,
/// `xyChart.plotColorPalette` for an XY chart), as Pele's palette.ts reads them: Pele sets them on its SVG as
/// `--pele-series-1` to `--pele-series-8`, over the page's own. A series they leave unset keeps its palette's color, and
/// so does one whose value is not a color Pele accepts. With each color, the label ink Pele draws text on it in, where
/// the color's contrast is known.
public struct DiagramSeriesColors: Hashable, Sendable {
    /// Pele's series variables: series past the eighth take the colors again in turn.
    public static let slotCount = 8
    /// No series color set: the palette's own colors throughout.
    public static let none = DiagramSeriesColors(colors: [])

    /// Eight entries: each slot's color, nil where the palette's own stays.
    public let colors: [DiagramThemeColor?]
    /// Eight entries: the color Pele writes text on each slot's color in, `#1f1f1f` on a light color and white on a dark
    /// one; nil where no color is set or its contrast is not known (a `var()`, a `color-mix()`, a color under half
    /// opacity), where the type's own text color stays.
    public let inks: [DiagramColor?]

    /// The colors of the first slots in order, nil for a slot left unset; past eight they are left out.
    public init(colors: [DiagramThemeColor?]) {
        let slots = Array(colors.prefix(Self.slotCount)) + Array(repeating: nil, count: max(0, Self.slotCount - colors.count))
        self.colors = slots
        inks = slots.map { color in color.flatMap { color in DiagramSeriesInk.ink(on: color.cssText) } }
    }

    /// Whether no slot is set.
    public var isEmpty: Bool {
        colors.allSatisfy { color in color == nil }
    }

    /// The slot a series index takes: the eight in turn.
    public static func slot(ofSeries index: Int) -> Int {
        ((index % slotCount) + slotCount) % slotCount
    }

    /// The color set for the series at `index`, or nil.
    public func color(ofSeries index: Int) -> DiagramThemeColor? {
        colors[Self.slot(ofSeries: index)]
    }

    /// The ink for text on the series at `index`, or nil where the type's own text color stays.
    public func ink(ofSeries index: Int) -> DiagramColor? {
        inks[Self.slot(ofSeries: index)]
    }

    /// The declarations Pele adds to its SVG root's style for these colors, each `;--pele-series-N:<color>`; empty when
    /// none is set.
    public var styleDeclarations: String {
        colors.enumerated().compactMap { slot, color in color.map { color in ";--pele-series-\(slot + 1):\(color.cssText)" } }.joined()
    }

    /// `palette` with the slots set here in their colors, resolved as a browser resolves Pele's variables over a page
    /// whose own are `palette`'s: `var(--pele-…)` as the palette's role or slot (a slot set here as its own color),
    /// `currentColor` as the foreground, `light-dark()` by whether the background is darker than the foreground, and
    /// `color-mix()` as CSS mixes. A value that refers to itself through other slots, or to a variable no palette sets
    /// without a fallback, is no color in a browser, which then paints Pele's own series color; one this package cannot
    /// resolve keeps the palette's color. The series become eight, the palette's colors taken in turn where none is set.
    public func palette(over palette: DiagramPalette) -> DiagramPalette {
        guard !isEmpty else { return palette }
        var resolution = DiagramThemeColorResolution(palette: palette, colors: colors)
        var painted = palette
        painted.series = (0..<Self.slotCount).map { slot in resolution.color(ofSlot: slot) }
        return painted
    }
}

/// Resolves the slots' colors over a palette, each slot once.
struct DiagramThemeColorResolution {
    /// What a value resolves to: a color, nothing (CSS's guaranteed-invalid value, which a use's fallback replaces), or a
    /// value this package does not resolve.
    enum Outcome {
        case color(DiagramLinearColor)
        case invalid
        case unsupported
    }

    let palette: DiagramPalette
    let colors: [DiagramThemeColor?]
    private let isDark: Bool
    private var resolvedSlots: [Int: Outcome] = [:]
    /// The slots whose values refer to themselves through others: each of them is no color, as CSS makes every custom
    /// property of a cycle, whatever fallbacks they give.
    private let slotsInCycles: Set<Int>

    init(palette: DiagramPalette, colors: [DiagramThemeColor?]) {
        self.palette = palette
        self.colors = colors
        slotsInCycles = Self.slotsInCycles(colors)
        let background = DiagramLinearColor(palette.background)
        let foreground = DiagramLinearColor(palette.foreground)
        isDark = (background.map(Self.luminance) ?? 1) < (foreground.map(Self.luminance) ?? 0)
    }

    /// A slot's color: its own where it resolves, Pele's series color where it is no color, the palette's where it is
    /// not resolved here or not set.
    mutating func color(ofSlot slot: Int) -> CGColor {
        switch outcome(ofSlot: slot) {
        case .color(let color): color.cgColor
        case .invalid: DiagramPalette.peleSeries[slot]
        case .unsupported: palette.seriesColor(at: slot)
        }
    }

    /// A slot's value resolved, each slot once.
    private mutating func outcome(ofSlot slot: Int) -> Outcome {
        if let resolved = resolvedSlots[slot] { return resolved }
        guard let color = colors[slot] else {
            return DiagramLinearColor(palette.seriesColor(at: slot)).map(Outcome.color) ?? .unsupported
        }
        let resolved = slotsInCycles.contains(slot) ? Outcome.invalid : outcome(of: color.expression)
        resolvedSlots[slot] = resolved
        return resolved
    }

    /// The slots that reach themselves through the slots their values refer to.
    private static func slotsInCycles(_ colors: [DiagramThemeColor?]) -> Set<Int> {
        let count = colors.count
        var reaches = colors.map { color in
            let referenced = color?.expression.referencedSlots ?? []
            return (0..<count).map { slot in referenced.contains(slot) && colors[slot] != nil }
        }
        for middle in 0..<count {
            for start in 0..<count where reaches[start][middle] {
                for end in 0..<count where reaches[middle][end] { reaches[start][end] = true }
            }
        }
        return Set((0..<count).filter { slot in reaches[slot][slot] })
    }

    private mutating func outcome(of expression: DiagramThemeColorExpression) -> Outcome {
        switch expression {
        case .color(let color): return .color(color)
        case .currentColor: return role(.foreground)
        case .role(let role): return self.role(role)
        case .series(let slot, let fallback):
            let referenced = outcome(ofSlot: slot)
            guard case .invalid = referenced, let fallback else { return referenced }
            return outcome(of: fallback)
        case .unknownVariable(let fallback): return fallback.map { fallback in outcome(of: fallback) } ?? .invalid
        case .lightDark(let light, let dark): return outcome(of: isDark ? dark : light)
        case .mixture(let mixture):
            let first = outcome(of: mixture.first)
            let second = outcome(of: mixture.second)
            guard case .color(let firstColor) = first, case .color(let secondColor) = second else {
                if case .unsupported = first { return .unsupported }
                if case .unsupported = second { return .unsupported }
                return .invalid
            }
            return mixture.mixed(firstColor, secondColor).map(Outcome.color) ?? .invalid
        case .unsupported: return .unsupported
        }
    }

    private func role(_ role: DiagramPaletteRole) -> Outcome {
        DiagramLinearColor(role.color(in: palette)).map(Outcome.color) ?? .unsupported
    }

    private static func luminance(_ color: DiagramLinearColor) -> Double {
        0.2126 * color.red + 0.7152 * color.green + 0.0722 * color.blue
    }
}
