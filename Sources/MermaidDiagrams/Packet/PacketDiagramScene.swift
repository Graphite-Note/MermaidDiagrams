/**
 * File: PacketDiagramScene.swift
 * ------------------------------
 * Layer: Core
 * Description: A laid-out packet diagram's scene: its drawing parts back to front in the colors' roles, as Pele paints them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

extension DiagramScene {
    /// The packet diagram's painting: the fields' boxes in the surface and border colors, their labels, the bit numbers
    /// in the muted color, the title.
    public init(layout: PacketDiagramLayout) {
        var builder = DiagramSceneBuilder()
        PacketDiagramDrawingParts(layout: layout).addScene(to: &builder)
        self = builder.scene(size: layout.size, font: layout.font)
    }
}

extension PacketDiagramDrawingParts {
    func addScene(to builder: inout DiagramSceneBuilder) {
        builder.fillAndStroke(fieldBoxes, fill: .surface, stroke: .border, DiagramStroke(lineWidth: Self.lineWidth), part: .node)
        builder.texts(fieldLabels, .foreground, part: .label)
        builder.texts(bitNumbers, .muted, part: .bitNumber)
        builder.title(title)
    }
}
