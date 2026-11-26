/**
 * File: ReferenceC4Metrics.swift
 * ------------------------------
 * Layer: Tests
 * Description: The 0.7.0 (de81532) C4 layout kept as the reference the flat C4 layout is checked against. The numbers
 *              of Pele's C4 layout, routing and drawing (layout.ts, route.ts, render.ts), each in one place.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// Pele's C4 numbers, in points.
enum ReferenceC4Metrics {
    // MARK: Shapes (layout.ts)

    static let shapeWidth: CGFloat = 216
    static let shapeLeastHeight: CGFloat = 64
    static let shapePaddingX: CGFloat = 14
    static let shapePaddingY: CGFloat = 12
    /// The room a queue's rounded ends take out of its text's width, and the height a database's caps add.
    static let queueEndsWidth: CGFloat = 36
    static let cylinderCapsHeight: CGFloat = 24
    /// The space between a shape's technology and its description.
    static let descriptionGap: CGFloat = 4

    // MARK: Rows and boundaries (layout.ts)

    /// Room between two columns for the label of a line across them, clear of an arrowhead on either side, with an
    /// arrowhead's length to spare for a word a little wider than the label room.
    static let columnGap = narrowLabelWidth + labelPadding + 3 * arrowLength
    static let rowGap: CGFloat = 88
    /// Room for a relation to run along the inside of a boundary.
    static let boundaryPadding = lane + 8
    /// A boundary's padding in a narrow column.
    static let tightBoundaryPadding: CGFloat = 12
    static let boundaryGap: CGFloat = 48
    /// Where a boundary's heading starts, from its top left corner.
    static let headingLeft: CGFloat = 16
    static let headingTop: CGFloat = 10
    /// The space under a heading's last line, before the lane along the boundary's inside.
    static let headingGap: CGFloat = 6
    /// The width a heading wraps at when the layout has no column to fit.
    static let unwrappedWidth: CGFloat = 4_000

    // MARK: Routing (route.ts)

    static let loopReach: CGFloat = 28
    static let lane: CGFloat = 20
    static let laneStep: CGFloat = 7
    static let cornerRadius: CGFloat = 8
    /// A wide label on an upright lane leans this far out from it, to the middle of the gap between columns.
    static let labelLean: CGFloat = 30
    /// Label widths that fit the gap between two columns, and where there is room to spare.
    static let narrowLabelWidth: CGFloat = 88
    static let wideLabelWidth: CGFloat = 160
    static let loopLabelWidth: CGFloat = 64
    /// The space a label's background adds to the width of its text.
    static let labelPadding: CGFloat = 8
    /// The shared person shape: a head of radius 13 centered 14 below the top, over a body that starts 26 below it.
    static let personHead: CGFloat = 26
    /// Parallel stretches closer than this read as one line, and a line this close to a boundary's frame reads as part
    /// of it; ports on a side are this far apart.
    static let nearDistance: CGFloat = 6
    static let frameNearDistance: CGFloat = 3
    static let portStep: CGFloat = 12
    static let arrowLength = DiagramEdgeMark.arrowLength

    static func cylinderCapDepth(width: CGFloat) -> CGFloat { min(12, max(6, width / 14)) }
    static func queueCapDepth(height: CGFloat) -> CGFloat { min(12, height / 4) }

    // MARK: Drawing (render.ts)

    /// How far apart two relations that run opposite ways between the same two elements are drawn.
    static let pairShift: CGFloat = 7
    /// The gap between columns in a narrow column, and how much each later try widens it.
    static let narrowGap: CGFloat = 36
    static let narrowGapWidening: CGFloat = 24
    static let largestLabelOffset: CGFloat = 2_000
    /// A label may cover this much of a shape's edge, where there is no text.
    static let shapeEdgeAllowance: CGFloat = 8
    /// Places along a relation to try for its label, nearest the middle first.
    static let labelSlidePlaces: [CGFloat] = [0.5, 0.4, 0.6, 0.3, 0.7, 0.2, 0.8]
    /// Above this many box comparisons, labels stay at the middle and lines are not steered around shapes.
    static let carefulPlacementBudget = 2_000_000
    /// The space around the drawing, and below the title.
    static let padding = DiagramWidthFitting.defaultPadding
    static let titleGap: CGFloat = 12
    /// The column a narrow layout fits when none is given.
    static let defaultColumnWidth: CGFloat = 320
    static let leastRoom: CGFloat = 80
}
