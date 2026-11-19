/**
 * File: WardleyMapAnnotationPlacement.swift
 * -----------------------------------------
 * Layer: Core
 * Description: A Wardley map's annotations, notes and forces as Pele's draw() places them: numbered circles and their
 *              list in a box, bold notes written from their point, and wide arrows with their names.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

import CoreGraphics

extension WardleyMapPlacement {
    /// A force's arrow: its length, its body's height and its head's length, Pele's.
    static var forceWidth: CGFloat { 60 }
    static var forceHeight: CGFloat { 30 }
    static var forceHead: CGFloat { 20 }

    /// Each annotation's numbered circle at each of its points, at least 10 points in radius; then the texts, by number,
    /// in a box at the annotations' place in the plot (kept inside it), else under the map.
    mutating func placeAnnotations() {
        for annotation in map.annotations {
            guard let number = PlaneMapLabel.block(JavaScriptNumberText.text(annotation.number), measurer: measurers.boldNumberText) else { continue }
            let center = canvas.point(annotation.point)
            let radius = max(10, number.size.width / 2 + 4)
            canvas.grow(center.x - radius, center.y - radius, center.x + radius, center.y + radius)
            layout.annotations.append(WardleyMapLayoutAnnotation(circles: [WardleyMapLayoutCircle(center: center, radius: radius)],
                                                                 numbers: [PlaneMapLabel.placed(number, at: center)]))
        }
        let listed = map.annotations.filter { annotation in !(annotation.text ?? "").isEmpty }.sorted { first, second in first.number < second.number }
        guard !listed.isEmpty else { return }
        let lines = listed.compactMap { annotation in
            PlaneMapLabel.block(JavaScriptNumberText.text(annotation.number) + ". " + (annotation.text ?? ""), measurer: measurers.text, maximumWidth: canvas.annotationListWidth)
        }
        let width = (lines.map(\.size.width).max() ?? 0) + 20
        let height = lines.reduce(0) { total, line in total + line.size.height } + 14
        let box = map.annotationsBox
        let left = box.map { box in min(max(canvas.x(box.x), 0), max(0, canvas.plotWidth - width)) } ?? 0
        let top = box.map { box in min(max(canvas.y(box.y), 0), max(0, canvas.plotHeight - height)) } ?? legendTop
        canvas.grow(left, top, left + width, top + height)
        var rows: [DiagramTextBlock] = []
        var y = top + 7
        for line in lines {
            rows += WardleyMapCanvas.lines(of: line, x: left + 10, baseline: y + line.lineHeight / 2 + measurers.text.fontSize * 0.35)
            y += line.size.height
        }
        layout.annotationList = WardleyMapLayoutAnnotationList(frame: CGRect(x: left, y: top, width: width, height: height), rows: rows)
    }

    /// Each note in bold from its point, wrapped at 360 points or six tenths of the plot; then the accelerators, pointing
    /// right, and the deaccelerators, pointing left, each with its bold name under it.
    mutating func placeNotesAndForces() {
        for note in map.notes {
            guard let text = PlaneMapLabel.block(note.text, measurer: measurers.boldText, maximumWidth: min(360, canvas.plotWidth * 0.6)) else { continue }
            let point = canvas.point(note.point)
            layout.notes.append(canvas.starting(text, x: point.x, baseline: point.y))
        }
        for force in map.accelerators { placeForce(force, isAccelerator: true) }
        for force in map.deaccelerators { placeForce(force, isAccelerator: false) }
    }

    private mutating func placeForce(_ force: WardleyMapForce, isAccelerator: Bool) {
        let point = canvas.point(force.point)
        let half = Self.forceHeight / 2
        let tip = isAccelerator ? point.x + Self.forceWidth : point.x
        let tail = isAccelerator ? point.x : point.x + Self.forceWidth
        let neck = isAccelerator ? point.x + Self.forceWidth - Self.forceHead : point.x + Self.forceHead
        let outline = DiagramPath(start: CGPoint(x: tail, y: point.y - half), segments: [
            .line(to: CGPoint(x: neck, y: point.y - half)), .line(to: CGPoint(x: neck, y: point.y - half - 8)), .line(to: CGPoint(x: tip, y: point.y)),
            .line(to: CGPoint(x: neck, y: point.y + half + 8)), .line(to: CGPoint(x: neck, y: point.y + half)), .line(to: CGPoint(x: tail, y: point.y + half)),
        ])
        canvas.grow(point.x, point.y - half - 8, point.x + Self.forceWidth, point.y + half + 8)
        let name = PlaneMapLabel.block(force.name, measurer: measurers.boldLinkText, maximumWidth: 160).map { block in
            canvas.centered(block, at: CGPoint(x: point.x + Self.forceWidth / 2, y: point.y + half + 8 + 12))
        }
        layout.forces.append(WardleyMapLayoutForce(outline: outline, isAccelerator: isAccelerator, name: name))
    }
}
