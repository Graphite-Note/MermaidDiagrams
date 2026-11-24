/**
 * File: IshikawaScene.swift
 * -------------------------
 * Layer: Core
 * Description: A laid-out Ishikawa diagram's scene, back to front in Pele's colors, across or down, and its renderer,
 *              which paints it.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

import CoreGraphics

extension DiagramScene {
    /// The diagram's painting, in Pele's order. Across: the title, the spine and its arrow in the line color, then each
    /// category's bones and arrow, its box in the surface color outlined in the border color, its name and its causes,
    /// a cause's causes muted, and last the head with its bold name. Down: the title, the connectors in the border color,
    /// then each entry's box (the effect's and the categories') and its name. Every shape is recorded into a lane of the
    /// thread's scene workspace, made for a moment and given back once the builder has copied it.
    public init(layout: IshikawaLayout) {
        self = DiagramSceneWorkspace.withRecording { workspace in
            var builder = DiagramSceneBuilder(workspace: workspace)
            builder.title(layout.title)
            IshikawaScene.addFishbone(of: layout, to: &builder, workspace: workspace)
            IshikawaScene.addOutline(of: layout, to: &builder, workspace: workspace)
            return builder.scene(size: layout.size, font: layout.font)
        }
    }
}

enum IshikawaScene {
    static let lineWidth: CGFloat = 1
    /// Pele's corner radius (`--pele-radius`), which a category's box takes.
    static let boxCornerRadius: CGFloat = 4

    /// The spine and its arrow, each category's bones, arrow, box and texts, and the head.
    static func addFishbone(of layout: IshikawaLayout, to builder: inout DiagramSceneBuilder, workspace: DiagramSceneWorkspace) {
        let line = DiagramStroke(lineWidth: lineWidth)
        let madeCount = workspace.madePathCount
        defer { workspace.givePathsBack(downTo: madeCount) }
        if let spine = layout.spine { builder.stroke(recorded(spine, workspace: workspace), .line, line, part: .ishikawaSpine) }
        if let arrow = layout.spineArrow { builder.fill(arrowLane(arrow, workspace: workspace), .line, part: .marker) }
        for category in layout.categories {
            workspace.givePathsBack(downTo: madeCount)
            builder.stroke(joined(category.bones, workspace: workspace), .line, line, part: .ishikawaBones)
            builder.fill(arrowLane(category.arrow, workspace: workspace), .line, part: .marker)
            let box = category.box
            let corners = (width: min(boxCornerRadius, box.width / 2), height: min(boxCornerRadius, box.height / 2))
            builder.fillAndStroke(workspace.roundedRectangle(box, cornerWidth: corners.width, cornerHeight: corners.height), fill: .surface,
                                  stroke: .border, line, part: .node)
            builder.text(category.label, .foreground, part: .label)
            for cause in category.causes { builder.text(cause.text, cause.isMuted ? .muted : .foreground, part: .label) }
        }
        if let head = layout.head {
            builder.fillAndStroke(headOutline(head.frame, workspace: workspace), fill: .surface, stroke: .border,
                                  DiagramStroke(lineWidth: lineWidth, lineJoin: .round), part: .node)
            builder.text(head.label, .foreground, isBold: true, part: .label)
        }
    }

    /// The outline's connectors, then each entry's box and text.
    static func addOutline(of layout: IshikawaLayout, to builder: inout DiagramSceneBuilder, workspace: DiagramSceneWorkspace) {
        let line = DiagramStroke(lineWidth: lineWidth)
        let madeCount = workspace.madePathCount
        defer { workspace.givePathsBack(downTo: madeCount) }
        builder.stroke(joined(layout.outlineConnectors, workspace: workspace), .border, line, part: .edge)
        for entry in layout.outlineEntries {
            if entry.isFramed {
                workspace.givePathsBack(downTo: madeCount)
                let corner = min(entry.cornerRadius, entry.frame.width / 2, entry.frame.height / 2)
                builder.fillAndStroke(workspace.roundedRectangle(entry.frame, cornerWidth: corner, cornerHeight: corner), fill: .surface,
                                      stroke: .border, line, part: .node)
            }
            builder.text(entry.text, .foreground, isBold: entry.isFramed, part: .label)
        }
    }

    /// A line recorded into a lane of its own.
    private static func recorded(_ path: DiagramPath, workspace: DiagramSceneWorkspace) -> DiagramPathLane {
        let lane = workspace.makeLane()
        DiagramEdgeDrawing.record(path, into: lane)
        return lane
    }

    /// Lines joined into one lane, each recorded apart and added as Core Graphics adds one path to another.
    private static func joined(_ paths: [DiagramPath], workspace: DiagramSceneWorkspace) -> DiagramPathLane {
        let lane = workspace.makeLane()
        for path in paths {
            let madeCount = workspace.madePathCount
            lane.addPath(recorded(path, workspace: workspace))
            workspace.givePathsBack(downTo: madeCount)
        }
        return lane
    }

    private static func arrowLane(_ mark: DiagramEdgeMark, workspace: DiagramSceneWorkspace) -> DiagramPathLane {
        let filled = workspace.makeLane()
        DiagramEdgeDrawing.addMark(mark, filled: filled, stroked: workspace.makeLane())
        return filled
    }

    /// The head: flat on the spine's side, a half circle on the other.
    private static func headOutline(_ frame: CGRect, workspace: DiagramSceneWorkspace) -> DiagramPathLane {
        let radius = frame.height / 2
        let lane = workspace.makeLane()
        lane.move(to: CGPoint(x: frame.minX, y: frame.minY))
        lane.addLine(to: CGPoint(x: frame.maxX - radius, y: frame.minY))
        lane.addArc(center: CGPoint(x: frame.maxX - radius, y: frame.midY), radius: radius, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false)
        lane.addLine(to: CGPoint(x: frame.minX, y: frame.maxY))
        lane.closeSubpath()
        return lane
    }
}

/// Draws a laid-out Ishikawa diagram into a Core Graphics context whose origin is the layout's top left and whose y runs
/// down, by painting its scene with `DiagramSceneRenderer`.
public enum IshikawaRenderer {
    public static func draw(_ layout: IshikawaLayout, in context: CGContext, palette: DiagramPalette) {
        DiagramSceneRenderer.draw(DiagramScene(layout: layout), in: context, palette: palette)
    }
}
