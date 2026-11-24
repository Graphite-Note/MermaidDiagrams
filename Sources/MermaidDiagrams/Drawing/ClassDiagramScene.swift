/**
 * File: ClassDiagramScene.swift
 * -----------------------------
 * Layer: Core
 * Description: A laid-out class diagram's scene: its drawing parts back to front in the colors' roles, as Pele paints
 *              them.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 23/11/2026
 */

import CoreGraphics

extension DiagramScene {
    /// The class diagram's painting: the namespaces' boxes, the lines and their marks, the namespaces' titles lines cross,
    /// the patches behind relation text and that text, the
    /// cardinalities, the boxes and notes, their text (abstract members in italics, static ones underlined), the title.
    /// Annotations and cardinalities are in the muted role and notes on the alternate surface, the colors
    /// `ClassDiagramPalette` names `muted` and `noteSurface`.
    public init(layout: ClassDiagramLayout) {
        var builder = DiagramSceneBuilder()
        ClassDiagramDrawingParts(layout: layout).addScene(to: &builder)
        self = builder.scene(size: layout.size, font: layout.font)
    }
}

extension ClassDiagramDrawingParts {
    /// Every line is drawn with round caps and joins.
    func addScene(to builder: inout DiagramSceneBuilder) {
        let line = DiagramStroke.rounded(lineWidth: Self.lineWidth)
        namespaces.addBoxes(to: &builder)
        builder.stroke(solidLinesScenePath, .line, line, part: .edge)
        builder.stroke(dashedLinesScenePath, .line, .rounded(lineWidth: Self.lineWidth, dashLengths: Self.dashedDashLengths), part: .edge)
        builder.stroke(dottedLinesScenePath, .line, .rounded(lineWidth: Self.lineWidth, dashLengths: Self.dottedDashLengths), part: .edge)
        builder.fill(filledMarksScenePath, .line, part: .marker)
        builder.stroke(strokedMarksScenePath, .line, line, part: .marker)
        namespaces.addCrossedTitles(to: &builder)
        builder.fill(edgeTextPatchesScenePath, .background, part: .labelBackground)
        builder.texts(edgeTexts, .foreground, part: .edgeLabel)
        builder.texts(cardinalities, .muted, part: .edgeLabel)
        builder.fill(classFillsScenePath, .surface, part: .node)
        builder.fill(noteFillsScenePath, .alternateSurface, part: .note)
        builder.stroke(outlinesScenePath, .border, line, part: .node)
        builder.texts(annotations, .muted, part: .label)
        builder.texts(names, .foreground, isBold: true, part: .label)
        for member in members {
            switch member.classifier {
            case .plain, .static: builder.text(member.text, .foreground, part: .label)
            case .abstract: builder.text(member.text, .foreground, isItalic: true, part: .label)
            }
        }
        builder.stroke(memberUnderlinesScenePath, .foreground, line, part: .label)
        builder.texts(noteTexts, .foreground, part: .note)
        builder.title(title)
    }
}

extension ClassDiagramPalette {
    /// The diagram's palette with this one's muted color and note surface in the roles a class diagram's scene names
    /// them by (`muted`, `alternateSurface`).
    public var scenePalette: DiagramPalette {
        var palette = diagram
        palette.muted = muted
        palette.alternateSurface = noteSurface
        return palette
    }
}
