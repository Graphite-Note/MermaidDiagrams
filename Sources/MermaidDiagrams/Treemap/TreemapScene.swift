/**
 * File: TreemapScene.swift
 * ------------------------
 * Layer: Core
 * Description: A laid-out treemap's scene: its drawing parts back to front in the colors' roles, as Pele paints them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

extension DiagramScene {
    /// The treemap's painting: the title, the sections as tints of their series colors with their names and totals, then the
    /// leaves in their series colors with their names and values.
    public init(layout: TreemapLayout) {
        var builder = DiagramSceneBuilder()
        TreemapDrawingParts(layout: layout).addScene(to: &builder)
        self = builder.scene(size: layout.size, font: layout.font)
    }
}

extension TreemapDrawingParts {
    func addScene(to builder: inout DiagramSceneBuilder) {
        builder.title(title)
        for box in sectionBoxes { builder.add(box, part: .section) }
        for name in sectionNames { builder.text(name.block, name.paint, isBold: true, part: .label) }
        for value in sectionValues { builder.text(value.block, value.paint, part: .value) }
        for box in leafBoxes { builder.add(box, part: .leaf) }
        for name in leafNames { builder.text(name.block, name.paint, part: .label) }
        for value in leafValues { builder.text(value.block, value.paint, part: .value) }
    }
}

extension DiagramSceneBuilder {
    /// A box filled, outlined, both or neither, as its parts say.
    fileprivate mutating func add(_ box: TreemapBoxParts, part: DiagramScenePart) {
        switch (box.fill, box.outline) {
        case (let fill?, let outline?): fillAndStroke(box.path, fill: fill, stroke: outline, box.stroke, part: part)
        case (let fill?, nil): self.fill(box.path, fill, part: part)
        case (nil, let outline?): stroke(box.path, outline, box.stroke, part: part)
        case (nil, nil): break
        }
    }
}
