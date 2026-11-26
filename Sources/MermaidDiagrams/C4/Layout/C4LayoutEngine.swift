/**
 * File: C4LayoutEngine.swift
 * --------------------------
 * Layer: Core
 * Description: Lays out a C4 diagram as Pele's render.ts draws it: the grid, the relations routed, the headings and
 *              labels placed, the title above; for a narrow column, tight, with the gap between columns that leaves the
 *              fewest routes without a lane of their own.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 26/11/2026
 */

import CoreGraphics

/// Lays out C4 diagrams.
public enum C4LayoutEngine {
    /// The diagram with room to spare: shapes 216 points wide in rows of `shapesPerRow`, 120 points apart.
    public static func layout(_ diagram: C4Diagram, typography: DiagramTypography) throws(C4LayoutError) -> C4Layout {
        var texts = C4GridTexts(diagram: diagram)
        let measuring = C4TextMeasuring(C4Measurers(typography: typography))
        let pass = try drawing(diagram, measuring: measuring, room: nil, gap: C4Metrics.narrowGap, texts: &texts)
        return pass.assembled(font: typography.font, titleRoom: C4Metrics.unwrappedWidth, texts: &texts)
    }

    /// The diagram for a container `availableWidth` wide, as Pele's `tighten` draws it: with room to spare, and tight
    /// instead when that does not fit and tight is narrower.
    public static func layout(_ diagram: C4Diagram, typography: DiagramTypography, fittingWidth availableWidth: CGFloat?) throws(C4LayoutError) -> C4Layout {
        try DiagramWidthFitting.tighten(availableWidth: availableWidth, width: { layout in layout.size.width }) { isTight throws(C4LayoutError) in
            isTight ? try tightLayout(diagram, typography: typography, columnWidth: availableWidth) : try layout(diagram, typography: typography)
        }
    }

    /// The diagram tight for a column `columnWidth` wide (320 when nil): its shapes, rows and headings fitted to the
    /// column less the padding, labels on their lines without the diagram's offsets. Drawn with the gap between columns
    /// at 36 points, then 60, 84 and 108 while routes are left without a lane of their own, keeping the drawing that
    /// leaves the fewest.
    static func tightLayout(_ diagram: C4Diagram, typography: DiagramTypography, columnWidth: CGFloat?) throws(C4LayoutError) -> C4Layout {
        try tightLayout(diagram, measurers: C4Measurers(typography: typography), font: typography.font, columnWidth: columnWidth)
    }

    /// The tight drawing with the text measured by `measurers`.
    static func tightLayout<Measurer: DiagramTextMeasuring>(_ diagram: C4Diagram, measurers: C4Measurers<Measurer>, font: DiagramFont,
                                                            columnWidth: CGFloat?) throws(C4LayoutError) -> C4Layout {
        let available = DiagramWidthFitting.limit(columnWidth) ?? C4Metrics.defaultColumnWidth
        let room = max(C4Metrics.leastRoom, available - 2 * C4Metrics.padding)
        let measuring = C4TextMeasuring(measurers)
        // Every drawing is in the same room, so the grid's texts are measured once.
        var texts = C4GridTexts(diagram: diagram)
        var best = try drawing(diagram, measuring: measuring, room: room, gap: C4Metrics.narrowGap, texts: &texts)
        var gap = C4Metrics.narrowGap + C4Metrics.narrowGapWidening
        while best.squeezedCount > 0, gap <= C4Metrics.narrowGap + 3 * C4Metrics.narrowGapWidening {
            let wider = try drawing(diagram, measuring: measuring, room: room, gap: gap, texts: &texts)
            if wider.squeezedCount < best.squeezedCount { best = wider }
            gap += C4Metrics.narrowGapWidening
        }
        return best.assembled(font: font, titleRoom: room, texts: &texts)
    }

    /// One drawing, its grid's texts measured into `texts` or taken from it, its labels placed: what `assembled` puts
    /// on the page.
    static func drawing<Measurer: DiagramTextMeasuring>(_ diagram: C4Diagram, measuring: C4TextMeasuring<Measurer>, room: CGFloat?, gap: CGFloat,
                                                        texts: inout C4GridTexts) throws(C4LayoutError) -> C4DrawingPass<Measurer> {
        var pass = C4DrawingPass(diagram: diagram, measuring: measuring, room: room, gap: gap, texts: &texts)
        try pass.routeRelations()
        pass.placeHeadings()
        pass.labels = pass.placeLabels(into: &texts.lines)
        return pass
    }

    /// One drawing on its page with the text measured by `measurers`, and how many of its routes found no lane of their
    /// own.
    static func drawing<Measurer: DiagramTextMeasuring>(_ diagram: C4Diagram, measurers: C4Measurers<Measurer>, font: DiagramFont, room: CGFloat?,
                                                        gap: CGFloat) throws(C4LayoutError) -> (layout: C4Layout, squeezedCount: Int) {
        var texts = C4GridTexts(diagram: diagram)
        let pass = try drawing(diagram, measuring: C4TextMeasuring(measurers), room: room, gap: gap, texts: &texts)
        return (pass.assembled(font: font, titleRoom: room ?? C4Metrics.unwrappedWidth, texts: &texts), pass.squeezedCount)
    }
}
