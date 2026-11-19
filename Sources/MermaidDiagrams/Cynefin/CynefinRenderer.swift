/**
 * File: CynefinRenderer.swift
 * ---------------------------
 * Layer: Core
 * Description: Draws a laid-out Cynefin framework into a Core Graphics context, from its scene.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// Draws a laid-out Cynefin framework into a Core Graphics context whose origin is the layout's top left and whose y runs
/// down, back to front, by painting its scene (`DiagramScene(layout:)`) with `DiagramSceneRenderer`.
public enum CynefinRenderer {
    public static func draw(_ layout: CynefinLayout, in context: CGContext, palette: DiagramPalette) {
        DiagramSceneRenderer.draw(DiagramScene(layout: layout), in: context, palette: palette)
    }
}
