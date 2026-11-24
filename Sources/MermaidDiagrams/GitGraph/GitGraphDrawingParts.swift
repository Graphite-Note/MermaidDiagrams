/**
 * File: GitGraphDrawingParts.swift
 * --------------------------------
 * Layer: Core
 * Description: A laid-out Git graph's geometry grouped by how it is painted, with the paints of its branch names, as
 *              Core Graphics paths recorded by the drawing its scene shares (GitGraphScenePaths).
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.3
 * Date: 24/11/2026
 */

import CoreGraphics

/// A laid-out Git graph's geometry grouped by how it is painted, so that drawing it in any colors is a few fills and
/// strokes per color, by Core Graphics (`GitGraphRenderer`) or by a view's own shapes. Back to front, as Pele draws: the
/// lanes and their names, the lines between lanes, then along them, the commits' symbols and their marks, the ids on
/// their patches, the tags, the title.
public struct GitGraphDrawingParts {
    /// What is painted in one series color: the lanes whose index leaves `seriesIndex` when divided by
    /// `seriesColorCount`, and the commits and lines that take their color.
    public struct ColorGroup {
        public let seriesIndex: Int
        /// The lanes' lines, stroked `laneLineWidth` wide, dashed with `laneDashLengths`.
        public let laneLines: CGPath
        /// The boxes behind branch names, filled.
        public let nameBoxes: CGPath
        /// The lines between lanes, stroked `connectorLineWidth` wide with round caps.
        public let curves: CGPath
        /// The lines to cherry-picks, stroked like `curves` and dashed with `cherryPickDashLengths`.
        public let cherryPickCurves: CGPath
        /// The lines along lanes, stroked like `curves`, over them.
        public let straightLines: CGPath
        /// Merges' rings: filled in the background color, then stroked `ringLineWidth` wide in the group's color.
        public let rings: CGPath
        /// Dots, squares and the small dots inside rings, filled, over the rings.
        public let symbols: CGPath
    }

    public let colorGroups: [ColorGroup]
    /// The crosses on reverse commits, stroked `crossLineWidth` wide in the background color with round caps.
    public let reverseCrosses: CGPath
    /// The cherries' stems, stroked `cherryStemLineWidth` wide in the background color with round joins.
    public let cherryStems: CGPath
    /// The cherries' two fruits, filled in the background color.
    public let cherryFruits: CGPath
    /// The patches behind ids, turned with them, filled in the background color.
    public let labelPatches: CGPath
    /// The ids, each drawn turned by its angle about its center, in the muted color.
    public let labels: [GitGraphLayoutCommitLabel]
    /// The tags' boxes, filled in the surface color and stroked `tagLineWidth` wide in the border color with round joins.
    public let tagBoxes: CGPath
    /// The tags' holes, filled in the border color.
    public let tagHoles: CGPath
    /// The tags' text, in the foreground color.
    public let tagTexts: [DiagramTextBlock]
    /// The branch names, in the background color on their boxes.
    public let names: [DiagramTextBlock]
    /// The paint of each of `names`: the background color, or Pele's ink on its lane's color where the graph's theme
    /// variables set that color (`DiagramSeriesColors.inks`).
    public let namePaints: [DiagramPaint]
    /// The title, drawn bold, or nil.
    public let title: DiagramTextBlock?

    public static let laneLineWidth: CGFloat = 1
    public static let laneDashLengths: [CGFloat] = [2, 4]
    public static let connectorLineWidth: CGFloat = 2
    public static let cherryPickDashLengths: [CGFloat] = [4, 3]
    public static let ringLineWidth: CGFloat = 2
    public static let crossLineWidth: CGFloat = 1.5
    public static let cherryStemLineWidth: CGFloat = 1
    public static let tagLineWidth: CGFloat = 1
    /// Pele's eight `--pele-series-*` colors, which lanes take in turn.
    public static let seriesColorCount = DiagramPalette.peleSeries.count
    /// The corner radius of a name's box: Pele's `--pele-radius`.
    static let nameBoxCornerRadius: CGFloat = 4
    static let labelPatchCornerRadius: CGFloat = 3
    static let tagHoleRadius: CGFloat = 1.5

    public init(layout: GitGraphLayout) {
        let paths = GitGraphScenePaths(layout: layout, making: DiagramCoreGraphicsPaths())
        colorGroups = paths.groups.enumerated().compactMap { seriesIndex, group in
            group.isPainted ? ColorGroup(seriesIndex: seriesIndex, laneLines: group.laneLines.path, nameBoxes: group.nameBoxes.path, curves: group.curves.path,
                                         cherryPickCurves: group.cherryPickCurves.path, straightLines: group.straightLines.path, rings: group.rings.path,
                                         symbols: group.symbols.path) : nil
        }
        reverseCrosses = paths.reverseCrosses.path
        cherryStems = paths.cherryStems.path
        cherryFruits = paths.cherryFruits.path
        labelPatches = paths.labelPatches.path
        labels = layout.commits.compactMap(\.label)
        tagBoxes = paths.tagBoxes.path
        tagHoles = paths.tagHoles.path
        tagTexts = layout.commits.flatMap { commit in commit.tags.map(\.text) }
        names = layout.lanes.compactMap(\.name)
        namePaints = Self.namePaints(layout)
        title = layout.title
    }

    /// The paint of each lane's name: Pele's ink on the lane's color where the theme variables set it, else the background.
    private static func namePaints(_ layout: GitGraphLayout) -> [DiagramPaint] {
        layout.lanes.enumerated().compactMap { laneIndex, lane in
            lane.name.map { _ in layout.seriesColors.ink(ofSeries: laneIndex).map(DiagramPaint.color) ?? .background }
        }
    }
}
