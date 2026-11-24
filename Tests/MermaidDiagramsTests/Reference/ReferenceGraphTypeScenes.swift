/**
 * File: ReferenceGraphTypeScenes.swift
 * ------------------------------------
 * Layer: Tests
 * Description: 0.7.0's state, class, entity relationship and requirement diagram scenes, frozen as main 2a0cc65 made them from Core Graphics paths (the
 *              public drawing parts and the builder's Core Graphics paths), which the scenes recorded into lanes are
 *              compared with.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// 0.7.0's state diagram scene, made from the public drawing parts' Core Graphics paths.
enum ReferenceStateDiagramScene {
    static func scene(layout: StateDiagramLayout) -> DiagramScene {
        var builder = DiagramSceneBuilder()
        let parts = StateDiagramDrawingParts(layout: layout)
        let line = DiagramStroke.rounded(lineWidth: StateDiagramDrawingParts.lineWidth)
        let dashed = DiagramStroke.rounded(lineWidth: StateDiagramDrawingParts.lineWidth, dashLengths: StateDiagramDrawingParts.noteConnectorDashLengths)
        parts.composites.addBoxes(to: &builder)
        builder.stroke(parts.compositeTitleRules, .border, line, part: .cluster)
        builder.stroke(parts.regionDividers, .border, dashed, part: .cluster)
        builder.stroke(parts.transitionLines, .line, line, part: .edge)
        builder.stroke(parts.noteConnectors, .border, dashed, part: .edge)
        builder.fill(parts.arrows, .line, part: .marker)
        parts.composites.addCrossedTitles(to: &builder)
        builder.fill(parts.transitionTextPatches, .background, part: .labelBackground)
        builder.texts(parts.transitionTexts, .foreground, part: .edgeLabel)
        builder.fill(parts.stateFills, .surface, part: .node)
        builder.stroke(parts.stateOutlines, .border, line, part: .node)
        builder.fillAndStroke(parts.endRings, fill: .background, stroke: .line, line, part: .node)
        builder.fill(parts.solidMarks, .line, part: .node)
        builder.texts(parts.stateTexts, .foreground, part: .label)
        builder.fillAndStroke(parts.noteSheets, fill: .background, stroke: .border, line, part: .note)
        builder.stroke(parts.noteFolds, .border, line, part: .note)
        builder.texts(parts.noteTexts, DiagramPaint.betweenBackgroundAndForeground(share: DiagramPalette.noteTextShare), part: .note)
        builder.title(parts.title)
        return builder.scene(size: layout.size, font: layout.font)
    }
}

/// 0.7.0's class diagram scene, made from the public drawing parts' Core Graphics paths.
enum ReferenceClassDiagramScene {
    static func scene(layout: ClassDiagramLayout) -> DiagramScene {
        var builder = DiagramSceneBuilder()
        let parts = ClassDiagramDrawingParts(layout: layout)
        let line = DiagramStroke.rounded(lineWidth: ClassDiagramDrawingParts.lineWidth)
        parts.namespaces.addBoxes(to: &builder)
        builder.stroke(parts.solidLines, .line, line, part: .edge)
        builder.stroke(parts.dashedLines, .line, .rounded(lineWidth: ClassDiagramDrawingParts.lineWidth, dashLengths: ClassDiagramDrawingParts.dashedDashLengths),
                       part: .edge)
        builder.stroke(parts.dottedLines, .line, .rounded(lineWidth: ClassDiagramDrawingParts.lineWidth, dashLengths: ClassDiagramDrawingParts.dottedDashLengths),
                       part: .edge)
        builder.fill(parts.filledMarks, .line, part: .marker)
        builder.stroke(parts.strokedMarks, .line, line, part: .marker)
        parts.namespaces.addCrossedTitles(to: &builder)
        builder.fill(parts.edgeTextPatches, .background, part: .labelBackground)
        builder.texts(parts.edgeTexts, .foreground, part: .edgeLabel)
        builder.texts(parts.cardinalities, .muted, part: .edgeLabel)
        builder.fill(parts.classFills, .surface, part: .node)
        builder.fill(parts.noteFills, .alternateSurface, part: .note)
        builder.stroke(parts.outlines, .border, line, part: .node)
        builder.texts(parts.annotations, .muted, part: .label)
        builder.texts(parts.names, .foreground, isBold: true, part: .label)
        for member in parts.members {
            switch member.classifier {
            case .plain, .static: builder.text(member.text, .foreground, part: .label)
            case .abstract: builder.text(member.text, .foreground, isItalic: true, part: .label)
            }
        }
        builder.stroke(parts.memberUnderlines, .foreground, line, part: .label)
        builder.texts(parts.noteTexts, .foreground, part: .note)
        builder.title(parts.title)
        return builder.scene(size: layout.size, font: layout.font)
    }
}

/// 0.7.0's entity relationship diagram scene, made from the public drawing parts' Core Graphics paths.
enum ReferenceEntityRelationshipScene {
    static func scene(layout: EntityRelationshipLayout) -> DiagramScene {
        var builder = DiagramSceneBuilder()
        let parts = EntityRelationshipDrawingParts(layout: layout)
        let line = DiagramStroke.rounded(lineWidth: EntityRelationshipDrawingParts.lineWidth)
        parts.subgraphs.addBoxes(to: &builder)
        builder.stroke(parts.identifyingLines, .line, line, part: .edge)
        builder.stroke(parts.nonIdentifyingLines, .line,
                       .rounded(lineWidth: EntityRelationshipDrawingParts.lineWidth, dashLengths: EntityRelationshipDrawingParts.nonIdentifyingDashLengths),
                       part: .edge)
        builder.fill(parts.markFills, .background, part: .marker)
        builder.stroke(parts.markOutlines, .line, line, part: .marker)
        builder.fill(parts.labelPatches, .background, part: .labelBackground)
        builder.texts(parts.labels, .foreground, part: .edgeLabel)
        builder.fill(parts.boxFills, .surface, part: .node)
        builder.fill(parts.rowStripes, .background, part: .node)
        builder.stroke(parts.boxOutlines, .border, line, part: .node)
        builder.texts(parts.entityTexts, .foreground, part: .label)
        builder.texts(parts.attributeDetails, DiagramPaint.foreground.atOpacity(EntityRelationshipDrawingParts.mutedTextOpacity), part: .label)
        builder.title(parts.title)
        return builder.scene(size: layout.size, font: layout.font)
    }
}

/// 0.7.0's requirement diagram scene, made from the public drawing parts' Core Graphics paths.
enum ReferenceRequirementScene {
    static func scene(layout: RequirementLayout) -> DiagramScene {
        var builder = DiagramSceneBuilder()
        let parts = RequirementDrawingParts(layout: layout)
        let line = DiagramStroke.rounded(lineWidth: RequirementDrawingParts.lineWidth)
        builder.title(parts.title)
        builder.stroke(parts.solidLines, .line, line, part: .edge)
        builder.stroke(parts.dashedLines, .line, .rounded(lineWidth: RequirementDrawingParts.lineWidth, dashLengths: RequirementDrawingParts.dashedLineLengths),
                       part: .edge)
        builder.stroke(parts.marks, .line, line, part: .marker)
        builder.fill(parts.textPatches, .background, part: .labelBackground)
        builder.texts(parts.texts, .muted, part: .edgeLabel)
        let outline = DiagramStroke(lineWidth: RequirementDrawingParts.lineWidth)
        builder.fill(parts.boxFills, .surface, part: .node)
        builder.stroke(parts.boxOutlines, .border, outline, part: .node)
        builder.texts(parts.stereotypes, .muted, part: .stereotype)
        builder.texts(parts.names, .foreground, isBold: true, part: .label)
        builder.texts(parts.fieldNames, .muted, part: .field)
        builder.texts(parts.fieldValues, .foreground, part: .value)
        for box in parts.styledBoxes {
            let style = box.style ?? DiagramElementStyle()
            let fill = CGMutablePath()
            let outline = CGMutablePath()
            RequirementDrawingParts.addBox(box, fill: fill, outline: outline)
            builder.keepNextShapeApart()
            builder.fill(fill, style.fill.map(DiagramPaint.color) ?? .surface, part: .node)
            builder.stroke(outline, style.stroke.map(DiagramPaint.color) ?? .border,
                           DiagramStroke(lineWidth: style.strokeWidth ?? RequirementDrawingParts.lineWidth, dashLengths: style.strokeDashLengths ?? []),
                           part: .node)
            let text = style.textColor.map(DiagramPaint.color) ?? TreemapInk.paint(onFill: style.fill)
            builder.text(box.stereotype, text ?? .muted, part: .stereotype)
            builder.text(box.name, text ?? .foreground, isBold: true, part: .label)
            builder.texts(box.fieldNames, text ?? .muted, part: .field)
            builder.texts(box.fieldValues, text ?? .foreground, part: .value)
        }
        return builder.scene(size: layout.size, font: layout.font)
    }
}
