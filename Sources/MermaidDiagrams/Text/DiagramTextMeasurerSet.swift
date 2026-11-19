/**
 * File: DiagramTextMeasurerSet.swift
 * ----------------------------------
 * Layer: Core
 * Description: The three measurers a diagram drawn as rows of text measures in: its regular text, its bold text and its
 *              smaller text, from a typography or, in tests, of fixed widths.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// The regular text of a diagram, its bold (titles, folders, headings) and its smaller text (Pele's seven eighths of
/// the size, rounded: a kanban card's, an Ishikawa diagram's causes), measured alike.
struct DiagramTextMeasurerSet<Measurer: DiagramTextMeasuring> {
    let regular: Measurer
    let bold: Measurer
    let small: Measurer
}

extension DiagramTextMeasurerSet where Measurer == CoreTextDiagramTextMeasurer {
    init(typography: DiagramTypography) {
        self.init(regular: typography.nodeText, bold: typography.boldNodeText, small: typography.edgeText)
    }
}
