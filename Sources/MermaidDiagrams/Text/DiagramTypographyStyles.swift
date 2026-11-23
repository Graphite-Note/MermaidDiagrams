/**
 * File: DiagramTypographyStyles.swift
 * -----------------------------------
 * Layer: Core
 * Description: A measurer of a typography's font at any size and style: one it already holds when it matches, else one
 *              made for it.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import CoreGraphics

extension DiagramTypography {
    /// The font at `size`, bold, italic or the system's monospaced font: the typography's own measurer when it holds
    /// one of that size and style, else a new one, for the sizes a diagram's options set.
    func measurer(size: CGFloat, isBold: Bool = false, isItalic: Bool = false, isMonospaced: Bool = false) -> CoreTextDiagramTextMeasurer {
        // The held measurers in this order, the first of the size and emphasis asked for; looked through without making
        // a list of them at every call.
        switch (isBold, isItalic, isMonospaced) {
        case (false, false, false):
            if nodeText.fontSize == size { return nodeText }
            if edgeText.fontSize == size { return edgeText }
            if smallText.fontSize == size { return smallText }
            if rowText.fontSize == size { return rowText }
            if axisText.fontSize == size { return axisText }
        case (true, false, false):
            if boldNodeText.fontSize == size { return boldNodeText }
            if boldEdgeText.fontSize == size { return boldEdgeText }
            if boldRowText.fontSize == size { return boldRowText }
        case (false, false, true):
            if monospacedEdgeText.fontSize == size { return monospacedEdgeText }
            if monospacedAxisText.fontSize == size { return monospacedAxisText }
        case (false, true, false):
            if italicEdgeText.fontSize == size { return italicEdgeText }
        default:
            break
        }
        return CoreTextDiagramTextMeasurer(font: font.resized(to: size), isBold: isBold, isItalic: isItalic, isMonospaced: isMonospaced)
    }
}
