/**
 * File: RequirementPlacedBoxes.swift
 * ----------------------------------
 * Layer: Core
 * Description: A requirement diagram's box placed on its page around its center: its frame, its stereotype and name in
 *              its head, its divider, and a measured text for each line of its fields' names and values.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics

/// Places a measured box around its center as Pele's renderer draws one: the stereotype then the name centered in its
/// head, 10 points below its top; under the divider, its rows 10 points down and 2 apart, each field's name at 14 points
/// from the left and its value after the widest name and 12 points more, each line of several a text of its own.
enum RequirementPlacedBoxes {
    /// `box` placed around `center`, then moved by `offset`: each place found around `center` and moved as
    /// `translated(by:)` moves it; its fields' lines appended to `fieldTexts`, the names' then the values'.
    static func placed(_ box: RequirementMeasuredBox, at center: CGPoint, offset: CGVector, measured: RequirementMeasurement,
                       fieldTexts: inout [DiagramMeasuredText]) -> RequirementPlacedBox {
        let frame = CGRect(x: center.x - box.size.width / 2, y: center.y - box.size.height / 2, width: box.size.width, height: box.size.height)
        let headTop = frame.minY + RequirementMeasurement.paddingAlong
        let stereotype = box.stereotype.centered(at: CGPoint(x: center.x, y: headTop + box.stereotype.size.height / 2).translated(by: offset))
        let name = box.name.centered(at: CGPoint(x: center.x, y: headTop + box.stereotype.size.height + box.name.size.height / 2).translated(by: offset))
        let movedFrame = frame.offsetBy(dx: offset.dx, dy: offset.dy)
        let style = measured.style(of: box)
        guard box.rowCount > 0 else {
            return RequirementPlacedBox(frame: movedFrame, isRequirement: box.isRequirement, stereotype: stereotype, name: name, dividerY: nil,
                                        fieldNames: fieldTexts.count..<fieldTexts.count, fieldValues: fieldTexts.count..<fieldTexts.count, style: style)
        }
        let divider = frame.minY + box.headHeight
        let keyLeft = frame.minX + RequirementMeasurement.paddingAcross
        let valueLeft = keyLeft + box.keyWidth + RequirementMeasurement.columnGap
        let namesStart = fieldTexts.count
        var rowTop = divider + RequirementMeasurement.paddingAlong
        for row in box.rowIndices {
            appendStartingAt(measured.rows[row].key, left: keyLeft, top: rowTop, offset: offset, lines: measured.lines, to: &fieldTexts)
            rowTop += measured.rows[row].height + RequirementMeasurement.rowGap
        }
        let valuesStart = fieldTexts.count
        rowTop = divider + RequirementMeasurement.paddingAlong
        for row in box.rowIndices {
            appendStartingAt(measured.rows[row].value, left: valueLeft, top: rowTop, offset: offset, lines: measured.lines, to: &fieldTexts)
            rowTop += measured.rows[row].height + RequirementMeasurement.rowGap
        }
        return RequirementPlacedBox(frame: movedFrame, isRequirement: box.isRequirement, stereotype: stereotype, name: name, dividerY: divider + offset.dy,
                                    fieldNames: namesStart..<valuesStart, fieldValues: valuesStart..<fieldTexts.count, style: style)
    }

    /// The text's lines, each starting at `left`, the first line's box starting at `top`, as Pele writes a field, moved by
    /// `offset` (as `DiagramTextBlock.lineBlock(at:center:)` cuts a block of several lines, each line's place then moved).
    private static func appendStartingAt(_ text: DiagramMeasuredText, left: CGFloat, top: CGFloat, offset: CGVector, lines: borrowing DiagramMeasuredLines,
                                         to texts: inout [DiagramMeasuredText]) {
        let placed = text.centered(at: CGPoint(x: left + text.size.width / 2, y: top + text.size.height / 2))
        guard placed.lineCount > 1 else { return texts.append(placed.translated(by: offset)) }
        let lineLeft = placed.center.x - placed.size.width / 2
        let lineTop = placed.center.y - placed.size.height / 2
        for index in 0..<Int(placed.lineCount) {
            let lineWidth = lines[Int(placed.firstLine) + index].width
            let center = CGPoint(x: lineLeft + lineWidth / 2, y: lineTop + (CGFloat(index) + 0.5) * placed.lineHeight)
            let line = DiagramMeasuredText(firstLine: placed.firstLine + Int32(index), lineCount: 1, width: lineWidth, height: placed.lineHeight,
                                           lineHeight: placed.lineHeight, fontSize: placed.fontSize, hasEmphasis: placed.hasEmphasis, center: center)
            texts.append(line.translated(by: offset))
        }
    }
}
