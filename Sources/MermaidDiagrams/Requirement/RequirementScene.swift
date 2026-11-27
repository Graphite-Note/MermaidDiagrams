/**
 * File: RequirementScene.swift
 * ----------------------------
 * Layer: Core
 * Description: A laid-out requirement diagram's scene: its drawing parts in Pele's order and roles, its paths recorded
 *              into lanes of the scene's workspace.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 26/11/2026
 */

import CoreGraphics

extension DiagramScene {
    /// The requirement diagram's painting, as Pele paints it (`RequirementDrawingParts`).
    public init(layout: RequirementLayout) {
        self.init(layout: layout, limits: .standard)
    }

    /// The same painting, each of its paths holding at most the elements `limits` allow
    /// (`DiagramSceneWorkspace.elementLimit(for:)`): past them the scene says so, and its preparation refuses it.
    public init(layout: RequirementLayout, limits: MermaidDiagramLimits) {
        self = DiagramSceneWorkspace.withRecording(limits: limits) { workspace in
            var builder = DiagramSceneBuilder(workspace: workspace)
            RequirementSceneRecording.add(layout, to: &builder, workspace: workspace)
            return builder.scene(size: layout.size, font: layout.font)
        }
    }
}

/// Adds a requirement diagram's painting to a scene, its paths recorded into lanes of `workspace`, grouped as
/// `RequirementDrawingParts` groups them; each box the diagram gave colors of its own is painted apart, its lanes made for
/// a moment and given back.
enum RequirementSceneRecording {
    static func add(_ layout: RequirementLayout, to builder: inout DiagramSceneBuilder, workspace: DiagramSceneWorkspace) {
        layout.source.withUnsafeBufferPointer { source in add(layout, source: source, to: &builder, workspace: workspace) }
    }

    /// The painting, the names' and fields' lines read from `source`, the layout's text, borrowed.
    private static func add(_ layout: RequirementLayout, source: UnsafeBufferPointer<UInt8>, to builder: inout DiagramSceneBuilder,
                            workspace: DiagramSceneWorkspace) {
        let lineWidth = RequirementDrawingParts.lineWidth
        let line = DiagramStroke.rounded(lineWidth: lineWidth)
        let paths = RequirementPaths(layout: layout, making: workspace)
        let lines = layout.lines
        builder.title(layout.placedTitle, of: lines, source: source)
        builder.stroke(paths.solidLines, .line, line, part: .edge)
        builder.stroke(paths.dashedLines, .line, .rounded(lineWidth: lineWidth, dashLengths: RequirementDrawingParts.dashedLineLengths), part: .edge)
        builder.stroke(paths.marks, .line, line, part: .marker)
        builder.fill(paths.textPatches, .background, part: .labelBackground)
        for relation in layout.placedRelations { builder.text(relation.text, of: lines, source: source, .muted, part: .edgeLabel) }
        let outline = DiagramStroke(lineWidth: lineWidth)
        builder.fill(paths.boxFills, .surface, part: .node)
        builder.stroke(paths.boxOutlines, .border, outline, part: .node)
        for box in layout.placedBoxes where box.style == nil { builder.text(box.stereotype, of: lines, source: source, .muted, part: .stereotype) }
        for box in layout.placedBoxes where box.style == nil { builder.text(box.name, of: lines, source: source, .foreground, isBold: true, part: .label) }
        for box in layout.placedBoxes where box.style == nil {
            builder.texts(layout.fieldTexts[box.fieldNames], of: lines, source: source, .muted, part: .field)
        }
        for box in layout.placedBoxes where box.style == nil {
            builder.texts(layout.fieldTexts[box.fieldValues], of: lines, source: source, .foreground, part: .value)
        }
        for box in layout.placedBoxes where box.style != nil { addStyledBox(box, of: layout, source: source, to: &builder, workspace: workspace) }
    }

    /// A box in the colors and stroke its style sets, and the usual ones for the rest; all its text in its style's color, or
    /// else, on a fill it sets, in the ink that contrasts more with that fill (Pele's `inkFill`), or else in the usual roles.
    private static func addStyledBox(_ box: RequirementPlacedBox, of layout: RequirementLayout, source: UnsafeBufferPointer<UInt8>,
                                     to builder: inout DiagramSceneBuilder, workspace: DiagramSceneWorkspace) {
        let style = box.style ?? DiagramElementStyle()
        let madeCount = workspace.madePathCount
        defer { workspace.givePathsBack(downTo: madeCount) }
        let fill = workspace.makePath()
        let outline = workspace.makePath()
        RequirementDrawingParts.addBox(frame: box.frame, dividerY: box.dividerY, fill: fill, outline: outline, making: workspace)
        builder.keepNextShapeApart()
        builder.fill(fill, style.fill.map(DiagramPaint.color) ?? .surface, part: .node)
        builder.stroke(outline, style.stroke.map(DiagramPaint.color) ?? .border,
                       DiagramStroke(lineWidth: style.strokeWidth ?? RequirementDrawingParts.lineWidth, dashLengths: style.strokeDashLengths ?? []),
                       part: .node)
        let text = style.textColor.map(DiagramPaint.color) ?? TreemapInk.paint(onFill: style.fill)
        let lines = layout.lines
        builder.text(box.stereotype, of: lines, source: source, text ?? .muted, part: .stereotype)
        builder.text(box.name, of: lines, source: source, text ?? .foreground, isBold: true, part: .label)
        builder.texts(layout.fieldTexts[box.fieldNames], of: lines, source: source, text ?? .muted, part: .field)
        builder.texts(layout.fieldTexts[box.fieldValues], of: lines, source: source, text ?? .foreground, part: .value)
    }
}
