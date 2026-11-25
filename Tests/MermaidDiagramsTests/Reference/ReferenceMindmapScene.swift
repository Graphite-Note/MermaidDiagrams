/**
 * File: ReferenceMindmapScene.swift
 * ---------------------------------
 * Layer: Tests
 * Description: 0.7.0's mindmap scene, frozen as main 2a0cc65 made it from the drawing parts' Core Graphics paths, which
 *              the scene recorded into lanes is compared with.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
import Foundation
@testable import MermaidDiagrams

enum ReferenceMindmapScene {
    /// The mindmap's painting: each branch's links and then its nodes in its series color, the root in the surface and
    /// border colors, the text, the title.
    static func scene(layout: MindmapLayout) -> DiagramScene {
        var builder = DiagramSceneBuilder()
        ReferenceMindmapDrawingParts(layout: layout).addScene(to: &builder)
        return builder.scene(size: layout.size, font: layout.font, seriesColors: layout.seriesColors)
    }
}

extension ReferenceMindmapDrawingParts {
    func addScene(to builder: inout DiagramSceneBuilder) {
        let outline = DiagramStroke(lineWidth: Self.outlineLineWidth)
        for branch in branches {
            let paint = DiagramPaint.series(branch.branchIndex)
            builder.stroke(branch.links, paint, DiagramStroke(lineWidth: Self.linkLineWidth), part: .edge)
            builder.fillAndStroke(branch.nodeOutlines, fill: paint.atOpacity(Self.nodeFillOpacity), stroke: paint, outline, part: .node)
        }
        builder.fillAndStroke(rootOutline, fill: .surface, stroke: .border, outline, part: .node)
        builder.texts(nodeTexts, .foreground, part: .label)
        builder.title(title)
    }
}


/// A laid-out mindmap's geometry grouped by how it is painted, so that drawing it in any colors is a few fills and
/// strokes per branch, by Core Graphics (`MindmapRenderer`) or by a view's own shapes. Back to front, as Pele draws:
/// each branch's links and then its nodes, the root over the links that leave it, the text, the title.
struct ReferenceMindmapDrawingParts {
    /// The links and node outlines of the branches that share one number (`MindmapNode.branchIndex`), painted in
    /// that number's series color.
    struct Branch {
        let branchIndex: Int
        /// The links into the branch's nodes, stroked `linkLineWidth` wide in the branch's color.
        let links: CGPath
        /// The outlines of the branch's nodes, filled with the branch's color at `nodeFillOpacity` and stroked
        /// `outlineLineWidth` wide in it. A node drawn as text alone has none.
        let nodeOutlines: CGPath
    }

    /// The branches with something to paint, by number.
    let branches: [Branch]
    /// The root's outline, filled in the surface color and stroked in the border color.
    let rootOutline: CGPath
    /// Every node's text, in the foreground color.
    let nodeTexts: [DiagramTextBlock]
    /// The title, drawn bold, or nil.
    let title: DiagramTextBlock?

    static let linkLineWidth: CGFloat = 1.5
    static let outlineLineWidth: CGFloat = 1
    /// How much of the branch color a node's fill takes, over the background: Pele's tint.
    static let nodeFillOpacity: CGFloat = 0.22

    init(layout: MindmapLayout) {
        let links = (0..<MindmapNode.branchCount).map { _ in CGMutablePath() }
        let outlines = (0..<MindmapNode.branchCount).map { _ in CGMutablePath() }
        let rootOutline = CGMutablePath()
        for edge in layout.edges {
            links[edge.branchIndex % MindmapNode.branchCount].addPath(DiagramEdgeDrawing.path(edge.path))
        }
        for node in layout.nodes {
            guard let outline = ReferenceMindmapShapeDrawing.outline(of: node.outline, in: node.frame) else { continue }
            if let branchIndex = node.branchIndex {
                outlines[branchIndex % MindmapNode.branchCount].addPath(outline)
            } else {
                rootOutline.addPath(outline)
            }
        }
        branches = (0..<MindmapNode.branchCount).compactMap { branchIndex in
            links[branchIndex].isEmpty && outlines[branchIndex].isEmpty ? nil
                : Branch(branchIndex: branchIndex, links: links[branchIndex], nodeOutlines: outlines[branchIndex])
        }
        self.rootOutline = rootOutline
        nodeTexts = layout.nodes.flatMap { node in node.isTextLeftAligned ? node.text.leftAlignedLines() : [node.text] }
        title = layout.title
    }
}


/// The outline of each mindmap node, Pele's, as a Core Graphics path in a frame: the flowchart's shapes, a pill,
/// a cloud of four arcs over a flat base, and a bang of fourteen spikes.
enum ReferenceMindmapShapeDrawing {
    /// How many spikes a bang has.
    static let bangSpikeCount = 14
    /// How far in a bang's notches are, as a fraction of its radii.
    static let bangNotchRatio: CGFloat = 0.82

    /// The outline to fill and stroke, or nil for a node drawn as its text alone.
    static func outline(of outline: MindmapNodeOutline, in frame: CGRect) -> CGPath? {
        if let shape = outline.flowchartShape { return FlowchartShapeDrawing.outline(of: shape, in: frame) }
        switch outline {
        case .pill:
            return CGPath(roundedRect: frame, cornerWidth: min(frame.width, frame.height) / 2, cornerHeight: frame.height / 2, transform: nil)
        case .cloud: return cloud(in: frame)
        case .bang: return bang(in: frame)
        case .text, .stadium, .rectangle, .roundedRectangle, .circle, .hexagon: return nil
        }
    }

    /// Pele's cloud: from the bottom left, a round lobe up the left side, two wide lobes over the top and a round lobe
    /// down the right side, then straight back along the bottom.
    private static func cloud(in frame: CGRect) -> CGPath {
        let halfWidth = frame.width / 2
        let halfHeight = frame.height / 2
        let lobeRadius = halfHeight * 0.55
        func point(_ across: CGFloat, _ down: CGFloat) -> CGPoint { CGPoint(x: frame.midX + across, y: frame.midY + down) }
        let corners = [point(-halfWidth + lobeRadius, halfHeight), point(-halfWidth + lobeRadius * 0.6, -halfHeight * 0.1),
                       point(-halfWidth * 0.1, -halfHeight * 0.72), point(halfWidth * 0.62, -halfHeight * 0.42), point(halfWidth - lobeRadius, halfHeight)]
        let radii = [CGSize(width: lobeRadius, height: lobeRadius), CGSize(width: halfWidth * 0.42, height: halfHeight * 0.7),
                     CGSize(width: halfWidth * 0.4, height: halfHeight * 0.62), CGSize(width: lobeRadius * 1.05, height: lobeRadius * 1.05)]
        let path = CGMutablePath()
        path.move(to: corners[0])
        for (index, radius) in radii.enumerated() {
            DiagramEllipticalArc.addArc(to: path, from: corners[index], to: corners[index + 1], radii: radius)
        }
        path.closeSubpath()
        return path
    }

    /// Pele's bang: points around the frame's ellipse, alternately on it and `bangNotchRatio` of the way in, from the top.
    private static func bang(in frame: CGRect) -> CGPath {
        let pointCount = 2 * bangSpikeCount
        let points = (0..<pointCount).map { index in
            let angle = CGFloat.pi * CGFloat(index) / CGFloat(bangSpikeCount) - CGFloat.pi / 2
            let reach: CGFloat = index.isMultiple(of: 2) ? 1 : bangNotchRatio
            return CGPoint(x: frame.midX + cos(angle) * frame.width / 2 * reach, y: frame.midY + sin(angle) * frame.height / 2 * reach)
        }
        let path = CGMutablePath()
        path.addLines(between: points)
        path.closeSubpath()
        return path
    }
}
