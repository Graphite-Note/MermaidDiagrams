/**
 * File: WardleyMapScene.swift
 * ---------------------------
 * Layer: Core
 * Description: A laid-out Wardley map's scene, as Pele paints it: the title, the frame, the stages' and axes' texts, the
 *              pipelines, the links, the evolutions, the nodes with their labels, the annotations, notes and forces.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 25/11/2026
 */

import CoreGraphics
import Foundation

extension DiagramScene {
    /// The Wardley map's painting, back to front as Pele writes it: the title; the stages' lines dashed in the border
    /// color, the grid, the axes in the line color; the stages' names in the muted color and the axes' titles in bold;
    /// the pipelines' boxes on the surface color; the links in the line color, their labels muted; the evolutions in the
    /// accent color; each node's shape, inertia bar and label; the annotations; the notes in bold; the forces. Every shape
    /// is recorded into a lane of the thread's scene workspace, given back once the builder has copied it.
    public init(layout: WardleyMapLayout) {
        self.init(layout: layout, limits: .standard)
    }

    /// The same painting recorded under `limits`: a scene one of whose lanes goes past their element limit says so
    /// (`exceededPathElementLimit`), and the preparation refuses it.
    public init(layout: WardleyMapLayout, limits: MermaidDiagramLimits) {
        self = DiagramSceneWorkspace.withRecording(limits: limits) { workspace in
            var builder = DiagramSceneBuilder(workspace: workspace)
            let paths = WardleyMapScenePaths(workspace: workspace)
            builder.title(layout.title)
            paths.addFrame(of: layout, to: &builder)
            paths.addPipelinesLinksAndTrends(of: layout, to: &builder)
            for node in layout.nodes { paths.add(node, to: &builder) }
            paths.addAnnotations(of: layout, to: &builder)
            for note in layout.notes { builder.texts(note, .foreground, isBold: true, part: .wardleyNote) }
            for force in layout.forces {
                let outline = paths.line(force.outline)
                outline.closeSubpath()
                let part: DiagramScenePart = force.isAccelerator ? .wardleyAccelerator : .wardleyDeaccelerator
                builder.fillAndStroke(outline, fill: .surface, stroke: .line, DiagramStroke(lineWidth: 1), part: part)
                paths.giveBack()
                builder.text(force.name, .foreground, isBold: true, part: part)
            }
            return builder.scene(size: layout.size, font: layout.font)
        }
    }
}

/// The shapes of a Wardley map's scene, each recorded into a lane of the scene's workspace made for a moment: a drawing
/// adds it to the builder, which copies it, and gives it back (`giveBack()`).
struct WardleyMapScenePaths {
    static let radius: CGFloat = 6
    static let squareSide: CGFloat = 10
    /// Pele's `--pele-radius`.
    static let cornerRadius: CGFloat = 4

    let workspace: DiagramSceneWorkspace
    /// How many lanes were out when the scene began, which `giveBack()` takes the scene's own back down to.
    private let madeCount: Int

    init(workspace: DiagramSceneWorkspace) {
        self.workspace = workspace
        madeCount = workspace.madePathCount
    }

    /// Takes back every lane made since the scene began.
    func giveBack() {
        workspace.givePathsBack(downTo: madeCount)
    }

    func rounded(_ frame: CGRect) -> DiagramPathLane {
        workspace.roundedRectangle(frame, cornerWidth: Self.cornerRadius, cornerHeight: Self.cornerRadius)
    }

    func circle(_ center: CGPoint, radius: CGFloat) -> DiagramPathLane {
        workspace.ellipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
    }

    /// A line in a lane of its own, which a drawing may add to: a force closes its outline.
    func line(_ path: DiagramPath) -> DiagramPathLane {
        let lane = workspace.makeLane()
        DiagramEdgeDrawing.record(path, into: lane)
        return lane
    }

    /// Lines joined into one lane, each recorded apart and added as Core Graphics adds one path to another.
    private func joined(_ paths: [DiagramPath]) -> DiagramPathLane {
        let lane = workspace.makeLane()
        for path in paths {
            let count = workspace.madePathCount
            lane.addPath(line(path))
            workspace.givePathsBack(downTo: count)
        }
        return lane
    }

    func arrows(_ marks: [DiagramEdgeMark]) -> DiagramPathLane {
        let filled = workspace.makeLane()
        let stroked = workspace.makeLane()
        for mark in marks { DiagramEdgeDrawing.addMark(mark, filled: filled, stroked: stroked) }
        return filled
    }

    /// The stages' lines, the grid, the axes, the stages' names and the axes' titles.
    func addFrame(of layout: WardleyMapLayout, to builder: inout DiagramSceneBuilder) {
        builder.stroke(joined(layout.stageLines), .border, DiagramStroke(lineWidth: 1, dashLengths: [4, 4]), part: .wardleyStage)
        builder.stroke(joined(layout.gridLines), .border, DiagramStroke(lineWidth: 1, dashLengths: [2, 6]), part: .wardleyGrid)
        builder.stroke(line(layout.axes), .line, DiagramStroke(lineWidth: 1), part: .wardleyAxis)
        giveBack()
        builder.texts(layout.stageLabels, .muted, part: .wardleyStageLabel)
        builder.text(layout.evolutionTitle, .foreground, isBold: true, part: .wardleyAxisLabel)
        builder.text(layout.visibilityTitle, .foreground, isBold: true, rotation: -.pi / 2, part: .wardleyAxisLabel)
    }

