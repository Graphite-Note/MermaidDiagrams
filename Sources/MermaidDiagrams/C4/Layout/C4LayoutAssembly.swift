/**
 * File: C4LayoutAssembly.swift
 * ----------------------------
 * Layer: Core
 * Description: Puts a C4 drawing on its page: everything moved so that the drawing, its labels and its title sit inside
 *              the padding, each boundary's heading lines placed by their left ends, each shape's texts centered one
 *              under the other, each relation's line copied once into the layout's list of segments.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics

extension C4DrawingPass {
    /// The layout: everything moved so that the drawing, its labels and its title sit `padding` inside the page, the
    /// title centered above and the drawing centered under a wider title. The title is measured into `texts`' lines,
    /// which the layout then keeps.
    func assembled(font: DiagramFont, titleRoom: CGFloat, texts: inout C4GridTexts) -> C4Layout {
        let title = measuring.measure(diagram.titleText, in: diagram, with: measuring.name, maximumWidth: titleRoom, into: &texts.lines)
        let titleHeight = title.measuredHeight > 0 ? title.measuredHeight + C4Metrics.titleGap : 0
        let inner = max(extent.width, title.measuredWidth)
        let padding = C4Metrics.padding
        let size = CGSize(width: (inner + 2 * padding).rounded(.up), height: (extent.height + titleHeight + 2 * padding).rounded(.up))
        let offset = CGVector(dx: padding - extent.minX + (inner - extent.width) / 2, dy: padding + titleHeight - extent.minY)
        let placedTitle = title.map { text in text.centered(at: CGPoint(x: size.width / 2, y: padding + text.height / 2)) }
        var headingLines: [DiagramMeasuredText] = []
        let boundaries = laidOutBoundaries(offset: offset, lines: texts.lines, headingLines: &headingLines)
        var segments: [DiagramPathSegment] = []
        let relations = laidOutRelations(offset: offset, segments: &segments)
        return C4Layout(size: size, font: font, lines: texts.lines, source: diagram.source, derived: diagram.derived, titleText: placedTitle,
                        boundaryRecords: boundaries, headingLines: headingLines, shapeRecords: laidOutShapes(offset: offset), relationRecords: relations,
                        segments: segments)
    }

    /// Each boundary but the top level, its heading's lines from its left end, one under the other.
    private func laidOutBoundaries(offset: CGVector, lines: DiagramMeasuredLines, headingLines: inout [DiagramMeasuredText]) -> [C4LaidOutBoundary] {
        var boundaries: [C4LaidOutBoundary] = []
        boundaries.reserveCapacity(groups.count - 1)
        for groupIndex in groups.indices.dropFirst() {
            let group = groups[groupIndex]
            let boundary = diagram.boundaryRecords[group.boundaryIndex]
            let frame = boxes[shapes.count + groupIndex - 1].frame.offsetBy(dx: offset.dx, dy: offset.dy)
            let left = frame.minX + group.headingLeft
            var top = frame.minY + C4Metrics.headingTop
            let nameLines = Self.placeLines(of: group.name, left: left, top: &top, lines: lines, into: &headingLines)
            let typeLines = Self.placeLines(of: group.type, left: left, top: &top, lines: lines, into: &headingLines)
            let descriptionLines = Self.placeLines(of: group.description, left: left, top: &top, lines: lines, into: &headingLines)
            let element = boundary.element
            boundaries.append(C4LaidOutBoundary(alias: element.alias, frame: frame, isDeploymentNode: boundary.deploymentNode != nil, nameLines: nameLines,
                                                typeLines: typeLines, descriptionLines: descriptionLines, look: diagram.look(of: element)))
        }
        return boundaries
    }

    /// The lines of `text`, each a text of its own placed by its left end from `top` down, as a block's `placedLines`
    /// places them; `top` moved past the text.
    private static func placeLines(of text: DiagramMeasuredText?, left: CGFloat, top: inout CGFloat, lines: DiagramMeasuredLines,
                                   into placed: inout [DiagramMeasuredText]) -> Range<Int> {
        let first = placed.count
        if let text {
            for index in 0..<Int(text.lineCount) {
                let lineIndex = Int(text.firstLine) + index
                let width = lines[lineIndex].width
                placed.append(DiagramMeasuredText(firstLine: Int32(lineIndex), lineCount: 1, width: width, height: text.lineHeight,
                                                  lineHeight: text.lineHeight, fontSize: text.fontSize, hasEmphasis: text.hasEmphasis,
                                                  center: CGPoint(x: left + width / 2, y: top + (CGFloat(index) + 0.5) * text.lineHeight)))
            }
        }
        top += text.measuredHeight
        return first..<placed.count
    }

    /// Each shape, its texts centered on it one under the other, below a person's head or a database's cap and left of a
    /// queue's front end.
    private func laidOutShapes(offset: CGVector) -> [C4LaidOutShape] {
        var laidOut: [C4LaidOutShape] = []
        laidOut.reserveCapacity(shapes.count)
        for (boxIndex, placed) in shapes.enumerated() {
            let shape = diagram.shapeRecords[placed.shapeIndex]
            let box = boxes[boxIndex]
            let frame = box.frame.offsetBy(dx: offset.dx, dy: offset.dy)
            let shiftX = box.form == .horizontalCylinder ? -C4Metrics.queueCapDepth(height: box.height) / 2 : 0
            let shiftY = box.form == .person ? C4Metrics.personHead / 2 : box.form == .cylinder ? C4Metrics.cylinderCapDepth(width: box.width) / 2 : 0
            let centerX = frame.midX + shiftX
            var top = frame.midY + shiftY - placed.textHeight / 2
            let type = Self.centered(placed.type, x: centerX, top: &top, gap: 0)
            let name = Self.centered(placed.name, x: centerX, top: &top, gap: 0)
            let technology = Self.centered(placed.technology, x: centerX, top: &top, gap: C4Metrics.descriptionGap)
            let description = Self.centered(placed.description, x: centerX, top: &top, gap: 0)
            let element = shape.element
            laidOut.append(C4LaidOutShape(alias: element.alias, kind: shape.kind, form: box.form, frame: frame, type: type, name: name,
                                          technology: technology, description: description, look: diagram.look(of: element)))
        }
        return laidOut
    }

    /// `text` centered across at `x` with its top at `top`; `top` moved past it and `gap`.
    private static func centered(_ text: DiagramMeasuredText?, x: CGFloat, top: inout CGFloat, gap: CGFloat) -> DiagramMeasuredText? {
        let placed = text.map { text in text.centered(at: CGPoint(x: x, y: top + text.height / 2)) }
        top += text.measuredHeight + gap
        return placed
    }

    /// Each relation with its label, everything moved by `offset`, its line's segments appended to `segments`.
    private func laidOutRelations(offset: CGVector, segments: inout [DiagramPathSegment]) -> [C4LaidOutRelation] {
        var laidOut: [C4LaidOutRelation] = []
        laidOut.reserveCapacity(relations.count)
        segments.reserveCapacity(relations.count * 2)
        for (routed, placedLabel) in zip(relations, labels) {
            let relation = diagram.relationRecords[routed.relationIndex]
            let route = routed.route
            let startMark = routed.pointsAtStart ? DiagramEdgeMark(arrowhead: .arrow, tip: route.start, direction: route.startDirection).translated(by: offset) : nil
            let endMark = routed.pointsAtEnd ? DiagramEdgeMark(arrowhead: .arrow, tip: route.end, direction: route.endDirection).translated(by: offset) : nil
            var corners = C4Numbers()
            for index in stride(from: 0, to: route.points.count, by: 2) {
                corners.append(route.points[index] + offset.dx)
                corners.append(route.points[index + 1] + offset.dy)
            }
            let firstSegment = segments.count
            for index in 0..<route.path.count { segments.append(route.path.segment(at: index, translatedBy: offset)) }
            laidOut.append(C4LaidOutRelation(from: relation.from, to: relation.to, pathStart: route.path.start.translated(by: offset),
                                             segments: firstSegment..<segments.count, corners: corners, startMark: startMark, endMark: endMark,
                                             labelFrame: placedLabel?.frame.offsetBy(dx: offset.dx, dy: offset.dy),
                                             label: placedLabel?.label?.translated(by: offset), technology: placedLabel?.technology?.translated(by: offset),
                                             lineColor: routed.lineColor, textColor: routed.textColor, isCased: routed.isCased))
        }
        return laidOut
    }
}
