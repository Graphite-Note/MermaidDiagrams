/**
 * File: C4LayoutEngine.swift
 * --------------------------
 * Layer: Core
 * Description: Lays out a C4 diagram as Pele's render.ts draws it: the grid, the relations routed, the headings and
 *              labels placed, the title above; for a narrow column, tight, with the gap between columns that leaves the
 *              fewest routes without a lane of their own.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 24/11/2026
 */

import CoreGraphics

/// Lays out C4 diagrams.
public enum C4LayoutEngine {
    /// The diagram with room to spare: shapes 216 points wide in rows of `shapesPerRow`, 120 points apart.
    public static func layout(_ diagram: C4Diagram, typography: DiagramTypography) throws(C4LayoutError) -> C4Layout {
        try drawing(diagram, measurers: C4Measurers(typography: typography), font: typography.font, room: nil, gap: C4Metrics.narrowGap).layout
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
        // Every drawing is in the same room, so the grid's texts are measured once.
        var texts = C4GridTexts(diagram: diagram)
        var best = try drawing(diagram, measurers: measurers, font: font, room: room, gap: C4Metrics.narrowGap, texts: &texts)
        var gap = C4Metrics.narrowGap + C4Metrics.narrowGapWidening
        while best.squeezedCount > 0, gap <= C4Metrics.narrowGap + 3 * C4Metrics.narrowGapWidening {
            let wider = try drawing(diagram, measurers: measurers, font: font, room: room, gap: gap, texts: &texts)
            if wider.squeezedCount < best.squeezedCount { best = wider }
            gap += C4Metrics.narrowGapWidening
        }
        return best.layout
    }

    /// One drawing, and how many of its routes found no lane of their own.
    static func drawing<Measurer: DiagramTextMeasuring>(_ diagram: C4Diagram, measurers: C4Measurers<Measurer>, font: DiagramFont, room: CGFloat?,
                                                        gap: CGFloat) throws(C4LayoutError) -> (layout: C4Layout, squeezedCount: Int) {
        var texts = C4GridTexts(diagram: diagram)
        return try drawing(diagram, measurers: measurers, font: font, room: room, gap: gap, texts: &texts)
    }

    /// One drawing, its grid's texts measured into `texts` or taken from it.
    static func drawing<Measurer: DiagramTextMeasuring>(_ diagram: C4Diagram, measurers: C4Measurers<Measurer>, font: DiagramFont, room: CGFloat?,
                                                        gap: CGFloat, texts: inout C4GridTexts) throws(C4LayoutError) -> (layout: C4Layout, squeezedCount: Int) {
        var pass = C4DrawingPass(diagram: diagram, measurers: measurers, room: room, gap: gap, texts: &texts)
        try pass.routeRelations()
        pass.placeHeadings()
        let labels = pass.placeLabels()
        return (pass.assembled(labels: labels, font: font, titleRoom: room ?? C4Metrics.unwrappedWidth), pass.squeezedCount)
    }
}

extension C4DrawingPass {
    /// The layout: everything moved so that the drawing, its labels and its title sit `padding` inside the page, the
    /// title centered above and the drawing centered under a wider title.
    func assembled(labels: [C4PlacedLabel?], font: DiagramFont, titleRoom: CGFloat) -> C4Layout {
        let title = C4TextLabel.block(diagram.titleText, in: diagram, measurer: measurers.name, maximumWidth: titleRoom)
        let titleHeight = title.measuredHeight > 0 ? title.measuredHeight + C4Metrics.titleGap : 0
        let inner = max(extent.width, title.measuredWidth)
        let padding = C4Metrics.padding
        let size = CGSize(width: (inner + 2 * padding).rounded(.up), height: (extent.height + titleHeight + 2 * padding).rounded(.up))
        let offset = CGVector(dx: padding - extent.minX + (inner - extent.width) / 2, dy: padding + titleHeight - extent.minY)
        let placedTitle = title.map { block in PlaneMapLabel.placed(block, at: CGPoint(x: size.width / 2, y: padding + block.size.height / 2)) }
        return C4Layout(size: size, font: font, title: placedTitle, boundaries: laidOutBoundaries(offset: offset), shapes: laidOutShapes(offset: offset),
                        relations: laidOutRelations(labels: labels, offset: offset))
    }

