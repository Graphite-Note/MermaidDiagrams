/**
 * File: DiagramScenePaletteSamples.swift
 * --------------------------------------
 * Layer: Tests
 * Description: The light and dark palettes the scene tests paint in: Pele's own colors, and a dark theme's with colors
 *              of its own for every role.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// The palettes the scene tests paint in.
enum DiagramScenePaletteSamples {
    static let light = DiagramPalette.peleLight

    /// A dark page whose every role is a color of its own, so a role painted in the place of another shows.
    static let dark = DiagramPalette(background: gray(0x1E), foreground: gray(0xDA), line: CGColor(srgbRed: 0.85, green: 0.8, blue: 0.7, alpha: 1),
                                     surface: gray(0x2A), border: gray(0x6B), accent: CGColor(srgbRed: 0.4, green: 0.6, blue: 0.95, alpha: 1),
                                     critical: CGColor(srgbRed: 0.95, green: 0.4, blue: 0.4, alpha: 1), muted: gray(0x99), alternateSurface: gray(0x33))

    private static func gray(_ level: Int) -> CGColor {
        let component = CGFloat(level) / 255
        return CGColor(srgbRed: component, green: component, blue: component, alpha: 1)
    }
}
