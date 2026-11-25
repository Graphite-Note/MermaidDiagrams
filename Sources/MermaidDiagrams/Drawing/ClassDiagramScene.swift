/**
 * File: ClassDiagramScene.swift
 * -----------------------------
 * Layer: Core
 * Description: A laid-out class diagram's scene: its drawing parts back to front in the colors' roles, as Pele paints
 *              them, its paths recorded into lanes of the scene's workspace.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 24/11/2026
 */

import CoreGraphics

extension DiagramScene {
    /// The class diagram's painting: the namespaces' boxes, the lines and their marks, the namespaces' titles lines cross,
    /// the patches behind relation text and that text, the
    /// cardinalities, the boxes and notes, their text (abstract members in italics, static ones underlined), the title.
    /// Annotations and cardinalities are in the muted role and notes on the alternate surface, the colors
    /// `ClassDiagramPalette` names `muted` and `noteSurface`.
    public init(layout: ClassDiagramLayout) {
        self = DiagramSceneWorkspace.withRecording { workspace in
            var builder = DiagramSceneBuilder(workspace: workspace)
            ClassDiagramSceneRecording.add(layout, to: &builder, workspace: workspace)
            return builder.scene(size: layout.size, font: layout.font)
        }
    }
}

/// Adds a class diagram's painting to a scene, its paths recorded into lanes of `workspace`, grouped as
/// `ClassDiagramDrawingParts` groups them.
enum ClassDiagramSceneRecording {
    /// Every line is drawn with round caps and joins.
    static func add(_ layout: ClassDiagramLayout, to builder: inout DiagramSceneBuilder, workspace: DiagramSceneWorkspace) {
        let lineWidth = ClassDiagramDrawingParts.lineWidth
        let line = DiagramStroke.rounded(lineWidth: lineWidth)
        let namespaces = FlowchartClusterPaths(clusters: layout.namespaces, making: workspace)
        FlowchartSceneRecording.addBoxes(of: namespaces, to: &builder)
        let paths = ClassDiagramPaths(layout: layout, making: workspace)
        builder.stroke(paths.solidLines, .line, line, part: .edge)
        builder.stroke(paths.dashedLines, .line, .rounded(lineWidth: lineWidth, dashLengths: ClassDiagramDrawingParts.dashedDashLengths), part: .edge)
        builder.stroke(paths.dottedLines, .line, .rounded(lineWidth: lineWidth, dashLengths: ClassDiagramDrawingParts.dottedDashLengths), part: .edge)
        builder.fill(paths.filledMarks, .line, part: .marker)
        builder.stroke(paths.strokedMarks, .line, line, part: .marker)
        FlowchartSceneRecording.addCrossedTitles(of: namespaces, to: &builder)
        builder.fill(paths.edgeTextPatches, .background, part: .labelBackground)
        for edge in layout.relations { builder.text(edge.text, .foreground, part: .edgeLabel) }
        for edge in layout.relations {
            builder.text(edge.sourceCardinality, .muted, part: .edgeLabel)
            builder.text(edge.targetCardinality, .muted, part: .edgeLabel)
        }
        builder.fill(paths.classFills, .surface, part: .node)
        builder.fill(paths.noteFills, .alternateSurface, part: .note)
        builder.stroke(paths.outlines, .border, line, part: .node)
        for box in layout.classes { builder.texts(box.annotations, .muted, part: .label) }
        for box in layout.classes { builder.text(box.name, .foreground, isBold: true, part: .label) }
        for box in layout.classes {
            for member in box.members {
                switch member.classifier {
                case .plain, .static: builder.text(member.text, .foreground, part: .label)
                case .abstract: builder.text(member.text, .foreground, isItalic: true, part: .label)
                }
            }
        }
        builder.stroke(paths.memberUnderlines, .foreground, line, part: .label)
        for note in layout.notes { builder.text(note.text, .foreground, part: .note) }
        builder.texts(layout.interfaces, .foreground, part: .note)
        builder.title(layout.title)
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