    /// The pipelines' boxes and lines, the links with their arrows and labels, and the evolutions.
    func addPipelinesLinksAndTrends(of layout: WardleyMapLayout, to builder: inout DiagramSceneBuilder) {
        for pipeline in layout.pipelines {
            builder.fillAndStroke(rounded(pipeline.frame), fill: .surface, stroke: .border, DiagramStroke(lineWidth: 1), part: .wardleyPipeline)
            if let pipelineLine = pipeline.line {
                builder.stroke(line(pipelineLine), .line, DiagramStroke(lineWidth: 1, dashLengths: [4, 4]), part: .wardleyPipeline)
            }
            giveBack()
        }
        for link in layout.links {
            builder.stroke(line(link.line), .line, DiagramStroke(lineWidth: 1, dashLengths: link.isDashed ? [6, 6] : []), part: .edge)
            builder.fill(arrows(link.arrows), .line, part: .marker)
            giveBack()
            builder.text(link.label, .muted, part: .edgeLabel)
        }
        for trend in layout.trends {
            if let trendLine = trend.line { builder.stroke(line(trendLine), .accent, DiagramStroke(lineWidth: 1, dashLengths: [4, 4]), part: .wardleyTrend) }
            builder.fill(arrows(trend.arrow.map { arrow in [arrow] } ?? []), .accent, part: .marker)
            builder.fillAndStroke(circle(trend.target, radius: 6), fill: .background, stroke: .accent, DiagramStroke(lineWidth: 1), part: .wardleyTrend)
            giveBack()
        }
    }

    /// A node: its sourcing ring (muted, the second surface, the surface or the background), a market's triangle of dots,
    /// a parent's square or a component's circle, its inertia bar, and its label.
    func add(_ node: WardleyMapLayoutNode, to builder: inout DiagramSceneBuilder) {
        defer { giveBack() }
        let center = node.center
        if let sourcing = node.sourcing {
            let fill: DiagramPaint = switch sourcing {
            case .outsource: .muted
            case .buy: .alternateSurface
            case .build: .surface
            case .market: .background
            }
            builder.fillAndStroke(circle(center, radius: 2 * Self.radius), fill: fill, stroke: .line, DiagramStroke(lineWidth: 1), part: .node)
        }
        if node.sourcing == .market { addMarket(at: center, to: &builder) }
        switch node.shape {
        case .square:
            let side = Self.squareSide
            let square = workspace.rectangle(CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side))
            builder.fillAndStroke(square, fill: .background, stroke: .line, DiagramStroke(lineWidth: 1), part: .node)
        case .circle: builder.fillAndStroke(circle(center, radius: Self.radius), fill: .background, stroke: .line, DiagramStroke(lineWidth: 1), part: .node)
        case .none: break
        }
        if let inertia = node.inertia { builder.fill(workspace.rectangle(inertia), .line, part: .wardleyInertia) }
        builder.texts(node.label, .foreground, isBold: node.isAnchor, part: .label)
    }

    /// A market's triangle 1.2 radii from its center, outlined, with a dot of 0.7 radii at each corner.
    private func addMarket(at center: CGPoint, to builder: inout DiagramSceneBuilder) {
        let reach = 1.2 * Self.radius
        let across = reach * cos(CGFloat.pi / 6)
        let bottom = center.y + reach * sin(CGFloat.pi / 6)
        let corners = [CGPoint(x: center.x, y: center.y - reach), CGPoint(x: center.x - across, y: bottom), CGPoint(x: center.x + across, y: bottom)]
        let triangle = workspace.makeLane()
        triangle.addLines(between: corners)
        triangle.closeSubpath()
        builder.stroke(triangle, .line, DiagramStroke(lineWidth: 1), part: .node)
        for corner in corners {
            builder.fillAndStroke(circle(corner, radius: 0.7 * Self.radius), fill: .background, stroke: .line, DiagramStroke(lineWidth: 1), part: .node)
        }
    }

    /// Each annotation's circles with their bold numbers, then the list's box and its rows.
    func addAnnotations(of layout: WardleyMapLayout, to builder: inout DiagramSceneBuilder) {
        defer { giveBack() }
        for annotation in layout.annotations {
            for (annotationCircle, number) in zip(annotation.circles, annotation.numbers) {
                builder.fillAndStroke(circle(annotationCircle.center, radius: annotationCircle.radius), fill: .background, stroke: .line,
                                      DiagramStroke(lineWidth: 1), part: .wardleyAnnotation)
                giveBack()
                builder.text(number, .foreground, isBold: true, part: .wardleyAnnotation)
            }
        }
        guard let list = layout.annotationList else { return }
        builder.fillAndStroke(rounded(list.frame), fill: .background, stroke: .border, DiagramStroke(lineWidth: 1), part: .wardleyAnnotations)
        builder.texts(list.rows, .foreground, part: .wardleyAnnotations)
    }
}
