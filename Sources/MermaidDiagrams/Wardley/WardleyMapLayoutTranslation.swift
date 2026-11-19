/**
 * File: WardleyMapLayoutTranslation.swift
 * ---------------------------------------
 * Layer: Core
 * Description: Moves a Wardley map laid out on its plot's coordinates onto the page, everything by one offset.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

extension WardleyMapLayout {
    /// The layout with everything moved by `offset`; the size and the title are the caller's.
    func translated(by offset: CGVector) -> WardleyMapLayout {
        var moved = self
        func point(_ point: CGPoint) -> CGPoint { point.translated(by: offset) }
        func frame(_ frame: CGRect) -> CGRect { frame.offsetBy(dx: offset.dx, dy: offset.dy) }
        moved.plot = frame(plot)
        moved.stageLines = stageLines.map { line in line.translated(by: offset) }
        moved.gridLines = gridLines.map { line in line.translated(by: offset) }
        moved.axes = axes.translated(by: offset)
        moved.stageLabels = stageLabels.map { label in label.translated(by: offset) }
        moved.evolutionTitle = evolutionTitle?.translated(by: offset)
        moved.visibilityTitle = visibilityTitle?.translated(by: offset)
        moved.pipelines = pipelines.map { pipeline in WardleyMapLayoutPipeline(frame: frame(pipeline.frame), line: pipeline.line?.translated(by: offset)) }
        moved.links = links.map { link in
            WardleyMapLayoutLink(line: link.line.translated(by: offset), isDashed: link.isDashed, arrows: link.arrows.map { arrow in arrow.translated(by: offset) },
                                 label: link.label?.translated(by: offset))
        }
        moved.trends = trends.map { trend in
            WardleyMapLayoutTrend(line: trend.line?.translated(by: offset), arrow: trend.arrow?.translated(by: offset), target: point(trend.target))
        }
        moved.nodes = nodes.map { node in
            var movedNode = node
            movedNode.center = point(node.center)
            movedNode.inertia = node.inertia.map(frame)
            movedNode.label = node.label.map { line in line.translated(by: offset) }
            return movedNode
        }
        moved.annotations = annotations.map { annotation in
            WardleyMapLayoutAnnotation(circles: annotation.circles.map { circle in WardleyMapLayoutCircle(center: point(circle.center), radius: circle.radius) },
                                       numbers: annotation.numbers.map { number in number.translated(by: offset) })
        }
        moved.annotationList = annotationList.map { list in
            WardleyMapLayoutAnnotationList(frame: frame(list.frame), rows: list.rows.map { row in row.translated(by: offset) })
        }
        moved.notes = notes.map { lines in lines.map { line in line.translated(by: offset) } }
        moved.forces = forces.map { force in
            WardleyMapLayoutForce(outline: force.outline.translated(by: offset), isAccelerator: force.isAccelerator, name: force.name?.translated(by: offset))
        }
        return moved
    }
}
