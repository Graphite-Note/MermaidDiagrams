/**
 * File: PlaneMapTypography.swift
 * ------------------------------
 * Layer: Core
 * Description: The bold and italic text sizes Cynefin frameworks and Wardley maps measure in, Pele's, made once per font
 *              with the typography's other measurers.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// The measurers the diagrams drawn on a fixed plane need beyond the typography's own, each Pele's size rounded: a
/// Cynefin domain's subtitles in thirteen sixteenths of the size in italic; a Wardley map's anchors, notes and axis titles
/// in thirteen sixteenths in bold, its annotation numbers in eleven sixteenths in bold (Pele's `tiny`), its link labels
/// one point larger, and its forces one point larger in bold.
struct PlaneMapTypography {
    let italicRowText: CoreTextDiagramTextMeasurer
    let boldRowText: CoreTextDiagramTextMeasurer
    let boldSmallestText: CoreTextDiagramTextMeasurer
    let linkText: CoreTextDiagramTextMeasurer
    let boldLinkText: CoreTextDiagramTextMeasurer

    /// Pele's `tiny` in a Wardley map: 11 points at 16.
    static let smallestTextScale: CGFloat = 0.6875

    init(font: DiagramFont) {
        let row = font.resized(to: (font.size * DiagramTypography.rowTextScale).rounded())
        let smallest = font.resized(to: (font.size * Self.smallestTextScale).rounded())
        let link = font.resized(to: smallest.size + 1)
        italicRowText = CoreTextDiagramTextMeasurer(font: row, isBold: false, isItalic: true)
        boldRowText = CoreTextDiagramTextMeasurer(font: row, isBold: true)
        boldSmallestText = CoreTextDiagramTextMeasurer(font: smallest, isBold: true)
        linkText = CoreTextDiagramTextMeasurer(font: link)
        boldLinkText = CoreTextDiagramTextMeasurer(font: link, isBold: true)
    }
}
