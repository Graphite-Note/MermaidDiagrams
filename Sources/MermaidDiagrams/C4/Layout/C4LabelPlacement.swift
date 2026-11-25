/**
 * File: C4LabelPlacement.swift
 * ----------------------------
 * Layer: Core
 * Description: Places the C4 headings and relation labels as Pele's render.ts does: a boundary's heading at the left,
 *              the middle or the right of its top, the first no line crosses; a relation's label on its line or beside
 *              it, slid along the line to the place that covers least of the shapes, arrowheads and labels already there.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

import CoreGraphics

/// A relation's label placed: the patch behind it and its two texts, the label then the technology.
struct C4PlacedLabel {
    let frame: CGRect
    let label: DiagramTextBlock?
    let technology: DiagramTextBlock?
}

extension C4DrawingPass {
    /// Each boundary's heading where the fewest lines cross it, taken so that labels keep off it.
    mutating func placeHeadings() {
        guard isCareful else { return }
        for groupIndex in groups.indices {
            guard let boxIndex = groupBoxIndices[groupIndex], groups[groupIndex].headingWidth > 0 else { continue }
            let box = boxes[boxIndex]
            let width = groups[groupIndex].headingWidth
            let top = box.y + C4Metrics.headingTop
            let bottom = box.y + groups[groupIndex].headingHeight - C4Metrics.lane
            var fewest = Int.max
            for left in [C4Metrics.headingLeft, (box.width - width) / 2, box.width - C4Metrics.headingLeft - width] {
                let count = relations.count { relation in
                    C4RouteGeometry.crosses(relation.route.points, left: box.x + left - 4, top: top, right: box.x + left + width + 4, bottom: bottom)
                }
                if count < fewest {
                    fewest = count
                    groups[groupIndex].headingLeft = left
                }
                if count == 0 { break }
            }
            let left = box.x + groups[groupIndex].headingLeft
            taken.append(CGRect(x: left - 4, y: top, width: width + 8, height: bottom - top))
        }
    }

    /// Each relation's label, nil for one with neither a label nor a technology. A dynamic diagram numbers its labels.
    mutating func placeLabels() -> [C4PlacedLabel?] {
        relations.map { relation in placeLabel(of: relation) }
    }

    private mutating func placeLabel(of routed: C4RoutedRelation) -> C4PlacedLabel? {
        let relation = diagram.relationRecords[routed.relationIndex]
        let route = routed.route
        let number = diagram.level == .dynamic ? routed.relationIndex + 1 : 0
        let label = C4TextLabel.numberedBlock(relation.label, number: number, in: diagram, measurer: measurers.small, maximumWidth: route.labelRoom)
        let technology = C4TextLabel.bracketedBlock(relation.technology, in: diagram, measurer: measurers.italicSmall, maximumWidth: route.labelRoom)
        let width = max(label.measuredWidth, technology.measuredWidth) + C4Metrics.labelPadding
        let height = label.measuredHeight + technology.measuredHeight
        guard height > 0 else { return nil }
        let center = labelCenter(of: route, relation: relation, size: CGSize(width: width, height: height))
        let frame = CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
        if isCareful { taken.append(frame) }
        grow(frame)
        let placedLabel = label.map { block in PlaneMapLabel.placed(block, at: CGPoint(x: center.x, y: frame.minY + block.size.height / 2)) }
        let placedTechnology = technology.map { block in
            PlaneMapLabel.placed(block, at: CGPoint(x: center.x, y: frame.minY + label.measuredHeight + block.size.height / 2))
        }
        return C4PlacedLabel(frame: frame, label: placedLabel, technology: placedTechnology)
    }

    /// The label sits on the line, or just beside it when another relation runs the opposite way, moved by the diagram's
    /// offsets unless tight. When careful it slides along the line to the place that covers least; the offsets are kept
    /// unless a place on the line itself covers less than any they lead to, as they are often tuned for Mermaid's spacing.
    private func labelCenter(of route: C4Route, relation: C4RelationRecord, size: CGSize) -> CGPoint {
        let side = route.labelSide
        let beside = abs(side.dx) * (size.width / 2) + abs(side.dy) * (size.height / 2) + 2
        let aside = route.labelLean != 0 ? max(0, min(route.labelLean, beside - 14)) : beside
        var shift = CGVector(dx: side.dx * aside + (isTight ? 0 : Self.offset(relation.labelOffsetX)),
                             dy: side.dy * aside + (isTight ? 0 : Self.offset(relation.labelOffsetY)))
        var along: CGFloat = 0.5
        let start = route.labelStretchStart
        let end = route.labelStretchEnd
        if isCareful {
            var least = CGFloat.infinity
            let onLine = CGVector(dx: side.dx * aside, dy: side.dy * aside)
            let isMoved = shift != onLine
            var pass = 0
            while pass < (isMoved ? 2 : 1), least > 0 {
                let tried = pass == 1 ? onLine : shift
                for place in C4Metrics.labelSlidePlaces {
                    let centerX = start.x + (end.x - start.x) * place + tried.dx
                    let centerY = start.y + (end.y - start.y) * place + tried.dy
                    let area = covered(CGRect(x: centerX - size.width / 2, y: centerY - size.height / 2, width: size.width, height: size.height))
                    if area < least {
                        least = area
                        along = place
                        shift = tried
                    }
                    if area == 0 { break }
                }
                pass += 1
            }
        }
        return CGPoint(x: start.x + (end.x - start.x) * along + shift.dx, y: start.y + (end.y - start.y) * along + shift.dy)
    }

    /// How much of the rectangle the shapes, arrowheads, headings and labels taken cover, added up.
    private func covered(_ rectangle: CGRect) -> CGFloat {
        var area: CGFloat = 0
        for other in taken {
            let width = min(rectangle.maxX, other.maxX) - max(rectangle.minX, other.minX)
            guard width > 0 else { continue }
            let height = min(rectangle.maxY, other.maxY) - max(rectangle.minY, other.minY)
            if height > 0 { area += width * height }
        }
        return area
    }

    /// A label offset the diagram sets, within 2,000 points either way; none for none or zero.
    private static func offset(_ value: Double?) -> CGFloat {
        guard let value, value != 0, !value.isNaN else { return 0 }
        return CGFloat(max(-Double(C4Metrics.largestLabelOffset), min(Double(C4Metrics.largestLabelOffset), value)))
    }
}
