/**
 * File: WardleyMapLinkRouting.swift
 * ---------------------------------
 * Layer: Core
 * Description: A Wardley map's pipelines, links and evolutions as Pele's draw() places them: a pipeline's box under its
 *              parent, links stopped short of their nodes with arrows by their flow, evolutions dashed to open circles.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics
import Foundation

extension WardleyMapPlacement {
    /// A component's radius, a pipeline parent's square, and a pipeline's padding: Pele's.
    static var componentRadius: CGFloat { 6 }
    static var squareSide: CGFloat { 10 }
    static var pipelinePadding: CGFloat { 15 }

    /// Each pipeline's box around its components, 15 points past the outer ones and four radii tall from two radii above
    /// them, with its parent moved to the middle of the box's top as a square; a dashed line through several components.
    mutating func placePipelines() {
        let radius = Self.componentRadius
        for pipeline in map.pipelines {
            pipelineMembers[pipeline.nodeIdentifier] = Set(pipeline.componentIdentifiers)
            let parts = pipeline.componentIdentifiers.compactMap { identifier in indexByIdentifier[identifier].map { index in positions[index] } }
                .sorted { first, second in first.x < second.x }
            guard let first = parts.first, let last = parts.last else { continue }
            let top = first.y - 2 * radius
            if let parent = indexByIdentifier[pipeline.nodeIdentifier] {
                positions[parent] = CGPoint(x: (first.x + last.x) / 2, y: top - Self.squareSide / 6)
            }
            canvas.grow(first.x - Self.pipelinePadding, top, last.x + Self.pipelinePadding, top + 4 * radius)
            let frame = CGRect(x: first.x - Self.pipelinePadding, y: top, width: last.x - first.x + 2 * Self.pipelinePadding, height: 4 * radius)
            let line = parts.count > 1 ? DiagramPath(start: CGPoint(x: first.x, y: first.y), segments: [.line(to: CGPoint(x: last.x, y: first.y))]) : nil
            layout.pipelines.append(WardleyMapLayoutPipeline(frame: frame, line: line))
        }
    }

    /// How far from a node's center a line toward it along (`across`, `down`) stops: an anchor's text's ellipse, a
    /// parent's square's half diagonal, a sourced component's ring, else a component's circle.
    func reach(_ index: Int, across: CGFloat, down: CGFloat) -> CGFloat {
        let node = map.nodes[index]
        if node.kind == .anchor {
            let width = anchorLabels[index]?.size.width ?? 0
            return 1 / hypot(across / (width / 2 + 5), down / (measurers.boldText.fontSize * 0.8))
        }
        if node.isPipelineParent { return Self.squareSide / 2.0.squareRoot() }
        return node.sourcing != nil ? 2 * Self.componentRadius : Self.componentRadius
    }

    /// Marks the quadrant around a node that a line leaving it along (`across`, `down`) runs through, unless the line is
    /// nearly level or upright.
    mutating func occupy(_ index: Int, across: CGFloat, down: CGFloat) {
        if abs(across) < 0.25 || abs(down) < 0.25 { return }
        takenQuadrants[index] |= across > 0 ? (down < 0 ? 1 : 2) : (down < 0 ? 4 : 8)
    }

    /// Each link between two placed nodes, but a parent's to its own pipeline's components: a line stopped at each node's
    /// reach, arrows at the ends its flow points to, and its label beside the middle on the upper side.
    mutating func placeLinks() {
        for link in map.links {
            guard let from = indexByIdentifier[link.source], let to = indexByIdentifier[link.target], from != to,
                  pipelineMembers[link.target]?.contains(link.source) != true else { continue }
            let start = positions[from]
            let end = positions[to]
            let distance = hypot(end.x - start.x, end.y - start.y)
            guard distance >= 0.01 else { continue }
            let across = (end.x - start.x) / distance
            let down = (end.y - start.y) / distance
            let startReach = reach(from, across: across, down: down)
            let endReach = reach(to, across: across, down: down)
            guard startReach + endReach < distance else { continue }
            occupy(from, across: across, down: down)
            occupy(to, across: -across, down: -down)
            var lineStart = CGPoint(x: start.x + across * startReach, y: start.y + down * startReach)
            var lineEnd = CGPoint(x: end.x - across * endReach, y: end.y - down * endReach)
            let trim = DiagramEdgeMark.lineTrim(for: .arrow)
            var arrows: [DiagramEdgeMark] = []
            if link.flow == .forward || link.flow == .bidirectional {
                arrows.append(DiagramEdgeMark(arrowhead: .arrow, tip: lineEnd, direction: CGVector(dx: across, dy: down)))
                lineEnd = CGPoint(x: lineEnd.x - across * trim, y: lineEnd.y - down * trim)
            }
            if link.flow == .backward || link.flow == .bidirectional {
                arrows.append(DiagramEdgeMark(arrowhead: .arrow, tip: lineStart, direction: CGVector(dx: -across, dy: -down)))
                lineStart = CGPoint(x: lineStart.x + across * trim, y: lineStart.y + down * trim)
            }
            let label = link.label.flatMap { text in placedLinkLabel(text, from: start, to: end, across: across, down: down) }
            layout.links.append(WardleyMapLayoutLink(line: DiagramPath(start: lineStart, segments: [.line(to: lineEnd)]), isDashed: link.isDashed, arrows: arrows,
                                                     label: label))
        }
    }

    /// A link's label 5 points beside the middle of its line, on its upper side.
    private mutating func placedLinkLabel(_ text: String, from start: CGPoint, to end: CGPoint, across: CGFloat, down: CGFloat) -> DiagramTextBlock? {
        guard let block = PlaneMapLabel.block(text, measurer: measurers.linkText, maximumWidth: 200) else { return nil }
        let side: CGFloat = across >= 0 ? 1 : -1
        let normal = CGVector(dx: down * side, dy: -across * side)
        let away = 5 + abs(normal.dx) * block.size.width / 2 + abs(normal.dy) * block.size.height / 2
        return canvas.centered(block, at: CGPoint(x: (start.x + end.x) / 2 + normal.dx * away, y: (start.y + end.y) / 2 + normal.dy * away))
    }

    /// Each evolution: a dashed line from the component's reach to an arrow two points short of an open circle where it
    /// is heading, when the circle is far enough; the circle alone otherwise.
    mutating func placeTrends() {
        let radius = Self.componentRadius
        for trend in map.trends {
            guard let index = indexByIdentifier[trend.nodeIdentifier] else { continue }
            let origin = positions[index]
            let target = canvas.point(trend.target)
            let distance = hypot(target.x - origin.x, target.y - origin.y)
            let across = distance > 0 ? (target.x - origin.x) / distance : 0
            let down = distance > 0 ? (target.y - origin.y) / distance : 0
            let start = distance > 0 ? reach(index, across: across, down: down) : 0
            var placed = WardleyMapLayoutTrend(line: nil, arrow: nil, target: target)
            if distance > start + radius + 4 {
                let tip = CGPoint(x: target.x - across * (radius + 2), y: target.y - down * (radius + 2))
                let trim = DiagramEdgeMark.lineTrim(for: .arrow)
                placed.line = DiagramPath(start: CGPoint(x: origin.x + across * start, y: origin.y + down * start),
                                          segments: [.line(to: CGPoint(x: tip.x - across * trim, y: tip.y - down * trim))])
                placed.arrow = DiagramEdgeMark(arrowhead: .arrow, tip: tip, direction: CGVector(dx: across, dy: down))
            }
            canvas.grow(target.x - radius, target.y - radius, target.x + radius, target.y + radius)
            layout.trends.append(placed)
        }
    }
}
