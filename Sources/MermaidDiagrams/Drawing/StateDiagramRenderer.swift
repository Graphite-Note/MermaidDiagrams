/**
 * File: StateDiagramRenderer.swift
 * --------------------------------
 * Layer: Core
 * Description: Draws a laid-out state diagram into a Core Graphics context, from its scene.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

import CoreGraphics

/// Draws a laid-out state diagram into a Core Graphics context whose origin is the layout's top left and whose y runs
/// down (a flipped bitmap, a PDF page), back to front, by painting its scene (`DiagramScene(layout:)`) with
/// `DiagramSceneRenderer`. Nothing is parsed or measured here, so drawing again in other colors is cheap.
public enum StateDiagramRenderer {
    public static func draw(_ layout: StateDiagramLayout, in context: CGContext, palette: DiagramPalette) {
        DiagramSceneRenderer.draw(DiagramScene(layout: layout), in: context, palette: palette)
    }
}

extension DiagramPalette {
    /// How far from the background toward the text a note's text is: Pele's muted gray, #6e6e6e, between its white
    /// page and its #1f1f1f text.
    public static let noteTextShare: CGFloat = 0.65

    /// The color of a note's text: between the background and the text, so that a note reads as an aside.
    public var noteText: CGColor {
        guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB),
              let backgroundComponents = background.converted(to: sRGB, intent: .defaultIntent, options: nil)?.components,
              let foregroundComponents = foreground.converted(to: sRGB, intent: .defaultIntent, options: nil)?.components,
              backgroundComponents.count == foregroundComponents.count else { return foreground }
        let mixed = zip(backgroundComponents, foregroundComponents).map { backgroundComponent, foregroundComponent in
            backgroundComponent + (foregroundComponent - backgroundComponent) * Self.noteTextShare
        }
        return CGColor(colorSpace: sRGB, components: mixed) ?? foreground
    }
}
