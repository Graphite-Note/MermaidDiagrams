/**
 * File: PacketDiagramScene.swift
 * ------------------------------
 * Layer: Core
 * Description: A laid-out packet diagram's scene: the fields' boxes recorded into a lane of the thread's scene workspace
 *              and added back to front in the colors' roles, as Pele paints them, without a Core Graphics path.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 25/11/2026
 */

import CoreGraphics

extension DiagramScene {
    /// The packet diagram's painting: the fields' boxes in the surface and border colors, their labels, the bit numbers
    /// in the muted color, the title.
    public init(layout: PacketDiagramLayout) {
        self.init(layout: layout, limits: .standard)
    }

    /// The same painting recorded under `limits`: a scene one of whose lanes goes past their element limit says so
    /// (`exceededPathElementLimit`), and the preparation refuses it.
    public init(layout: PacketDiagramLayout, limits: MermaidDiagramLimits) {
        self = DiagramSceneWorkspace.withRecording(limits: limits) { workspace in
            var builder = DiagramSceneBuilder(workspace: workspace)
            let boxes = workspace.makeLane()
            for field in layout.fields {
                let radius = min(PacketDiagramLayoutEngine.cornerRadius, field.frame.width / 2, field.frame.height / 2)
                boxes.addRoundedRect(in: field.frame, cornerWidth: radius, cornerHeight: radius)
            }
            builder.fillAndStroke(boxes, fill: .surface, stroke: .border, DiagramStroke(lineWidth: PacketDiagramDrawingParts.lineWidth), part: .node)
            for field in layout.fields { builder.text(field.label, .foreground, part: .label) }
            builder.texts(layout.bitNumbers, .muted, part: .bitNumber)
            builder.title(layout.title)
            return builder.scene(size: layout.size, font: layout.font)
        }
    }
}
