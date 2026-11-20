/**
 * File: UseCaseNodePainting.swift
 * -------------------------------
 * Layer: Core
 * Description: The nodes of a use case diagram's scene as Pele paints them: an actor's figure with its stereotype and
 *              label, an oval or a box with its texts, a note with its folded corner, a JSON table with its rows.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

enum UseCaseNodePainting {
    static func add(_ node: UseCaseLayoutNode, to builder: inout DiagramSceneBuilder) {
        let look = node.look
        let (strokePaint, stroke) = UseCaseScenePainting.outline(look)
        let fill = look.fill.map(DiagramPaint.color)
        let frame = node.frame
        let cornerRadius = UseCaseScenePainting.cornerRadius
        switch node.form {
        case .actor(let type, let isBusiness):
            addFigure(of: node, type: type, isBusiness: isBusiness, to: &builder)
            builder.text(node.stereotype, .muted, isBold: look.isBold, isItalic: look.isItalic, part: .stereotype)
            builder.text(node.label, UseCaseScenePainting.textPaint(look, usual: .foreground, readsInk: false), isBold: look.isBold, isItalic: look.isItalic,
                         part: .label)
            return
        case .ellipse(let isBusiness):
            builder.fillAndStroke(CGPath(ellipseIn: frame, transform: nil), fill: fill ?? .surface, stroke: strokePaint, stroke, part: .node)
            if isBusiness { builder.stroke(UseCaseFigureShapes.ellipseSlash(in: frame), strokePaint, stroke, part: .business) }
        case .rectangle:
            builder.fillAndStroke(CGPath(roundedRect: frame, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil), fill: fill ?? .surface,
                                  stroke: strokePaint, stroke, part: .node)
        case .note:
            let joined = DiagramStroke(lineWidth: stroke.lineWidth, dashLengths: stroke.dashLengths, lineJoin: .round)
            builder.fillAndStroke(UseCaseFigureShapes.noteOutline(in: frame), fill: fill ?? .alternateSurface, stroke: strokePaint, joined, part: .note)
            builder.stroke(UseCaseFigureShapes.noteFold(in: frame), strokePaint, joined, part: .note)
        case .jsonTable:
            return addTable(node, to: &builder)
        }
        builder.text(node.stereotype, UseCaseScenePainting.textPaint(look, usual: .muted, readsTextColor: false), isBold: look.isBold,
                     isItalic: look.isItalic, part: .stereotype)
        builder.text(node.label, UseCaseScenePainting.textPaint(look, usual: .foreground), isBold: look.isBold, isItalic: look.isItalic, part: .label)
    }

    /// An actor's figure, its middle 30 points below the top of its node, and a business actor's slash.
    private static func addFigure(of node: UseCaseLayoutNode, type: UseCaseActorType, isBusiness: Bool, to builder: inout DiagramSceneBuilder) {
        let look = node.look
        let (strokePaint, stroke) = UseCaseScenePainting.outline(look)
        let fill = look.fill.map(DiagramPaint.color)
        let middle = CGPoint(x: node.center.x, y: node.frame.minY + UseCaseNodeMeasurement.figureHeight / 2)
        var headY = UseCaseFigureShapes.headCenterY
        var radius = UseCaseFigureShapes.headRadius
        switch type {
        case .normal:
            builder.fillAndStroke(UseCaseFigureShapes.head(radius: radius, at: middle), fill: fill ?? .surface, stroke: strokePaint, stroke, part: .actorFigure)
            builder.stroke(UseCaseFigureShapes.limbs(at: middle), strokePaint, stroke, part: .actorFigure)
        case .hollow:
            radius = UseCaseFigureShapes.hollowHeadRadius
            builder.fillAndStroke(UseCaseFigureShapes.head(radius: radius, at: middle), fill: fill ?? .background, stroke: strokePaint, stroke, part: .actorFigure)
            builder.keepNextShapeApart()
            builder.fillAndStroke(UseCaseFigureShapes.hollowBody(at: middle), fill: fill ?? .background, stroke: strokePaint,
                                  DiagramStroke(lineWidth: stroke.lineWidth, dashLengths: stroke.dashLengths, lineJoin: .round), part: .actorFigure)
        case .awesome:
            let figure = UseCaseFigureShapes.awesomeFigure(at: middle)
            if let written = look.stroke {
                builder.fillAndStroke(figure, fill: fill ?? .border, stroke: .color(written), stroke, part: .actorFigure)
            } else {
                builder.fill(figure, fill ?? .border, part: .actorFigure)
            }
        case .icon:
            headY = UseCaseFigureShapes.iconHeadCenterY
            radius = UseCaseFigureShapes.iconHeadRadius
            let box = UseCaseFigureShapes.iconBox.offsetBy(dx: middle.x, dy: middle.y)
            builder.fillAndStroke(CGPath(roundedRect: box, cornerWidth: UseCaseScenePainting.cornerRadius, cornerHeight: UseCaseScenePainting.cornerRadius,
                                         transform: nil), fill: fill ?? .surface, stroke: strokePaint, stroke, part: .actorFigure)
        }
        if isBusiness { builder.stroke(UseCaseFigureShapes.actorSlash(headY: headY, radius: radius, at: middle), strokePaint, stroke, part: .business) }
    }

    /// A JSON table's box, its lines, its name in bold, each row's key muted and its value.
    private static func addTable(_ node: UseCaseLayoutNode, to builder: inout DiagramSceneBuilder) {
        let look = node.look
        let (strokePaint, stroke) = UseCaseScenePainting.outline(look)
        let radius = UseCaseScenePainting.cornerRadius
        builder.fillAndStroke(CGPath(roundedRect: node.frame, cornerWidth: radius, cornerHeight: radius, transform: nil),
                              fill: look.fill.map(DiagramPaint.color) ?? .surface, stroke: strokePaint, stroke, part: .node)
        builder.stroke(UseCaseFigureShapes.tableLines(in: node.frame, headHeight: node.headHeight, keyColumnWidth: node.keyColumnWidth), strokePaint, stroke,
                       part: .jsonLines)
        builder.text(node.label, UseCaseScenePainting.textPaint(look, usual: .foreground), isBold: true, isItalic: look.isItalic, part: .label)
        let keyPaint = UseCaseScenePainting.textPaint(look, usual: .muted, readsTextColor: false)
        let valuePaint = UseCaseScenePainting.textPaint(look, usual: .foreground)
        for row in node.rows {
            builder.text(row.key, keyPaint, isBold: look.isBold, isItalic: look.isItalic, part: .jsonKey)
            builder.texts(row.valueLines, valuePaint, isBold: look.isBold, isItalic: look.isItalic, part: .jsonValue)
        }
    }
}