    /// Each boundary but the top level, its heading's lines from its left end.
    private func laidOutBoundaries(offset: CGVector) -> [C4LayoutBoundary] {
        groups.indices.compactMap { groupIndex in
            guard let boxIndex = groupBoxIndices[groupIndex] else { return nil }
            let group = groups[groupIndex]
            let boundary = diagram.boundaryRecords[group.boundaryIndex]
            let frame = boxes[boxIndex].frame.offsetBy(dx: offset.dx, dy: offset.dy)
            let left = frame.minX + group.headingLeft
            var top = frame.minY + C4Metrics.headingTop
            var lines: [[DiagramTextBlock]] = []
            for text in group.texts {
                lines.append(text?.placedLines(left: left, top: top) ?? [])
                top += text.measuredHeight
            }
            let element = boundary.element
            return C4LayoutBoundary(alias: diagram.text(element.alias), frame: frame, isDeploymentNode: boundary.deploymentNode != nil, name: lines[0],
                                    type: lines[1], description: lines[2], look: diagram.look(of: element))
        }
    }

    /// Each shape, its texts centered on it one under the other, below a person's head or a database's cap and left of a
    /// queue's front end.
    private func laidOutShapes(offset: CGVector) -> [C4LayoutShape] {
        shapeOrder.enumerated().map { boxIndex, placedIndex in
            let placed = shapes[placedIndex]
            let shape = diagram.shapeRecords[placed.shapeIndex]
            let box = boxes[boxIndex]
            let frame = box.frame.offsetBy(dx: offset.dx, dy: offset.dy)
            let shiftX = box.form == .horizontalCylinder ? -C4Metrics.queueCapDepth(height: box.height) / 2 : 0
            let shiftY = box.form == .person ? C4Metrics.personHead / 2 : box.form == .cylinder ? C4Metrics.cylinderCapDepth(width: box.width) / 2 : 0
            var top = frame.midY + shiftY - placed.textHeight / 2
            var texts: [DiagramTextBlock?] = []
            for (index, text) in placed.texts.enumerated() {
                texts.append(text.map { block in PlaneMapLabel.placed(block, at: CGPoint(x: frame.midX + shiftX, y: top + block.size.height / 2)) })
                top += text.measuredHeight + (index == 2 ? C4Metrics.descriptionGap : 0)
            }
            let element = shape.element
            return C4LayoutShape(alias: diagram.text(element.alias), kind: shape.kind, form: box.form, frame: frame, type: texts[0], name: texts[1],
                                 technology: texts[2], description: texts[3], look: diagram.look(of: element))
        }
    }

    private func laidOutRelations(labels: [C4PlacedLabel?], offset: CGVector) -> [C4LayoutRelation] {
        zip(relations, labels).map { routed, placedLabel in
            let relation = diagram.relationRecords[routed.relationIndex]
            let route = routed.route
            let startMark = routed.pointsAtStart ? DiagramEdgeMark(arrowhead: .arrow, tip: route.start, direction: route.startDirection).translated(by: offset) : nil
            let endMark = routed.pointsAtEnd ? DiagramEdgeMark(arrowhead: .arrow, tip: route.end, direction: route.endDirection).translated(by: offset) : nil
            let corners = stride(from: 0, to: route.points.count, by: 2).map { index in
                CGPoint(x: route.points[index] + offset.dx, y: route.points[index + 1] + offset.dy)
            }
            return C4LayoutRelation(from: diagram.text(relation.from), to: diagram.text(relation.to), path: route.path.translated(by: offset), corners: corners, startMark: startMark,
                                    endMark: endMark,
                                    labelFrame: placedLabel?.frame.offsetBy(dx: offset.dx, dy: offset.dy), label: placedLabel?.label?.translated(by: offset),
                                    technology: placedLabel?.technology?.translated(by: offset), lineColor: routed.lineColor,
                                    textColor: routed.textColor, isCased: routed.isCased)
        }
    }
}
