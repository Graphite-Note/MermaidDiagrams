/**
 * File: IshikawaScene.swift
 * -------------------------
 * Layer: Core
 * Description: A laid-out Ishikawa diagram's scene, back to front in Pele's colors, across or down, and its renderer,
 *              which paints it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

extension DiagramScene {
    /// The diagram's painting, in Pele's order. Across: the title, the spine and its arrow in the line color, then each
    /// category's bones and arrow, its box in the surface color outlined in the border color, its name and its causes,
    /// a cause's causes muted, and last the head with its bold name. Down: the title, the connectors in the border color,
    /// then each entry's box (the effect's and the categories') and its name.
    public init(layout: IshikawaLayout) {
        var builder = DiagramSceneBuilder()
        builder.title(layout.title)
        let line = DiagramStroke(lineWidth: IshikawaScene.lineWidth)
        if let spine = layout.spine { builder.stroke(DiagramEdgeDrawing.path(spine), .line, line, part: .ishikawaSpine) }
        if let arrow = layout.spineArrow { builder.fill(IshikawaScene.arrowPath(arrow), .line, part: .marker) }
        for category in layout.categories {
            let bones = CGMutablePath()
            for bone in category.bones { bones.addPath(DiagramEdgeDrawing.path(bone)) }
            builder.stroke(bones, .line, line, part: .ishikawaBones)
            builder.fill(IshikawaScene.arrowPath(category.arrow), .line, part: .marker)
            builder.fillAndStroke(KanbanScene.roundedBox(category.box), fill: .surface, stroke: .border, line, part: .node)
            builder.text(category.label, .foreground, part: .label)
            for cause in category.causes { builder.text(cause.text, cause.isMuted ? .muted : .foreground, part: .label) }
        }
        if let head = layout.head {
            builder.fillAndStroke(IshikawaScene.headOutline(head.frame), fill: .surface, stroke: .border,
                                  DiagramStroke(lineWidth: IshikawaScene.lineWidth, lineJoin: .round), part: .node)
            builder.text(head.label, .foreground, isBold: true, part: .label)
        }
        let connectors = CGMutablePath()
        for connector in layout.outlineConnectors { connectors.addPath(DiagramEdgeDrawing.path(connector)) }
        builder.stroke(connectors, .border, line, part: .edge)
        for entry in layout.outlineEntries {
            if entry.isFramed {
                let corner = min(entry.cornerRadius, entry.frame.width / 2, entry.frame.height / 2)
                builder.fillAndStroke(CGPath(roundedRect: entry.frame, cornerWidth: corner, cornerHeight: corner, transform: nil), fill: .surface,
                                      stroke: .border, line, part: .node)
            }
            builder.text(entry.text, .foreground, isBold: entry.isFramed, part: .label)
        }
        self = builder.scene(size: layout.size, font: layout.font)
    }
}

enum IshikawaScene {
    static let lineWidth: CGFloat = 1

    static func arrowPath(_ mark: DiagramEdgeMark) -> CGPath {
        let filled = CGMutablePath()
        DiagramEdgeDrawing.addMark(mark, filled: filled, stroked: CGMutablePath())
        return filled
    }

    /// The head: flat on the spine's side, a half circle on the other.
    static func headOutline(_ frame: CGRect) -> CGPath {
        let radius = frame.height / 2
        let path = CGMutablePath()
        path.move(to: CGPoint(x: frame.minX, y: frame.minY))
        path.addLine(to: CGPoint(x: frame.maxX - radius, y: frame.minY))
        path.addArc(center: CGPoint(x: frame.maxX - radius, y: frame.midY), radius: radius, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false)
        path.addLine(to: CGPoint(x: frame.minX, y: frame.maxY))
        path.closeSubpath()
        return path
    }
}

/// Draws a laid-out Ishikawa diagram into a Core Graphics context whose origin is the layout's top left and whose y runs
/// down, by painting its scene with `DiagramSceneRenderer`.
public enum IshikawaRenderer {
    public static func draw(_ layout: IshikawaLayout, in context: CGContext, palette: DiagramPalette) {
        DiagramSceneRenderer.draw(DiagramScene(layout: layout), in: context, palette: palette)
    }
}
