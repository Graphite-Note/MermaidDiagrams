/**
 * File: EntityRelationshipDrawingParts.swift
 * ------------------------------------------
 * Layer: Core
 * Description: A laid-out entity relationship diagram's geometry grouped by how it is painted, as Core Graphics paths
 *              or in any kind a drawing records.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.3
 * Date: 24/11/2026
 */

import CoreGraphics

/// A laid-out entity relationship diagram's geometry grouped by how it is painted, so that drawing it in any colors is
/// a handful of fills and strokes, by Core Graphics (`EntityRelationshipRenderer`) or by a view's own shapes. Back to
/// front, as Pele draws: the lines and their marks, the labels on their patches, the boxes with their striped rows,
/// outlines and header dividers, the boxes' text, the title.
public struct EntityRelationshipDrawingParts {
    /// Identifying relationships, stroked one point wide with round caps.
    public let identifyingLines: CGPath
    /// Non-identifying relationships, stroked one point wide in dashes of 4 and gaps of 3.
    public let nonIdentifyingLines: CGPath
    /// The rings and diamonds of the cardinality marks, filled in the background color so that the line does not show
    /// through them.
    public let markFills: CGPath
    /// Every mark's bars, feet, rings and diamonds, stroked one point wide in the line color, solid on any line.
    public let markOutlines: CGPath
    /// The patches behind the labels, filled in the background color.
    public let labelPatches: CGPath
    public let labels: [DiagramTextBlock]
    /// The boxes, filled in the surface color.
    public let boxFills: CGPath
    /// The first attribute row of each box and every second one after it, filled in the background color.
    public let rowStripes: CGPath
    /// The boxes' outlines and the lines under their headers, stroked one point wide in the border color.
    public let boxOutlines: CGPath
    /// The entities' names and their attributes' names, in the text color.
    public let entityTexts: [DiagramTextBlock]
    /// The attributes' types, keys and comments, in the muted text color.
    public let attributeDetails: [DiagramTextBlock]
    /// The title, drawn bold, or nil.
    public let title: DiagramTextBlock?

    public static let lineWidth: CGFloat = 1
    public static let nonIdentifyingDashLengths: [CGFloat] = [4, 3]
    /// The opacity of the text color that types, keys and comments are drawn at: Pele's muted gray (#6e6e6e) is its
    /// text (#1f1f1f) at this opacity over its white page.
    public static let mutedTextOpacity: CGFloat = 0.647

    /// The corner radius of a box: Pele's `--pele-radius`.
    static let boxCornerRadius: CGFloat = 4
    /// The corner radius of the patch behind a label.
    static let labelPatchCornerRadius: CGFloat = 3
    /// How much wider than its text the patch behind a label is.
    static let labelPatchExtraWidth: CGFloat = 8

    /// The groups' boxes and their titles, painted behind everything; empty parts for a diagram without groups.
    public let subgraphs: FlowchartClusterDrawingParts

    public init(layout: EntityRelationshipLayout) {
        subgraphs = FlowchartClusterDrawingParts(clusters: layout.subgraphs)
        let paths = EntityRelationshipPaths(layout: layout, making: DiagramCoreGraphicsPaths())
        identifyingLines = paths.identifyingLines.path
        nonIdentifyingLines = paths.nonIdentifyingLines.path
        markFills = paths.markFills.path
        markOutlines = paths.markOutlines.path
        labelPatches = paths.labelPatches.path
        labels = layout.relationships.compactMap(\.label)
        boxFills = paths.boxFills.path
        rowStripes = paths.rowStripes.path
        boxOutlines = paths.boxOutlines.path
        entityTexts = layout.entities.flatMap { entity in [entity.name] + entity.rows.flatMap { row in Self.texts(of: row, inMutedColor: false) } }
        attributeDetails = layout.entities.flatMap { entity in entity.rows.flatMap { row in Self.texts(of: row, inMutedColor: true) } }
        title = layout.title
    }

