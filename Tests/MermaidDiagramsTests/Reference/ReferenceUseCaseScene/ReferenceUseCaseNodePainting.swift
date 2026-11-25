/**
 * File: ReferenceUseCaseNodePainting.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: 0.7.0's painting of a use case diagram's nodes (main dad6fb8's), frozen with its Core Graphics
 *              paths for the scene's reference.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

enum ReferenceUseCaseNodePainting {
    static func add(_ node: UseCaseLayoutNode, to builder: inout DiagramSceneBuilder) {
        let look = node.look
        let (strokePaint, stroke) = ReferenceUseCaseScenePainting.outline(look)
        let frame = node.frame
        let cornerRadius = ReferenceUseCaseScenePainting.cornerRadius
        switch node.form {
        case .actor(let type, let isBusiness):
            addFigure(of: node, type: type, isBusiness: isBusiness, to: &builder)
            // Pele measures a stereotype in its node's weight and slant but draws it plain.
            builder.text(node.stereotype, .muted, part: .stereotype)
            builder.text(node.label, ReferenceUseCaseScenePainting.textPaint(look, usual: .foreground, readsInk: false), isBold: look.isBold, isItalic: look.isItalic,
                         part: .label)
            return
        case .ellipse(let isBusiness):
            builder.fillAndStroke(CGPath(ellipseIn: frame, transform: nil), fill: ReferenceUseCaseScenePainting.fill(look, usual: .surface), stroke: strokePaint, stroke, part: .node)
            if isBusiness { builder.stroke(ReferenceUseCaseFigureShapes.ellipseSlash(in: frame), strokePaint, stroke, part: .business) }
        case .rectangle:
            builder.fillAndStroke(CGPath(roundedRect: frame, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil),
                                  fill: ReferenceUseCaseScenePainting.fill(look, usual: .surface),
                                  stroke: strokePaint, stroke, part: .node)
        case .note:
            let joined = DiagramStroke(lineWidth: stroke.lineWidth, dashLengths: stroke.dashLengths, lineJoin: .round)
            builder.fillAndStroke(ReferenceUseCaseFigureShapes.noteOutline(in: frame), fill: ReferenceUseCaseScenePainting.fill(look, usual: .alternateSurface), stroke: strokePaint,
                                  joined, part: .note)
            builder.stroke(ReferenceUseCaseFigureShapes.noteFold(in: frame), strokePaint, joined, part: .note)
        case .jsonTable:
            return addTable(node, to: &builder)
        }
        builder.text(node.stereotype, ReferenceUseCaseScenePainting.textPaint(look, usual: .muted, readsTextColor: false), part: .stereotype)
        builder.text(node.label, ReferenceUseCaseScenePainting.textPaint(look, usual: .foreground), isBold: look.isBold, isItalic: look.isItalic, part: .label)
    }

    /// An actor's figure, its middle 30 points below the top of its node, and a business actor's slash.
    private static func addFigure(of node: UseCaseLayoutNode, type: UseCaseActorType, isBusiness: Bool, to builder: inout DiagramSceneBuilder) {
        let look = node.look
        let (strokePaint, stroke) = ReferenceUseCaseScenePainting.outline(look)
        func fill(_ usual: DiagramPaint) -> DiagramPaint { ReferenceUseCaseScenePainting.fill(look, usual: usual) }
        let middle = CGPoint(x: node.center.x, y: node.frame.minY + UseCaseNodeMeasurement.figureHeight / 2)
        var headY = ReferenceUseCaseFigureShapes.headCenterY
        var radius = ReferenceUseCaseFigureShapes.headRadius
        switch type {
        case .normal:
            builder.fillAndStroke(ReferenceUseCaseFigureShapes.head(radius: radius, at: middle), fill: fill(.surface), stroke: strokePaint, stroke, part: .actorFigure)
            builder.stroke(ReferenceUseCaseFigureShapes.limbs(at: middle), strokePaint, stroke, part: .actorFigure)
        case .hollow:
            radius = ReferenceUseCaseFigureShapes.hollowHeadRadius
            builder.fillAndStroke(ReferenceUseCaseFigureShapes.head(radius: radius, at: middle), fill: fill(.background), stroke: strokePaint, stroke, part: .actorFigure)
            builder.keepNextShapeApart()
            builder.fillAndStroke(ReferenceUseCaseFigureShapes.hollowBody(at: middle), fill: fill(.background), stroke: strokePaint,
                                  DiagramStroke(lineWidth: stroke.lineWidth, dashLengths: stroke.dashLengths, lineJoin: .round), part: .actorFigure)
        case .awesome:
            let figure = ReferenceUseCaseFigureShapes.awesomeFigure(at: middle)
            if let written = look.stroke {
                builder.fillAndStroke(figure, fill: fill(.border), stroke: DiagramPaint.color(written).atOpacity(look.strokeAmount), stroke, part: .actorFigure)
            } else {
                builder.fill(figure, fill(.border), part: .actorFigure)
            }
        case .icon:
            headY = ReferenceUseCaseFigureShapes.iconHeadCenterY
            radius = ReferenceUseCaseFigureShapes.iconHeadRadius
            let box = ReferenceUseCaseFigureShapes.iconBox.offsetBy(dx: middle.x, dy: middle.y)
            builder.fillAndStroke(CGPath(roundedRect: box, cornerWidth: ReferenceUseCaseScenePainting.cornerRadius, cornerHeight: ReferenceUseCaseScenePainting.cornerRadius,
                                         transform: nil), fill: fill(.surface), stroke: strokePaint, stroke, part: .actorFigure)
        }
        if isBusiness { builder.stroke(ReferenceUseCaseFigureShapes.actorSlash(headY: headY, radius: radius, at: middle), strokePaint, stroke, part: .business) }
    }

    /// A JSON table's box, its lines, its name in bold, each row's key muted and its value.
    private static func addTable(_ node: UseCaseLayoutNode, to builder: inout DiagramSceneBuilder) {
        let look = node.look
        let (strokePaint, stroke) = ReferenceUseCaseScenePainting.outline(look)
        let radius = ReferenceUseCaseScenePainting.cornerRadius
        builder.fillAndStroke(CGPath(roundedRect: node.frame, cornerWidth: radius, cornerHeight: radius, transform: nil),
                              fill: ReferenceUseCaseScenePainting.fill(look, usual: .surface), stroke: strokePaint, stroke, part: .node)
        builder.stroke(ReferenceUseCaseFigureShapes.tableLines(in: node.frame, headHeight: node.headHeight, keyColumnWidth: node.keyColumnWidth), strokePaint, stroke,
                       part: .jsonLines)
        builder.text(node.label, ReferenceUseCaseScenePainting.textPaint(look, usual: .foreground), isBold: true, isItalic: look.isItalic, part: .label)
        let keyPaint = ReferenceUseCaseScenePainting.textPaint(look, usual: .muted, readsTextColor: false)
        let valuePaint = ReferenceUseCaseScenePainting.textPaint(look, usual: .foreground)
        for row in node.rows {
            // Pele measures a key in its table's weight and slant but draws it plain.
            builder.text(row.key, keyPaint, part: .jsonKey)
            builder.texts(row.valueLines, valuePaint, isBold: look.isBold, isItalic: look.isItalic, part: .jsonValue)
        }
    }
}
