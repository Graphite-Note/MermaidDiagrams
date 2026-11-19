/**
 * File: SequenceTextInk.swift
 * ---------------------------
 * Layer: Core
 * Description: The text color Pele picks for text on a colored sequence box: its dark text on light colors, white on
 *              dark ones, by which contrasts more.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import Foundation

/// Pele's `ink` (`src/svg/ink.ts`) for a fill it knows: `--pele-fg-on-light` (#1f1f1f) on a fill whose relative
/// luminance is above the point where #1f1f1f and white contrast with it equally, `--pele-fg-on-dark` (white) below it;
/// none for a fill under half opacity, whose look depends on what is behind it.
enum SequenceTextInk {
    static let onLight = DiagramColor(red: 31.0 / 255, green: 31.0 / 255, blue: 31.0 / 255)
    static let onDark = DiagramColor(red: 1, green: 1, blue: 1)

    /// The text color on `fill`, or nil when Pele picks none.
    static func ink(on fill: SequenceHighlightColor?) -> DiagramColor? {
        guard let fill, fill.alpha >= 0.5 else { return nil }
        return luminance(red: fill.red, green: fill.green, blue: fill.blue) > evenContrastLuminance ? onLight : onDark
    }

    /// The luminance at which #1f1f1f and white contrast equally with a color.
    private static let evenContrastLuminance: Double = {
        let dark = luminance(red: 31.0 / 255, green: 31.0 / 255, blue: 31.0 / 255)
        return (1.05 * (dark + 0.05)).squareRoot() - 0.05
    }()

    /// WCAG's relative luminance of an sRGB color.
    private static func luminance(red: Double, green: Double, blue: Double) -> Double {
        func linear(_ channel: Double) -> Double { channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
}
