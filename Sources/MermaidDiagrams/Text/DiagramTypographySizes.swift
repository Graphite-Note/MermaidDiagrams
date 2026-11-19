/**
 * File: DiagramTypographySizes.swift
 * ----------------------------------
 * Layer: Core
 * Description: Measurers for a text size a chart's options give, kept as the typography's own when the size is one of its.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

extension DiagramTypography {
    /// The measurer for the diagram's font at `size`, bold or not: one the typography already holds when `size` is one of
    /// its sizes, so that a chart whose options give the size it has anyway does not read a font's advances again.
    func measurer(ofSize size: CGFloat, isBold: Bool = false) -> CoreTextDiagramTextMeasurer {
        let held = isBold ? [boldNodeText] : [nodeText, edgeText, axisText, smallText, rowText]
        if let measurer = held.first(where: { measurer in measurer.fontSize == size }) { return measurer }
        return CoreTextDiagramTextMeasurer(font: font.resized(to: size), isBold: isBold)
    }
}