    /// The row's attribute name (`inMutedColor` false), or its type, keys and comment.
    private static func texts(of row: EntityRelationshipLayoutRow, inMutedColor: Bool) -> [DiagramTextBlock] {
        row.texts.filter { cell in isInMutedColor(cell.column) == inMutedColor }.map(\.text)
    }

    /// Whether a column's text is drawn in the muted color: a type, keys and a comment are; a name is not.
    static func isInMutedColor(_ column: EntityRelationshipColumn) -> Bool {
        switch column {
        case .name: false
        case .type, .keys, .comment: true
        }
    }
}

/// The paths of `EntityRelationshipDrawingParts` in any kind a drawing records: Core Graphics paths or lanes of the
/// scene's workspace. A shape made whole (a box, a relationship's line, a rounded stripe) is made for a moment, added where
/// it is painted and given back.
struct EntityRelationshipPaths<Path: DiagramPathRecording> {
    let identifyingLines: Path
    let nonIdentifyingLines: Path
    let markFills: Path
    let markOutlines: Path
    let labelPatches: Path
    let boxFills: Path
    let rowStripes: Path
    let boxOutlines: Path

    init<Maker: DiagramPathMaking>(layout: EntityRelationshipLayout, making maker: Maker) where Maker.Path == Path {
        identifyingLines = maker.makePath()
        nonIdentifyingLines = maker.makePath()
        markFills = maker.makePath()
        markOutlines = maker.makePath()
        labelPatches = maker.makePath()
        for relationship in layout.relationships {
            let madeCount = maker.madePathCount
            let line = maker.makePath()
            DiagramEdgeDrawing.record(relationship.path, into: line)
            switch relationship.identification {
            case .identifying: identifyingLines.addPath(line)
            case .nonIdentifying: nonIdentifyingLines.addPath(line)
            }
            EntityRelationshipCardinalityDrawing.addMark(relationship.firstEntityMark, fills: markFills, outlines: markOutlines)
            EntityRelationshipCardinalityDrawing.addMark(relationship.secondEntityMark, fills: markFills, outlines: markOutlines)
            if let label = relationship.label {
                let radius = EntityRelationshipDrawingParts.labelPatchCornerRadius
                labelPatches.addPath(maker.roundedRectangle(label.frame.insetBy(dx: -EntityRelationshipDrawingParts.labelPatchExtraWidth / 2, dy: 0),
                                                            cornerWidth: radius, cornerHeight: radius))
            }
            maker.givePathsBack(downTo: madeCount)
        }
        boxFills = maker.makePath()
        rowStripes = maker.makePath()
        boxOutlines = maker.makePath()
        Self.addBoxes(of: layout.entities, fills: boxFills, stripes: rowStripes, outlines: boxOutlines, making: maker)
    }

    /// The boxes to fill, the rows striped over them, and their outlines and header dividers.
    private static func addBoxes<Maker: DiagramPathMaking>(of entities: [EntityRelationshipLayoutEntity], fills: Path, stripes: Path, outlines: Path,
                                                           making maker: Maker) where Maker.Path == Path {
        let radius = EntityRelationshipDrawingParts.boxCornerRadius
        for entity in entities {
            let madeCount = maker.madePathCount
            defer { maker.givePathsBack(downTo: madeCount) }
            fills.addPath(maker.roundedRectangle(entity.frame, cornerWidth: radius, cornerHeight: radius), alsoTo: outlines)
            if let firstRow = entity.rows.first {
                outlines.move(to: CGPoint(x: entity.frame.minX, y: firstRow.frame.minY))
                outlines.addLine(to: CGPoint(x: entity.frame.maxX, y: firstRow.frame.minY))
            }
            for (index, row) in entity.rows.enumerated() where index.isMultiple(of: 2) {
                let frame = row.frame
                guard index == entity.rows.count - 1 else {
                    stripes.addRect(frame)
                    continue
                }
                // The last band follows the box's rounded bottom corners: a rounded rectangle, squared off on top.
                let stripeRadius = min(radius, frame.height / 2)
                stripes.addPath(maker.roundedRectangle(frame, cornerWidth: stripeRadius, cornerHeight: stripeRadius))
                stripes.addRect(CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height / 2))
            }
        }
    }
}
