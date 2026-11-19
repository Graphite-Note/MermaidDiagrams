/**
 * File: DiagramTypography.swift
 * -----------------------------
 * Layer: Core
 * Description: The measurers of a diagram's font at the sizes and in the styles its types draw text in, made once per
 *              font.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

import CoreGraphics

/// The fonts a diagram's text is measured in: the nodes' font, its bold, and the smaller ones of edges, annotations,
/// chart rows and axes. Made once for a font and
/// used for every diagram drawn in it, since reading a font's advances costs more than laying a diagram out.
public struct DiagramTypography {
    public let font: DiagramFont
    let nodeText: CoreTextDiagramTextMeasurer
    let edgeText: CoreTextDiagramTextMeasurer
    /// The nodes' font in bold: a class's name, measured as it is drawn.
    let boldNodeText: CoreTextDiagramTextMeasurer
    /// Four fifths of the nodes' size, rounded: a class's annotations and a relation's cardinalities, as in Pele.
    let smallText: CoreTextDiagramTextMeasurer
    /// The text of a chart's rows, such as a Gantt chart's tasks and sections: thirteen sixteenths of the size.
    let rowText: CoreTextDiagramTextMeasurer
    /// The dates of a chart's axis: three quarters of the size.
    let axisText: CoreTextDiagramTextMeasurer
    /// The bold and italic sizes of the diagrams drawn on a fixed plane: Cynefin frameworks and Wardley maps.
    let planeMapText: PlaneMapTypography
    /// The edges' size in bold: an event model's frame names and its narrow column's lane and card headings.
    let boldEdgeText: CoreTextDiagramTextMeasurer
    /// The rows' size in bold: an event model's lane names and card headings.
    let boldRowText: CoreTextDiagramTextMeasurer
    /// The system's monospaced font at the edges' size (a railroad diagram's terminals) and at the axes' (an event
    /// model's data), and the edges' size in italic (a railroad diagram's special sequences).
    let monospacedEdgeText: CoreTextDiagramTextMeasurer
    let monospacedAxisText: CoreTextDiagramTextMeasurer
    let italicEdgeText: CoreTextDiagramTextMeasurer

    /// Edge text is seven eighths of the nodes' size, rounded, as in Pele.
    static let edgeTextScale: CGFloat = 0.875
    static let smallTextScale: CGFloat = 0.8
    /// Pele's Gantt task labels: 13 points at 16.
    static let rowTextScale: CGFloat = 0.8125
    /// Pele's axis dates: 12 points at 16.
    static let axisTextScale: CGFloat = 0.75

    public init(font: DiagramFont) {
        self.font = font
        nodeText = CoreTextDiagramTextMeasurer(font: font)
        edgeText = CoreTextDiagramTextMeasurer(font: font.resized(to: (font.size * Self.edgeTextScale).rounded()))
        boldNodeText = CoreTextDiagramTextMeasurer(font: font, isBold: true)
        smallText = CoreTextDiagramTextMeasurer(font: font.resized(to: (font.size * Self.smallTextScale).rounded()))
        rowText = CoreTextDiagramTextMeasurer(font: font.resized(to: (font.size * Self.rowTextScale).rounded()))
        axisText = CoreTextDiagramTextMeasurer(font: font.resized(to: (font.size * Self.axisTextScale).rounded()))
        planeMapText = PlaneMapTypography(font: font)
        let edgeFont = font.resized(to: (font.size * Self.edgeTextScale).rounded())
        boldEdgeText = CoreTextDiagramTextMeasurer(font: edgeFont, isBold: true)
        boldRowText = CoreTextDiagramTextMeasurer(font: font.resized(to: (font.size * Self.rowTextScale).rounded()), isBold: true)
        monospacedEdgeText = CoreTextDiagramTextMeasurer(font: edgeFont, isBold: false, isMonospaced: true)
        monospacedAxisText = CoreTextDiagramTextMeasurer(font: font.resized(to: (font.size * Self.axisTextScale).rounded()), isBold: false,
                                                         isMonospaced: true)
        italicEdgeText = CoreTextDiagramTextMeasurer(font: edgeFont, isBold: false, isItalic: true)
    }
}
