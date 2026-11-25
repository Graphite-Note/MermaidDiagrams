/**
 * File: ReferenceEntityRelationshipDrawingParts.swift
 * ---------------------------------------------------
 * Layer: Tests
 * Description: 0.7.0's entity relationship drawing parts and cardinality marks, frozen as main 2a0cc65 made them
 *              in Core Graphics paths, which the drawing parts and scenes made by the generic path code are compared with.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// A laid-out entity relationship diagram's geometry grouped by how it is painted, so that drawing it in any colors is
/// a handful of fills and strokes, by Core Graphics (`EntityRelationshipRenderer`) or by a view's own shapes. Back to
/// front, as Pele draws: the lines and their marks, the labels on their patches, the boxes with their striped rows,
/// outlines and header dividers, the boxes' text, the title.
struct ReferenceEntityRelationshipDrawingParts {
    /// Identifying relationships, stroked one point wide with round caps.
    let identifyingLines: CGPath
    /// Non-identifying relationships, stroked one point wide in dashes of 4 and gaps of 3.
    let nonIdentifyingLines: CGPath
    /// The rings and diamonds of the cardinality marks, filled in the background color so that the line does not show
    /// through them.
    let markFills: CGPath
    /// Every mark's bars, feet, rings and diamonds, stroked one point wide in the line color, solid on any line.
    let markOutlines: CGPath
    /// The patches behind the labels, filled in the background color.
    let labelPatches: CGPath
    let labels: [DiagramTextBlock]
    /// The boxes, filled in the surface color.
    let boxFills: CGPath
    /// The first attribute row of each box and every second one after it, filled in the background color.
    let rowStripes: CGPath
    /// The boxes' outlines and the lines under their headers, stroked one point wide in the border color.
    let boxOutlines: CGPath
    /// The entities' names and their attributes' names, in the text color.
    let entityTexts: [DiagramTextBlock]
    /// The attributes' types, keys and comments, in the muted text color.
    let attributeDetails: [DiagramTextBlock]
    /// The title, drawn bold, or nil.
    let title: DiagramTextBlock?

    static let lineWidth: CGFloat = 1
    static let nonIdentifyingDashLengths: [CGFloat] = [4, 3]
    /// The opacity of the text color that types, keys and comments are drawn at: Pele's muted gray (#6e6e6e) is its
    /// text (#1f1f1f) at this opacity over its white page.
    static let mutedTextOpacity: CGFloat = 0.647

    /// The corner radius of a box: Pele's `--pele-radius`.
    static let boxCornerRadius: CGFloat = 4
    /// The corner radius of the patch behind a label.
    static let labelPatchCornerRadius: CGFloat = 3
    /// How much wider than its text the patch behind a label is.
    static let labelPatchExtraWidth: CGFloat = 8

    /// The groups' boxes and their titles, painted behind everything; empty parts for a diagram without groups.
    let subgraphs: FlowchartClusterDrawingParts

    init(layout: EntityRelationshipLayout) {
        subgraphs = FlowchartClusterDrawingParts(clusters: layout.subgraphs)
        let identifyingLines = CGMutablePath()
        let nonIdentifyingLines = CGMutablePath()
        let markFills = CGMutablePath()
        let markOutlines = CGMutablePath()
        let labelPatches = CGMutablePath()
        for relationship in layout.relationships {
            let line = DiagramEdgeDrawing.path(relationship.path)
            switch relationship.identification {
            case .identifying: identifyingLines.addPath(line)
            case .nonIdentifying: nonIdentifyingLines.addPath(line)
            }
            for mark in [relationship.firstEntityMark, relationship.secondEntityMark] {
                ReferenceEntityRelationshipCardinalityDrawing.addMark(mark, fills: markFills, outlines: markOutlines)
            }
            if let label = relationship.label {
                labelPatches.addPath(CGPath(roundedRect: label.frame.insetBy(dx: -Self.labelPatchExtraWidth / 2, dy: 0),
                                            cornerWidth: Self.labelPatchCornerRadius, cornerHeight: Self.labelPatchCornerRadius, transform: nil))
            }
        }
        self.identifyingLines = identifyingLines
        self.nonIdentifyingLines = nonIdentifyingLines
        self.markFills = markFills
        self.markOutlines = markOutlines
        self.labelPatches = labelPatches
        labels = layout.relationships.compactMap(\.label)
        let boxes = BoxPaths(entities: layout.entities)
        boxFills = boxes.fills
        rowStripes = boxes.stripes
        boxOutlines = boxes.outlines
        entityTexts = layout.entities.flatMap { entity in [entity.name] + entity.rows.flatMap { row in Self.texts(of: row, inMutedColor: false) } }
        attributeDetails = layout.entities.flatMap { entity in entity.rows.flatMap { row in Self.texts(of: row, inMutedColor: true) } }
        title = layout.title
    }

    /// The row's attribute name (`inMutedColor` false), or its type, keys and comment.
    private static func texts(of row: EntityRelationshipLayoutRow, inMutedColor: Bool) -> [DiagramTextBlock] {
        row.texts.filter { cell in
            switch cell.column {
            case .name: !inMutedColor
            case .type, .keys, .comment: inMutedColor
            }
        }.map(\.text)
    }

    /// The boxes to fill, the rows striped over them, and their outlines and header dividers.
    private struct BoxPaths {
        let fills = CGMutablePath()
        let stripes = CGMutablePath()
        let outlines = CGMutablePath()

        init(entities: [EntityRelationshipLayoutEntity]) {
            let radius = ReferenceEntityRelationshipDrawingParts.boxCornerRadius
            for entity in entities {
                let box = CGPath(roundedRect: entity.frame, cornerWidth: radius, cornerHeight: radius, transform: nil)
                fills.addPath(box)
                outlines.addPath(box)
                if let firstRow = entity.rows.first {
                    outlines.move(to: CGPoint(x: entity.frame.minX, y: firstRow.frame.minY))
                    outlines.addLine(to: CGPoint(x: entity.frame.maxX, y: firstRow.frame.minY))
                }
                for (index, row) in entity.rows.enumerated() where index.isMultiple(of: 2) {
                    addStripe(row.frame, isLast: index == entity.rows.count - 1)
                }
            }
        }

        /// A row's band; the last one follows the box's rounded bottom corners: a rounded rectangle, squared off on top.
        private func addStripe(_ frame: CGRect, isLast: Bool) {
            guard isLast else { return stripes.addRect(frame) }
            let radius = min(ReferenceEntityRelationshipDrawingParts.boxCornerRadius, frame.height / 2)
            stripes.addPath(CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil))
            stripes.addRect(CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height / 2))
        }
    }
}

/// The crow's foot marks of the cardinalities, Pele's, drawn over the end of a line where it meets a box: one bar
/// across the line for "one", a ring for "zero", a foot whose toes spread on the box for "many". Exactly one is two
/// bars, zero or one a bar and a ring, one or more a foot and a bar, zero or more a foot and a ring, and the parent
/// end a hollow diamond. Rings and the diamond are filled with the background, so that the line does not show
/// through them.
enum ReferenceEntityRelationshipCardinalityDrawing {
    /// Half a bar's length across the line.
    static let barHalfLength: CGFloat = 5
    /// Half the spread of a foot's toes on the box.
    static let footHalfWidth: CGFloat = 6
    /// How far back from the box a foot's toes meet.
    static let footLength: CGFloat = 10
    static let ringRadius: CGFloat = 3.5
    /// The diamond's length along the line and half its width.
    static let diamondLength: CGFloat = 12
    static let diamondHalfWidth: CGFloat = 4
    /// How far back from the box each bar or ring's center is: the bars of exactly one, the bar and ring of zero or
    /// one, and the bar or ring behind a foot.
    static let nearBarSetback: CGFloat = 6
    static let farBarSetback: CGFloat = 10
    static let ringBehindBarSetback: CGFloat = 13.5
    static let barBehindFootSetback: CGFloat = 13.5
    static let ringBehindFootSetback: CGFloat = 14

    /// Adds a mark to the paths filled with the background (rings, the diamond) and stroked in the line color.
    static func addMark(_ mark: EntityRelationshipCardinalityMark, fills: CGMutablePath, outlines: CGMutablePath) {
        // `back` runs from the box along the line, `side` across it.
        func point(back: CGFloat, side: CGFloat) -> CGPoint {
            CGPoint(x: mark.tip.x - mark.direction.dx * back - mark.direction.dy * side, y: mark.tip.y - mark.direction.dy * back + mark.direction.dx * side)
        }
        func addBar(back: CGFloat) {
            outlines.move(to: point(back: back, side: -barHalfLength))
            outlines.addLine(to: point(back: back, side: barHalfLength))
        }
        func addFoot() {
            outlines.addLines(between: [point(back: 0, side: -footHalfWidth), point(back: footLength, side: 0), point(back: 0, side: footHalfWidth)])
        }
        func addRing(back: CGFloat) {
            let center = point(back: back, side: 0)
            let ring = CGRect(x: center.x - ringRadius, y: center.y - ringRadius, width: 2 * ringRadius, height: 2 * ringRadius)
            fills.addEllipse(in: ring)
            outlines.addEllipse(in: ring)
        }
        switch mark.cardinality {
        case .exactlyOne:
            addBar(back: nearBarSetback)
            addBar(back: farBarSetback)
        case .zeroOrOne:
            addBar(back: nearBarSetback)
            addRing(back: ringBehindBarSetback)
        case .oneOrMore:
            addFoot()
            addBar(back: barBehindFootSetback)
        case .zeroOrMore:
            addFoot()
            addRing(back: ringBehindFootSetback)
        case .parent:
            let diamond = [point(back: 0, side: 0), point(back: diamondLength / 2, side: diamondHalfWidth), point(back: diamondLength, side: 0),
                           point(back: diamondLength / 2, side: -diamondHalfWidth)]
            fills.addLines(between: diamond)
            fills.closeSubpath()
            outlines.addLines(between: diamond)
            outlines.closeSubpath()
        }
    }
}
