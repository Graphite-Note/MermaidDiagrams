/**
 * File: InfoDiagramRenderer.swift
 * -------------------------------
 * Layer: Core
 * Description: Draws a laid-out info diagram into a Core Graphics context, from its scene.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// Draws a laid-out info diagram into a Core Graphics context whose origin is the layout's top left and whose y runs
/// down (a flipped bitmap, a PDF page), by painting its scene (`DiagramScene(layout:)`) with `DiagramSceneRenderer`.
public enum InfoDiagramRenderer {
    public static func draw(_ layout: InfoDiagramLayout, in context: CGContext, palette: DiagramPalette) {
        DiagramSceneRenderer.draw(DiagramScene(layout: layout), in: context, palette: palette)
    }
}
