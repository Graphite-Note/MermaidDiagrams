/**
 * File: ClassDiagramScene.swift
 * -----------------------------
 * Layer: Core
 * Description: A laid-out class diagram's scene: its drawing parts back to front in the colors' roles, as Pele paints
 *              them, its paths recorded into lanes of the scene's workspace.
 *
 * Authors: Bahey Shalash
 * Version: 0.5
 * Date: 26/11/2026
 */

import CoreGraphics

extension DiagramScene {
    /// The class diagram's painting: the namespaces' boxes, the lines and their marks, the namespaces' titles lines cross,
    /// the patches behind relation text and that text, the
    /// cardinalities, the boxes and notes, their text (abstract members in italics, static ones underlined), the title.
    /// Annotations and cardinalities are in the muted role and notes on the alternate surface, the colors
    /// `ClassDiagramPalette` names `muted` and `noteSurface`.
    public init(layout: ClassDiagramLayout) {
        self.init(layout: layout, limits: .standard)
    }

    /// The same painting, each of its paths holding at most the elements `limits` allow
    /// (`DiagramSceneWorkspace.elementLimit(for:)`): past them the scene says so, and its preparation refuses it.
    public init(layout: ClassDiagramLayout, limits: MermaidDiagramLimits) {
        self = DiagramSceneWorkspace.withRecording(limits: limits) { workspace in
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
        layout.source.withBytes { source in
            let lines = layout.lines
            for edge in layout.placedRelations { if let text = edge.text { builder.text(text, of: lines, source: source, .foreground, part: .edgeLabel) } }
            for edge in layout.placedRelations {
                if let text = edge.sourceCardinality { builder.text(text, of: lines, source: source, .muted, part: .edgeLabel) }
                if let text = edge.targetCardinality { builder.text(text, of: lines, source: source, .muted, part: .edgeLabel) }
            }
            builder.fill(paths.classFills, .surface, part: .node)
            builder.fill(paths.noteFills, .alternateSurface, part: .note)
            builder.stroke(paths.outlines, .border, line, part: .node)
            builder.texts(layout.placedAnnotations, of: lines, source: source, .muted, part: .label)
            for box in layout.placedClasses { builder.text(box.name, of: lines, source: source, .foreground, isBold: true, part: .label) }
            for member in layout.placedMembers {
                switch member.classifier {
                case .plain, .static: builder.text(member.text, of: lines, source: source, .foreground, part: .label)
                case .abstract: builder.text(member.text, of: lines, source: source, .foreground, isItalic: true, part: .label)
                }
            }
            builder.stroke(paths.memberUnderlines, .foreground, line, part: .label)
            for note in layout.placedNotes { builder.text(note.text, of: lines, source: source, .foreground, part: .note) }
            builder.texts(layout.placedInterfaces, of: lines, source: source, .foreground, part: .note)
            builder.title(layout.placedTitle, of: lines, source: source)
        }
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
