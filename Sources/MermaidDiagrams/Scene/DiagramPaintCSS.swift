/**
 * File: DiagramPaintCSS.swift
 * ---------------------------
 * Layer: Core
 * Description: A paint read from a CSS color a diagram's options write: a color, or a CSS variable of Pele's palette
 *              the page resolves.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

extension DiagramPaint {
    /// The paint a CSS color stands for where Pele writes it into a style (`fill:…`): a color `DiagramColor` reads (a
    /// hexadecimal color, `rgb()`, a CSS color name), or `var(--name)` with an optional fallback, which the page resolves:
    /// a variable of Pele's palette (`--pele-bg`, `--pele-accent`, `--pele-series-1` to `--pele-series-8` and the others,
    /// and Pele's own short names on its SVG, `--_bg`, `--_c` …) is that role of the palette; any other variable stands for
    /// its fallback. Nil for anything else, which a browser leaves unpainted.
    init?(cssColor written: String) {
        let text = written.trimmingCharacters(in: .whitespaces)
        guard text.lowercased().hasPrefix("var("), text.hasSuffix(")") else {
            guard let color = DiagramColor(cssText: text) else { return nil }
            self = .color(color)
            return
        }
        let inside = text.dropFirst(4).dropLast()
        let comma = inside.firstIndex(of: ",")
        let name = inside[..<(comma ?? inside.endIndex)].trimmingCharacters(in: .whitespaces)
        if let role = Self.paletteRole(variable: name) {
            self.init(role)
        } else if let comma, let fallback = DiagramPaint(cssColor: String(inside[inside.index(after: comma)...])) {
            self = fallback
        } else {
            return nil
        }
    }

    /// The palette role a variable of Pele's names, or nil.
    private static func paletteRole(variable name: String) -> DiagramPaletteRole? {
        if name.hasPrefix(seriesPrefix), let number = Int(name.dropFirst(seriesPrefix.count)), (1...DiagramPalette.peleSeries.count).contains(number) {
            return .series(number - 1)
        }
        return paletteRoles[name]
    }

    private static let seriesPrefix = "--pele-series-"
    private static let paletteRoles: [String: DiagramPaletteRole] = [
        "--pele-bg": .background, "--_bg": .background, "--pele-fg": .foreground, "--_fg": .foreground, "--pele-line": .line, "--_l": .line,
        "--pele-surface": .surface, "--_s": .surface, "--pele-surface-alt": .alternateSurface, "--_a": .alternateSurface,
        "--pele-border": .border, "--_b": .border, "--pele-accent": .accent, "--_c": .accent, "--pele-muted": .muted, "--_m": .muted,
        "--pele-critical": .critical,
    ]
}
