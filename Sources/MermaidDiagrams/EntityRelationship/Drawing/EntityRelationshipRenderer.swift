/**
 * File: EntityRelationshipRenderer.swift
 * --------------------------------------
 * Layer: Core
 * Description: Draws an laid-out entity relationship diagram into a Core Graphics context, from its scene.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

import CoreGraphics

/// Draws an laid-out entity relationship diagram into a Core Graphics context whose origin is the layout's top left and whose y runs
/// down (a flipped bitmap, a PDF page), back to front, by painting its scene (`DiagramScene(layout:)`) with
/// `DiagramSceneRenderer`. Nothing is parsed or measured here, so drawing again in other colors is cheap.
public enum EntityRelationshipRenderer {
    public static func draw(_ layout: EntityRelationshipLayout, in context: CGContext, palette: DiagramPalette) {
        DiagramSceneRenderer.draw(DiagramScene(layout: layout), in: context, palette: palette)
    }
}
