/**
 * File: QuadrantChartRenderer.swift
 * ---------------------------------
 * Layer: Core
 * Description: Draws a laid-out quadrant chart into a Core Graphics context, from its scene.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

import CoreGraphics

/// Draws a laid-out quadrant chart into a Core Graphics context whose origin is the layout's top left and whose y runs
/// down (a flipped bitmap, a PDF page), back to front, by painting its scene (`DiagramScene(layout:)`) with
/// `DiagramSceneRenderer`. Nothing is parsed or measured here, so drawing again in other colors is cheap.
public enum QuadrantChartRenderer {
    public static func draw(_ layout: QuadrantChartLayout, in context: CGContext, palette: DiagramPalette) {
        DiagramSceneRenderer.draw(DiagramScene(layout: layout), in: context, palette: palette)
    }

    /// The color a point's paint stands for in `palette`.
    public static func color(_ paint: QuadrantChartPaint, in palette: DiagramPalette) -> CGColor {
        QuadrantChartDrawingParts.paint(paint).color(in: palette)
    }
}
