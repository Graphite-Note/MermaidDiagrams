/**
 * File: DiagramPaint.swift
 * ------------------------
 * Layer: Core
 * Description: A color a scene names by its role in a palette, a mixture of two roles, or a color the diagram's text
 *              set, at an opacity, resolved only when it is drawn.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// A role of `DiagramPalette`, by Pele's variables (`--pele-bg` and the others).
public enum DiagramPaletteRole: Hashable, Sendable {
    case background
    case foreground
    case line
    case surface
    case border
    case accent
    case critical
    case muted
    case alternateSurface
    /// The series color at an index, the palette's colors taken in turn (`DiagramPalette.seriesColor(at:)`).
    case series(Int)

    /// The role's color in `palette`.
    public func color(in palette: DiagramPalette) -> CGColor {
        switch self {
        case .background: palette.background
        case .foreground: palette.foreground
        case .line: palette.line
        case .surface: palette.surface
        case .border: palette.border
        case .accent: palette.accent
        case .critical: palette.critical
        case .muted: palette.muted
        case .alternateSurface: palette.alternateSurface
        case .series(let index): palette.seriesColor(at: index)
        }
    }
}

/// What a shape or a text is painted in: a palette's role, a mixture of two, or a color the diagram's own text set
/// (a flowchart's `style`, a quadrant chart's point colors), at an opacity. It stays a role until it is drawn, so a scene
/// is painted in any palette.
public struct DiagramPaint: Hashable, Sendable {
    public enum Source: Hashable, Sendable {
        case role(DiagramPaletteRole)
        /// `share` of the way from one role's color to the other's, channel by channel in sRGB (opacity too), as Pele's
        /// colors between its page and its text are.
        case mixture(from: DiagramPaletteRole, to: DiagramPaletteRole, share: CGFloat)
        /// A color the diagram's text gave.
        case color(DiagramColor)
    }

    public let source: Source
    /// Multiplies the color's own opacity.
    public let opacity: CGFloat

    public init(source: Source, opacity: CGFloat = 1) {
        self.source = source
        self.opacity = opacity
    }

    public init(_ role: DiagramPaletteRole, opacity: CGFloat = 1) {
        self.init(source: .role(role), opacity: opacity)
    }

    public static let background = DiagramPaint(.background)
    public static let foreground = DiagramPaint(.foreground)
    public static let line = DiagramPaint(.line)
    public static let surface = DiagramPaint(.surface)
    public static let border = DiagramPaint(.border)
    public static let accent = DiagramPaint(.accent)
    public static let critical = DiagramPaint(.critical)
    public static let muted = DiagramPaint(.muted)
    public static let alternateSurface = DiagramPaint(.alternateSurface)

    /// The series color at `index`.
    public static func series(_ index: Int) -> DiagramPaint {
        DiagramPaint(.series(index))
    }

    /// `share` of the way from the background to the foreground.
    public static func betweenBackgroundAndForeground(share: CGFloat) -> DiagramPaint {
        DiagramPaint(source: .mixture(from: .background, to: .foreground, share: share))
    }

    /// A color the diagram's text gave.
    public static func color(_ color: DiagramColor) -> DiagramPaint {
        DiagramPaint(source: .color(color))
    }

    /// The same paint at `opacity` times its opacity.
    public func atOpacity(_ opacity: CGFloat) -> DiagramPaint {
        DiagramPaint(source: source, opacity: self.opacity * opacity)
    }

    /// The paint's color in `palette`.
    public func color(in palette: DiagramPalette) -> CGColor {
        let color: CGColor
        switch source {
        case .role(let role): color = role.color(in: palette)
        case .mixture(let from, let to, let share): color = Self.mixed(from.color(in: palette), to.color(in: palette), share: share)
        case .color(let written): color = written.cgColor
        }
        guard opacity != 1 else { return color }
        return color.copy(alpha: color.alpha * opacity) ?? color
    }

    /// `share` of the way from `start` to `end`, channel by channel in sRGB; `end` when either has no sRGB form.
    static func mixed(_ start: CGColor, _ end: CGColor, share: CGFloat) -> CGColor {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let startComponents = start.converted(to: space, intent: .defaultIntent, options: nil)?.components,
              let endComponents = end.converted(to: space, intent: .defaultIntent, options: nil)?.components,
              startComponents.count == 4, endComponents.count == 4 else { return end }
        let components = zip(startComponents, endComponents).map { from, to in from + (to - from) * share }
        return CGColor(srgbRed: components[0], green: components[1], blue: components[2], alpha: components[3])
    }
}
