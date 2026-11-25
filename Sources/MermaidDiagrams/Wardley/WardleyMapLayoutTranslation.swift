/**
 * File: WardleyMapLayoutTranslation.swift
 * ---------------------------------------
 * Layer: Core
 * Description: Moves a Wardley map laid out on its plot's coordinates onto the page, everything by one offset, where
 *              the layout keeps it.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

import CoreGraphics

extension WardleyMapLayout {
    /// Moves everything by `offset` where it is, each point and frame as `translated(by:)` of its kind moves it, so that
    /// no list is made again; the size and the title are the caller's.
    mutating func translate(by offset: CGVector) {
        translateFrame(by: offset)
        translateLines(by: offset)
        translateNodesAndNotes(by: offset)
    }

    /// The plot, the stages' and the grid's lines, the axes, the stages' names and the axes' titles.
    private mutating func translateFrame(by offset: CGVector) {
        plot = plot.offsetBy(dx: offset.dx, dy: offset.dy)
        for index in stageLines.indices { stageLines[index] = stageLines[index].translated(by: offset) }
        for index in gridLines.indices { gridLines[index] = gridLines[index].translated(by: offset) }
        axes = axes.translated(by: offset)
        Self.move(&stageLabels, by: offset)
        evolutionTitle = evolutionTitle?.translated(by: offset)
        visibilityTitle = visibilityTitle?.translated(by: offset)
    }

    /// The pipelines, the links with their arrows and labels, and the evolutions.
    private mutating func translateLines(by offset: CGVector) {
        for index in pipelines.indices {
            pipelines[index].frame = pipelines[index].frame.offsetBy(dx: offset.dx, dy: offset.dy)
            pipelines[index].line = pipelines[index].line?.translated(by: offset)
        }
        for index in links.indices {
            links[index].line = links[index].line.translated(by: offset)
            for arrow in links[index].arrows.indices { links[index].arrows[arrow] = links[index].arrows[arrow].translated(by: offset) }
            links[index].label = links[index].label?.translated(by: offset)
        }
        for index in trends.indices {
            trends[index].line = trends[index].line?.translated(by: offset)
            trends[index].arrow = trends[index].arrow?.translated(by: offset)
            trends[index].target = trends[index].target.translated(by: offset)
        }
    }

    /// The nodes, the annotations and their list, the notes and the forces.
    private mutating func translateNodesAndNotes(by offset: CGVector) {
        for index in nodes.indices {
            nodes[index].center = nodes[index].center.translated(by: offset)
            nodes[index].inertia = nodes[index].inertia.map { inertia in inertia.offsetBy(dx: offset.dx, dy: offset.dy) }
            Self.move(&nodes[index].label, by: offset)
        }
        for index in annotations.indices {
            for circle in annotations[index].circles.indices {
                annotations[index].circles[circle].center = annotations[index].circles[circle].center.translated(by: offset)
            }
            Self.move(&annotations[index].numbers, by: offset)
        }
        if var list = annotationList {
            // Taken out first, so that its rows are moved where they are.
            annotationList = nil
            list.frame = list.frame.offsetBy(dx: offset.dx, dy: offset.dy)
            Self.move(&list.rows, by: offset)
            annotationList = list
        }
        for index in notes.indices { Self.move(&notes[index], by: offset) }
        for index in forces.indices {
            forces[index].outline = forces[index].outline.translated(by: offset)
            forces[index].name = forces[index].name?.translated(by: offset)
        }
    }

    private static func move(_ lines: inout [DiagramTextBlock], by offset: CGVector) {
        for index in lines.indices { lines[index] = lines[index].translated(by: offset) }
    }
}
