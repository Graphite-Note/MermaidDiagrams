/**
 * File: RailroadDrawingParts.swift
 * --------------------------------
 * Layer: Core
 * Description: A laid-out railroad diagram's geometry grouped by how it is painted, its scene in Pele's colors and
 *              order, and its renderer.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// A laid-out railroad diagram's geometry grouped by how it is painted, back to front as Pele draws a rule: its name,
/// its track and arrows in the line color, the dots at its ends, then its boxes (terminals as pills on the surface
/// color, names of rules on the background, special sequences on the background in a dashed outline, each outlined in
/// the border color) and their text, the counts in the muted color. Rules do not overlap, so each group holds every
/// rule's.
public struct RailroadDrawingParts {
    public let title: DiagramTextBlock?
    public let ruleNames: [DiagramTextBlock]
    public let track: CGPath
    public let arrows: CGPath
    public let markers: CGPath
    public let terminals: CGPath
    public let nonterminals: CGPath
    public let specials: CGPath
    /// Drawn in the system's monospaced font.
    public let terminalTexts: [DiagramTextBlock]
    public let nonterminalTexts: [DiagramTextBlock]
    /// Drawn in italics, the question marks around them in the muted color.
    public let specialTexts: [DiagramTextBlock]
    public let specialQuestionMarks: [DiagramTextBlock]
    public let counts: [DiagramTextBlock]
    public let lineWidth: CGFloat

    /// Pele's dashes of a special sequence's outline, and the corner of a name's box.
    public static let specialDashLengths: [CGFloat] = [4, 3]
    static let cornerRadius: CGFloat = 4

    public init(layout: RailroadLayout) {
        title = layout.title
        ruleNames = layout.rules.map(\.name)
        let track = CGMutablePath()
        let arrows = CGMutablePath()
        let markers = CGMutablePath()
        for rule in layout.rules {
            for piece in rule.track { track.addPath(DiagramEdgeDrawing.path(piece)) }
            for arrow in rule.arrows {
                arrows.addLines(between: arrow.points)
                arrows.closeSubpath()
            }
            for center in rule.markerCenters {
                markers.addEllipse(in: CGRect(x: center.x - layout.markerRadius, y: center.y - layout.markerRadius, width: 2 * layout.markerRadius,
                                              height: 2 * layout.markerRadius))
            }
        }
        self.track = track
        self.arrows = arrows
        self.markers = markers
        let boxes = layout.rules.flatMap(\.boxes)
        terminals = Self.outlines(boxes, .terminal) { frame in frame.height / 2 }
        nonterminals = Self.outlines(boxes, .nonterminal) { _ in Self.cornerRadius }
        specials = Self.outlines(boxes, .special) { _ in Self.cornerRadius }
        terminalTexts = boxes.filter { box in box.kind == .terminal }.map(\.text)
        nonterminalTexts = boxes.filter { box in box.kind == .nonterminal }.map(\.text)
        specialTexts = boxes.filter { box in box.kind == .special }.map(\.text)
        specialQuestionMarks = boxes.flatMap(\.questionMarks)
        counts = layout.rules.flatMap(\.counts)
        lineWidth = layout.lineWidth
    }

    private static func outlines(_ boxes: [RailroadLayoutBox], _ kind: RailroadLayoutBox.Kind, radius: (CGRect) -> CGFloat) -> CGPath {
        let path = CGMutablePath()
        for box in boxes where box.kind == kind {
            let corner = min(radius(box.frame), box.frame.width / 2, box.frame.height / 2)
            path.addRoundedRect(in: box.frame, cornerWidth: corner, cornerHeight: corner)
        }
        return path
    }
}

extension DiagramScene {
    /// The railroad diagram's painting, in Pele's order and colors.
    public init(layout: RailroadLayout) {
        var builder = DiagramSceneBuilder()
        RailroadDrawingParts(layout: layout).addScene(to: &builder)
        self = builder.scene(size: layout.size, font: layout.font)
    }
}

extension RailroadDrawingParts {
    func addScene(to builder: inout DiagramSceneBuilder) {
        let line = DiagramStroke(lineWidth: lineWidth)
        builder.title(title)
        builder.texts(ruleNames, .foreground, isBold: true, part: .clusterLabel)
        builder.stroke(track, .line, line, part: .edge)
        builder.fill(arrows, .line, part: .marker)
        builder.fill(markers, .line, part: .marker)
        builder.fillAndStroke(terminals, fill: .surface, stroke: .border, line, part: .node)
        builder.fillAndStroke(nonterminals, fill: .background, stroke: .border, line, part: .node)
        builder.fillAndStroke(specials, fill: .background, stroke: .border, DiagramStroke(lineWidth: lineWidth, dashLengths: Self.specialDashLengths), part: .node)
        builder.texts(terminalTexts, .foreground, isMonospaced: true, part: .label)
        builder.texts(nonterminalTexts, .foreground, part: .label)
        builder.texts(specialQuestionMarks, .muted, isItalic: true, part: .label)
        builder.texts(specialTexts, .foreground, isItalic: true, part: .label)
        builder.texts(counts, .muted, part: .edgeLabel)
    }
}

/// Draws a laid-out railroad diagram into a Core Graphics context whose origin is the layout's top left and whose y
/// runs down, by painting its scene with `DiagramSceneRenderer`.
public enum RailroadRenderer {
    public static func draw(_ layout: RailroadLayout, in context: CGContext, palette: DiagramPalette) {
        DiagramSceneRenderer.draw(DiagramScene(layout: layout), in: context, palette: palette)
    }
}
