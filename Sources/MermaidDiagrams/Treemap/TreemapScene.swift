/**
 * File: TreemapScene.swift
 * ------------------------
 * Layer: Core
 * Description: A laid-out treemap's scene: its boxes recorded into lanes of the thread's scene workspace and added back
 *              to front in the colors' roles with their texts, as Pele paints them, without a Core Graphics path.
 *
 * Authors: Bahey Shalash
 * Version: 0.5
 * Date: 25/11/2026
 */

import CoreGraphics

extension DiagramScene {
    /// The treemap's painting: the title, the sections as tints of their series colors with their names and totals, then the
    /// leaves in their series colors with their names and values.
    public init(layout: TreemapLayout) {
        self.init(layout: layout, limits: .standard)
    }

    /// The same painting recorded under `limits`: a scene one of whose lanes goes past their element limit says so
    /// (`exceededPathElementLimit`), and the preparation refuses it.
    public init(layout: TreemapLayout, limits: MermaidDiagramLimits) {
        self = DiagramSceneWorkspace.withRecording(limits: limits) { workspace in
            var builder = DiagramSceneBuilder(workspace: workspace)
            TreemapSceneRecording.add(layout, to: &builder, workspace: workspace)
            return builder.scene(size: layout.size, font: layout.font, seriesColors: layout.seriesColors)
        }
    }
}

/// Adds a treemap's painting to a scene in `TreemapDrawingParts`' order and paints, each box's rounded outline recorded
/// into a lane of `workspace` given back once added.
enum TreemapSceneRecording {
    static func add(_ layout: TreemapLayout, to builder: inout DiagramSceneBuilder, workspace: DiagramSceneWorkspace) {
        builder.title(layout.title)
        for box in layout.boxes where box.isSection && box.hasHeader {
            add(box, look: TreemapDrawingParts.sectionLook(box), part: .section, to: &builder, workspace: workspace)
        }
        addTexts(of: layout, sections: true, to: &builder)
        for box in layout.boxes where !box.isSection { add(box, look: TreemapDrawingParts.leafLook(box), part: .leaf, to: &builder, workspace: workspace) }
        addTexts(of: layout, sections: false, to: &builder)
    }

    /// The names, then the values, of the sections or of the leaves.
    private static func addTexts(of layout: TreemapLayout, sections: Bool, to builder: inout DiagramSceneBuilder) {
        for box in layout.boxes where box.isSection == sections && box.name != nil {
            if let name = TreemapDrawingParts.texts(of: box, seriesColors: layout.seriesColors).name { builder.text(name, part: .label) }
        }
        for box in layout.boxes where box.isSection == sections && box.value != nil {
            if let value = TreemapDrawingParts.texts(of: box, seriesColors: layout.seriesColors).value { builder.text(value, part: .value) }
        }
    }

    private static func add(_ box: TreemapLayoutBox, look: TreemapDrawingParts.BoxLook, part: DiagramScenePart, to builder: inout DiagramSceneBuilder,
                            workspace: DiagramSceneWorkspace) {
        guard look.fill != nil || look.outline != nil else { return }
        let madeCount = workspace.madePathCount
        let radius = TreemapDrawingParts.cornerRadius(of: box)
        let path = workspace.roundedRectangle(box.frame, cornerWidth: radius, cornerHeight: radius)
        switch (look.fill, look.outline) {
        case (let fill?, let outline?): builder.fillAndStroke(path, fill: fill, stroke: outline, look.stroke, part: part)
        case (let fill?, nil): builder.fill(path, fill, part: part)
        case (nil, let outline?): builder.stroke(path, outline, look.stroke, part: part)
        case (nil, nil): break
        }
        workspace.givePathsBack(downTo: madeCount)
    }
}

extension DiagramSceneBuilder {
    fileprivate mutating func text(_ text: TreemapTextParts, part: DiagramScenePart) {
        self.text(text.block, text.paint, isBold: text.isBold, isItalic: text.isItalic, part: part)
    }
}
