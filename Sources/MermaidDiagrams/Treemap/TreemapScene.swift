/**
 * File: TreemapScene.swift
 * ------------------------
 * Layer: Core
 * Description: A laid-out treemap's scene: its drawing parts back to front in the colors' roles, as Pele paints them.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 23/11/2026
 */

import CoreGraphics

extension DiagramScene {
    /// The treemap's painting: the title, the sections as tints of their series colors with their names and totals, then the
    /// leaves in their series colors with their names and values.
    public init(layout: TreemapLayout) {
        var builder = DiagramSceneBuilder()
        TreemapDrawingParts(layout: layout).addScene(to: &builder)
        self = builder.scene(size: layout.size, font: layout.font, seriesColors: layout.seriesColors)
    }
}

extension TreemapDrawingParts {
    func addScene(to builder: inout DiagramSceneBuilder) {
        builder.title(title)
        for box in sectionBoxes { builder.add(box, part: .section) }
        for name in sectionNames { builder.text(name, part: .label) }
        for value in sectionValues { builder.text(value, part: .value) }
        for box in leafBoxes { builder.add(box, part: .leaf) }
        for name in leafNames { builder.text(name, part: .label) }
        for value in leafValues { builder.text(value, part: .value) }
    }
}

extension DiagramSceneBuilder {
    /// A text in its paint, weight and slant.
    fileprivate mutating func text(_ text: TreemapTextParts, part: DiagramScenePart) {
        self.text(text.block, text.paint, isBold: text.isBold, isItalic: text.isItalic, part: part)
    }

    /// A box filled, outlined, both or neither, as its parts say.
    fileprivate mutating func add(_ box: TreemapBoxParts, part: DiagramScenePart) {
        switch (box.fill, box.outline) {
        case (let fill?, let outline?): fillAndStroke(box.pathScenePath, fill: fill, stroke: outline, box.stroke, part: part)
        case (let fill?, nil): self.fill(box.pathScenePath, fill, part: part)
        case (nil, let outline?): stroke(box.pathScenePath, outline, box.stroke, part: part)
        case (nil, nil): break
        }
    }
}
