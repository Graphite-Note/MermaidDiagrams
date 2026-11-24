/**
 * File: FlowchartClusterDrawingParts.swift
 * ----------------------------------------
 * Layer: Core
 * Description: The boxes of a flowchart's groups grouped by how they are painted, as Core Graphics paths for a host and
 *              as the same paths in any kind a drawing records (`FlowchartClusterPaths`) for the scene.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

import CoreGraphics

/// The boxes of a flowchart's groups grouped by how they are painted, Pele's way: each box filled with the alternate
/// surface at half its opacity, one depth after another so that a box inside another is darker, the outlines in the
/// border color, and the titles in the muted color. A title an edge runs through is painted over the edges instead,
/// on a patch of its box's color: the background and, for each box it is inside and its own, the alternate surface at
/// half its opacity again.
public struct FlowchartClusterDrawingParts {
    /// The boxes at each depth, the top level first, each filled with the alternate surface at `fillOpacity`.
    public let fillsByDepth: [CGPath]
    /// The boxes' outlines, stroked one point wide in the border color.
    public let outlines: CGPath
    /// The titles no edge runs through, painted with the boxes.
    public let titles: [DiagramTextBlock]
    /// The patches behind the titles edges run through, by the depth of their box: painted after the edges, filled with
    /// the background and then `depth + 1` times with the alternate surface at `fillOpacity`.
    public let crossedTitlePatchesByDepth: [CGPath]
    /// The titles edges run through, painted on their patches.
    public let crossedTitles: [DiagramTextBlock]

    /// How much of the alternate surface a box shows over what is behind it: Pele's.
    public static let fillOpacity: CGFloat = 0.5
    /// How far the patch behind a crossed title reaches beyond its text, as Pele's outline around the letters does.
    static let crossedTitlePatchMargin: CGFloat = 2.5

    init(clusters: [FlowchartLayoutCluster]) {
        let paths = FlowchartClusterPaths(clusters: clusters, making: DiagramCoreGraphicsPaths())
        fillsByDepth = paths.fillsByDepth.map(\.path)
        outlines = paths.outlines.path
        titles = paths.titles
        crossedTitlePatchesByDepth = paths.crossedTitlePatchesByDepth.map(\.path)
        crossedTitles = paths.crossedTitles
    }
}

/// The paths of `FlowchartClusterDrawingParts` in any kind a drawing records: Core Graphics paths or lanes. Each box is
/// made for a moment, added where it is painted and given back.
struct FlowchartClusterPaths<Path: DiagramPathRecording> {
    let fillsByDepth: [Path]
    let outlines: Path
    let titles: [DiagramTextBlock]
    let crossedTitlePatchesByDepth: [Path]
    let crossedTitles: [DiagramTextBlock]

    init<Maker: DiagramPathMaking>(clusters: [FlowchartLayoutCluster], making maker: Maker) where Maker.Path == Path {
        var depthCount = 0
        for cluster in clusters { depthCount = max(depthCount, cluster.depth + 1) }
        let fills = (0..<depthCount).map { _ in maker.makePath() }
        let patches = (0..<depthCount).map { _ in maker.makePath() }
        let outlines = maker.makePath()
        var titles: [DiagramTextBlock] = []
        var crossedTitles: [DiagramTextBlock] = []
        let corner = FlowchartShapeDrawing.rectangleCornerRadius
        let patchCorner = FlowchartDrawingParts.edgeTextPatchCornerRadius
        for cluster in clusters {
            let madeCount = maker.madePathCount
            defer { maker.givePathsBack(downTo: madeCount) }
            let box = maker.roundedRectangle(cluster.frame, cornerWidth: corner, cornerHeight: corner)
            fills[cluster.depth].addPath(box, alsoTo: outlines)
            guard let title = cluster.title else { continue }
            guard cluster.isTitleCrossed else {
                titles.append(title)
                continue
            }
            crossedTitles.append(title)
            let margin = FlowchartClusterDrawingParts.crossedTitlePatchMargin
            patches[cluster.depth].addPath(maker.roundedRectangle(title.frame.insetBy(dx: -margin, dy: 0), cornerWidth: patchCorner, cornerHeight: patchCorner))
        }
        fillsByDepth = fills
        self.outlines = outlines
        self.titles = titles
        crossedTitlePatchesByDepth = patches
        self.crossedTitles = crossedTitles
    }
}
