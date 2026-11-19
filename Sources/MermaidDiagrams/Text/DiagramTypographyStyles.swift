/**
 * File: DiagramTypographyStyles.swift
 * -----------------------------------
 * Layer: Core
 * Description: A measurer of a typography's font at any size and style: one it already holds when it matches, else one
 *              made for it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

extension DiagramTypography {
    /// The font at `size`, bold, italic or the system's monospaced font: the typography's own measurer when it holds
    /// one of that size and style, else a new one, for the sizes a diagram's options set.
    func measurer(size: CGFloat, isBold: Bool = false, isItalic: Bool = false, isMonospaced: Bool = false) -> CoreTextDiagramTextMeasurer {
        let held: [(measurer: CoreTextDiagramTextMeasurer, isBold: Bool, isItalic: Bool, isMonospaced: Bool)] = [
            (nodeText, false, false, false), (edgeText, false, false, false), (boldNodeText, true, false, false), (smallText, false, false, false),
            (rowText, false, false, false), (axisText, false, false, false), (boldEdgeText, true, false, false), (boldRowText, true, false, false),
            (monospacedEdgeText, false, false, true), (monospacedAxisText, false, false, true), (italicEdgeText, false, true, false),
        ]
        if let match = held.first(where: { candidate in
            candidate.measurer.fontSize == size && candidate.isBold == isBold && candidate.isItalic == isItalic && candidate.isMonospaced == isMonospaced
        }) {
            return match.measurer
        }
        return CoreTextDiagramTextMeasurer(font: font.resized(to: size), isBold: isBold, isItalic: isItalic, isMonospaced: isMonospaced)
    }
}
