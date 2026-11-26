/**
 * File: ReferenceC4LayoutEngine.swift
 * -----------------------------------
 * Layer: Tests
 * Description: The 0.7.0 (de81532) C4 layout kept as the reference the flat C4 layout is checked against. Lays out a C4
 *              diagram as Pele's render.ts draws it: the grid, the relations routed, the headings and labels placed,
 *              the title above; for a narrow column, tight, with the gap between columns that leaves the fewest routes
 *              without a lane of their own.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// Lays out C4 diagrams.
enum ReferenceC4LayoutEngine {
    /// The diagram with room to spare: shapes 216 points wide in rows of `shapesPerRow`, 120 points apart.
    static func layout(_ diagram: ReferenceC4Diagram, typography: DiagramTypography) throws(C4LayoutError) -> ReferenceC4Layout {
        try drawing(diagram, measurers: ReferenceC4Measurers(typography: typography), font: typography.font, room: nil, gap: ReferenceC4Metrics.narrowGap).layout
    }

    /// The diagram for a container `availableWidth` wide, as Pele's `tighten` draws it: with room to spare, and tight
    /// instead when that does not fit and tight is narrower.
    static func layout(_ diagram: ReferenceC4Diagram, typography: DiagramTypography, fittingWidth availableWidth: CGFloat?) throws(C4LayoutError) -> ReferenceC4Layout {
        try DiagramWidthFitting.tighten(availableWidth: availableWidth, width: { layout in layout.size.width }) { isTight throws(C4LayoutError) in
            isTight ? try tightLayout(diagram, typography: typography, columnWidth: availableWidth) : try layout(diagram, typography: typography)
        }
    }

    /// The diagram tight for a column `columnWidth` wide (320 when nil): its shapes, rows and headings fitted to the
    /// column less the padding, labels on their lines without the diagram's offsets. Drawn with the gap between columns
    /// at 36 points, then 60, 84 and 108 while routes are left without a lane of their own, keeping the drawing that
    /// leaves the fewest.
    static func tightLayout(_ diagram: ReferenceC4Diagram, typography: DiagramTypography, columnWidth: CGFloat?) throws(C4LayoutError) -> ReferenceC4Layout {
        try tightLayout(diagram, measurers: ReferenceC4Measurers(typography: typography), font: typography.font, columnWidth: columnWidth)
    }

    /// The tight drawing with the text measured by `measurers`.
    static func tightLayout<Measurer: DiagramTextMeasuring>(_ diagram: ReferenceC4Diagram, measurers: ReferenceC4Measurers<Measurer>, font: DiagramFont,
                                                            columnWidth: CGFloat?) throws(C4LayoutError) -> ReferenceC4Layout {
        let available = DiagramWidthFitting.limit(columnWidth) ?? ReferenceC4Metrics.defaultColumnWidth
        let room = max(ReferenceC4Metrics.leastRoom, available - 2 * ReferenceC4Metrics.padding)
        var best = try drawing(diagram, measurers: measurers, font: font, room: room, gap: ReferenceC4Metrics.narrowGap)
        var gap = ReferenceC4Metrics.narrowGap + ReferenceC4Metrics.narrowGapWidening
        while best.squeezedCount > 0, gap <= ReferenceC4Metrics.narrowGap + 3 * ReferenceC4Metrics.narrowGapWidening {
            let wider = try drawing(diagram, measurers: measurers, font: font, room: room, gap: gap)
            if wider.squeezedCount < best.squeezedCount { best = wider }
            gap += ReferenceC4Metrics.narrowGapWidening
        }
        return best.layout
    }

    /// One drawing, and how many of its routes found no lane of their own.
    static func drawing<Measurer: DiagramTextMeasuring>(_ diagram: ReferenceC4Diagram, measurers: ReferenceC4Measurers<Measurer>, font: DiagramFont, room: CGFloat?,
                                                        gap: CGFloat) throws(C4LayoutError) -> (layout: ReferenceC4Layout, squeezedCount: Int) {
        var pass = ReferenceC4DrawingPass(diagram: diagram, measurers: measurers, room: room, gap: gap)
        try pass.routeRelations()
        pass.placeHeadings()
        let labels = pass.placeLabels()
        return (pass.assembled(labels: labels, font: font, titleRoom: room ?? ReferenceC4Metrics.unwrappedWidth), pass.squeezedCount)
    }
}

extension ReferenceC4DrawingPass {
    /// The layout: everything moved so that the drawing, its labels and its title sit `padding` inside the page, the
    /// title centered above and the drawing centered under a wider title.
    func assembled(labels: [ReferenceC4PlacedLabel?], font: DiagramFont, titleRoom: CGFloat) -> ReferenceC4Layout {
        let title = ReferenceC4TextLabel.block(diagram.title, measurer: measurers.name, maximumWidth: titleRoom)
        let titleHeight = title.measuredHeight > 0 ? title.measuredHeight + ReferenceC4Metrics.titleGap : 0
        let inner = max(extent.width, title.measuredWidth)
        let padding = ReferenceC4Metrics.padding
        let size = CGSize(width: (inner + 2 * padding).rounded(.up), height: (extent.height + titleHeight + 2 * padding).rounded(.up))
        let offset = CGVector(dx: padding - extent.minX + (inner - extent.width) / 2, dy: padding + titleHeight - extent.minY)
        let placedTitle = title.map { block in PlaneMapLabel.placed(block, at: CGPoint(x: size.width / 2, y: padding + block.size.height / 2)) }
        return ReferenceC4Layout(size: size, font: font, title: placedTitle, boundaries: laidOutBoundaries(offset: offset), shapes: laidOutShapes(offset: offset),
                        relations: laidOutRelations(labels: labels, offset: offset))
    }

    /// Each boundary but the top level, its heading's lines from its left end.
    private func laidOutBoundaries(offset: CGVector) -> [C4LayoutBoundary] {
        groups.indices.compactMap { groupIndex in
            guard let boxIndex = groupBoxIndices[groupIndex] else { return nil }
            let group = groups[groupIndex]
            let boundary = diagram.boundaries[group.boundaryIndex]
            let frame = boxes[boxIndex].frame.offsetBy(dx: offset.dx, dy: offset.dy)
            let left = frame.minX + group.headingLeft
            var top = frame.minY + ReferenceC4Metrics.headingTop
            var lines: [[DiagramTextBlock]] = []
            for text in group.texts {
                lines.append(text?.placedLines(left: left, top: top) ?? [])
                top += text.measuredHeight
            }
            let element = boundary.element
            return C4LayoutBoundary(alias: element.alias, frame: frame, isDeploymentNode: boundary.deploymentNode != nil, name: lines[0], type: lines[1],
                                    description: lines[2],
                                    look: C4ElementLook(backgroundColor: element.backgroundColor, borderColor: element.borderColor, fontColor: element.fontColor))
        }
    }

    /// Each shape, its texts centered on it one under the other, below a person's head or a database's cap and left of a
    /// queue's front end.
    private func laidOutShapes(offset: CGVector) -> [C4LayoutShape] {
        shapeOrder.enumerated().map { boxIndex, placedIndex in
            let placed = shapes[placedIndex]
            let shape = diagram.shapes[placed.shapeIndex]
            let box = boxes[boxIndex]
            let frame = box.frame.offsetBy(dx: offset.dx, dy: offset.dy)
            let shiftX = box.form == .horizontalCylinder ? -ReferenceC4Metrics.queueCapDepth(height: box.height) / 2 : 0
            let shiftY = box.form == .person ? ReferenceC4Metrics.personHead / 2 : box.form == .cylinder ? ReferenceC4Metrics.cylinderCapDepth(width: box.width) / 2 : 0
            var top = frame.midY + shiftY - placed.textHeight / 2
            var texts: [DiagramTextBlock?] = []
            for (index, text) in placed.texts.enumerated() {
                texts.append(text.map { block in PlaneMapLabel.placed(block, at: CGPoint(x: frame.midX + shiftX, y: top + block.size.height / 2)) })
                top += text.measuredHeight + (index == 2 ? ReferenceC4Metrics.descriptionGap : 0)
            }
            let element = shape.element
            return C4LayoutShape(alias: element.alias, kind: shape.kind, form: box.form, frame: frame, type: texts[0], name: texts[1], technology: texts[2],
                                 description: texts[3],
                                 look: C4ElementLook(backgroundColor: element.backgroundColor, borderColor: element.borderColor, fontColor: element.fontColor))
        }
    }

    private func laidOutRelations(labels: [ReferenceC4PlacedLabel?], offset: CGVector) -> [C4LayoutRelation] {
        zip(relations, labels).map { routed, placedLabel in
            let relation = diagram.relations[routed.relationIndex]
            let route = routed.route
            let startMark = routed.pointsAtStart ? DiagramEdgeMark(arrowhead: .arrow, tip: route.start, direction: route.startDirection).translated(by: offset) : nil
            let endMark = routed.pointsAtEnd ? DiagramEdgeMark(arrowhead: .arrow, tip: route.end, direction: route.endDirection).translated(by: offset) : nil
            let corners = stride(from: 0, to: route.points.count, by: 2).map { index in
                CGPoint(x: route.points[index] + offset.dx, y: route.points[index + 1] + offset.dy)
            }
            return C4LayoutRelation(from: relation.from, to: relation.to, path: route.path.translated(by: offset), corners: corners, startMark: startMark,
                                    endMark: endMark,
                                    labelFrame: placedLabel?.frame.offsetBy(dx: offset.dx, dy: offset.dy), label: placedLabel?.label?.translated(by: offset),
                                    technology: placedLabel?.technology?.translated(by: offset), lineColor: routed.lineColor,
                                    textColor: C4ElementLook.color(relation.textColor, property: "color"), isCased: routed.isCased)
        }
    }
}
