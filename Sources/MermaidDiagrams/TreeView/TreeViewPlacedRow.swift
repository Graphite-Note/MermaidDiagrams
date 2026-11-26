/**
 * File: TreeViewPlacedRow.swift
 * -----------------------------
 * Layer: Core
 * Description: A tree view's row and guide line as its layout keeps them: a few numbers and measured texts, placed on
 *              the page, which the scene draws from directly and the public rows and guides are made from.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics

/// A row on the page: its band, its icon's square, and its name and description, each drawn line by line from its left
/// end and its first line's top.
struct TreeViewPlacedRow: Sendable {
    let entryIndex: Int32
    let isFolder: Bool
    let isHighlighted: Bool
    let glyph: TreeViewGlyph?
    /// The band behind a highlighted entry, to the tree's right edge.
    let highlight: CGRect
    let glyphFrame: CGRect
    let name: DiagramMeasuredText
    let nameLeft: CGFloat
    let nameTop: CGFloat
    /// The description, of no line when the entry has none.
    let description: DiagramMeasuredText
    let descriptionLeft: CGFloat
    let descriptionTop: CGFloat

    /// The name's lines, each a text of its own from its left end, as `DiagramTextBlock.placedLines(left:top:)` places them.
    func placedNameLines(_ lines: DiagramMeasuredLines) -> [DiagramMeasuredText] {
        (0..<Int(name.lineCount)).map { index in Self.line(index, of: name, left: nameLeft, top: nameTop, lines: lines) }
    }

    func placedDescriptionLines(_ lines: DiagramMeasuredLines) -> [DiagramMeasuredText] {
        (0..<Int(description.lineCount)).map { index in Self.line(index, of: description, left: descriptionLeft, top: descriptionTop, lines: lines) }
    }

    /// Line `index` of `text`, a text of `lines`, as a text of its own: its left end at `left`, `index` lines below `top`.
    static func line(_ index: Int, of text: DiagramMeasuredText, left: CGFloat, top: CGFloat, lines: borrowing DiagramMeasuredLines) -> DiagramMeasuredText {
        let width = lines[Int(text.firstLine) + index].width
        return DiagramMeasuredText(firstLine: text.firstLine + Int32(index), lineCount: 1, width: width, height: text.lineHeight,
                                   lineHeight: text.lineHeight, fontSize: text.fontSize, hasEmphasis: text.hasEmphasis,
                                   center: CGPoint(x: left + width / 2, y: top + (CGFloat(index) + 0.5) * text.lineHeight))
    }
}

/// A guide line: from under a folder (`top`) down to its last entry's middle (`bottom`), turning there with a rounded
/// elbow of `radius` to `tick`, or a line across from `across` to `tick` at `bottom`, to an entry other than the last.
struct TreeViewGuideStroke: Equatable, Sendable {
    let isElbow: Bool
    let across: CGFloat
    let top: CGFloat
    let bottom: CGFloat
    let radius: CGFloat
    let tick: CGFloat

    /// The line as a path: Pele's quadratic elbow as the cubic that draws it.
    var path: DiagramPath {
        guard isElbow else { return DiagramPath(start: CGPoint(x: across, y: bottom), segments: [.line(to: CGPoint(x: tick, y: bottom))]) }
        var segments: [DiagramPathSegment] = [.line(to: CGPoint(x: across, y: bottom - radius))]
        if radius > 0 {
            let (end, control1, control2) = elbow
            segments.append(.curve(to: end, control1: control1, control2: control2))
            segments.append(.line(to: CGPoint(x: tick, y: bottom)))
        }
        return DiagramPath(start: CGPoint(x: across, y: top), segments: segments)
    }

    /// The elbow's end and the controls of the cubic that draws Pele's quadratic from `(across, bottom - radius)` round
    /// the corner `(across, bottom)`.
    var elbow: (end: CGPoint, control1: CGPoint, control2: CGPoint) {
        let elbowStart = CGPoint(x: across, y: bottom - radius)
        let corner = CGPoint(x: across, y: bottom)
        let elbowEnd = CGPoint(x: across + radius, y: bottom)
        return (elbowEnd, CGPoint(x: elbowStart.x + 2 / 3 * (corner.x - elbowStart.x), y: elbowStart.y + 2 / 3 * (corner.y - elbowStart.y)),
                CGPoint(x: elbowEnd.x + 2 / 3 * (corner.x - elbowEnd.x), y: elbowEnd.y))
    }

    /// The line recorded as its path's elements are, into a lane that may hold other lines.
    func record(into lane: DiagramPathLane) {
        guard isElbow else {
            lane.move(to: CGPoint(x: across, y: bottom))
            lane.addLine(to: CGPoint(x: tick, y: bottom))
            return
        }
        lane.move(to: CGPoint(x: across, y: top))
        lane.addLine(to: CGPoint(x: across, y: bottom - radius))
        guard radius > 0 else { return }
        let (end, control1, control2) = elbow
        lane.addCurve(to: end, control1: control1, control2: control2)
        lane.addLine(to: CGPoint(x: tick, y: bottom))
    }
}
