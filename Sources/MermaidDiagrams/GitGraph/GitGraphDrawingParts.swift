/**
 * File: GitGraphDrawingParts.swift
 * --------------------------------
 * Layer: Core
 * Description: A laid-out Git graph's geometry grouped by how it is painted, with the paints of its branch names.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.3
 * Date: 23/11/2026
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
        public var laneLines: CGPath { laneLinesScenePath.coreGraphicsPath }
        let laneLinesScenePath: DiagramScenePath
        /// The boxes behind branch names, filled.
        public var nameBoxes: CGPath { nameBoxesScenePath.coreGraphicsPath }
        let nameBoxesScenePath: DiagramScenePath
        /// The lines between lanes, stroked `connectorLineWidth` wide with round caps.
        public var curves: CGPath { curvesScenePath.coreGraphicsPath }
        let curvesScenePath: DiagramScenePath
        /// The lines to cherry-picks, stroked like `curves` and dashed with `cherryPickDashLengths`.
        public var cherryPickCurves: CGPath { cherryPickCurvesScenePath.coreGraphicsPath }
        let cherryPickCurvesScenePath: DiagramScenePath
        /// The lines along lanes, stroked like `curves`, over them.
        public var straightLines: CGPath { straightLinesScenePath.coreGraphicsPath }
        let straightLinesScenePath: DiagramScenePath
        /// Merges' rings: filled in the background color, then stroked `ringLineWidth` wide in the group's color.
        public var rings: CGPath { ringsScenePath.coreGraphicsPath }
        let ringsScenePath: DiagramScenePath
        /// Dots, squares and the small dots inside rings, filled, over the rings.
        public var symbols: CGPath { symbolsScenePath.coreGraphicsPath }
        let symbolsScenePath: DiagramScenePath
    }

    public let colorGroups: [ColorGroup]
    /// The crosses on reverse commits, stroked `crossLineWidth` wide in the background color with round caps.
    public var reverseCrosses: CGPath { reverseCrossesScenePath.coreGraphicsPath }
    let reverseCrossesScenePath: DiagramScenePath
    /// The cherries' stems, stroked `cherryStemLineWidth` wide in the background color with round joins.
    public var cherryStems: CGPath { cherryStemsScenePath.coreGraphicsPath }
    let cherryStemsScenePath: DiagramScenePath
    /// The cherries' two fruits, filled in the background color.
    public var cherryFruits: CGPath { cherryFruitsScenePath.coreGraphicsPath }
    let cherryFruitsScenePath: DiagramScenePath
    /// The patches behind ids, turned with them, filled in the background color.
    public var labelPatches: CGPath { labelPatchesScenePath.coreGraphicsPath }
    let labelPatchesScenePath: DiagramScenePath
    /// The ids, each drawn turned by its angle about its center, in the muted color.
    public let labels: [GitGraphLayoutCommitLabel]
    /// The tags' boxes, filled in the surface color and stroked `tagLineWidth` wide in the border color with round joins.
    public var tagBoxes: CGPath { tagBoxesScenePath.coreGraphicsPath }
    let tagBoxesScenePath: DiagramScenePath
    /// The tags' holes, filled in the border color.
    public var tagHoles: CGPath { tagHolesScenePath.coreGraphicsPath }
    let tagHolesScenePath: DiagramScenePath
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
        let groups = (0..<Self.seriesColorCount).map { _ in GroupPaths() }
        var marks = GitGraphSymbolDrawing()
        for (laneIndex, lane) in layout.lanes.enumerated() {
            let paths = groups[laneIndex % Self.seriesColorCount]
            paths.laneLines.addLines(between: [lane.lineStart, lane.lineEnd])
            if let frame = lane.nameFrame {
                paths.nameBoxes.addRoundedRect(in: frame, cornerWidth: Self.nameBoxCornerRadius, cornerHeight: Self.nameBoxCornerRadius)
            }
        }
        for connector in layout.connectors {
            let paths = groups[connector.laneIndex % Self.seriesColorCount]
            switch connector.style {
            case .alongLane: paths.straightLines.addEdgePath(connector.path)
            case .acrossLanes: paths.curves.addEdgePath(connector.path)
            case .cherryPick: paths.cherryPickCurves.addEdgePath(connector.path)
            }
        }
        var labelPatches = DiagramScenePath()
        var tagBoxes = DiagramScenePath()
        var tagHoles = DiagramScenePath()
        for commit in layout.commits {
            let paths = groups[commit.laneIndex % Self.seriesColorCount]
            marks.add(commit.symbol, at: commit.center, symbols: &paths.symbols, rings: &paths.rings)
            if let label = commit.label { Self.addPatch(of: label, to: &labelPatches) }
            for tag in commit.tags { Self.addTag(tag.frame, box: &tagBoxes, hole: &tagHoles) }
        }
        colorGroups = groups.enumerated().compactMap { seriesIndex, paths in paths.group(seriesIndex: seriesIndex) }
        reverseCrossesScenePath = marks.reverseCrosses
        cherryStemsScenePath = marks.cherryStems
        cherryFruitsScenePath = marks.cherryFruits
        self.labelPatchesScenePath = labelPatches
        labels = layout.commits.compactMap(\.label)
        self.tagBoxesScenePath = tagBoxes
        self.tagHolesScenePath = tagHoles
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

    /// The rounded patch behind an id, centered on its text and turned with it.
    private static func addPatch(of label: GitGraphLayoutCommitLabel, to patches: inout DiagramScenePath) {
        let center = label.text.center
        let frame = CGRect(x: center.x - label.patchSize.width / 2, y: center.y - label.patchSize.height / 2, width: label.patchSize.width,
                           height: label.patchSize.height)
        let turn = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: label.angle).translatedBy(x: -center.x, y: -center.y)
        patches.addRoundedRect(in: frame, cornerWidth: labelPatchCornerRadius, cornerHeight: labelPatchCornerRadius, transform: turn)
    }

    /// A tag's box, its point at the middle of its left side, and the hole at the point's base.
    private static func addTag(_ frame: CGRect, box: inout DiagramScenePath, hole: inout DiagramScenePath) {
        let pointBase = frame.minX + GitGraphGeometry.tagPointLength
        box.addLines(between: [CGPoint(x: frame.minX, y: frame.midY), CGPoint(x: pointBase, y: frame.minY), CGPoint(x: frame.maxX, y: frame.minY),
                               CGPoint(x: frame.maxX, y: frame.maxY), CGPoint(x: pointBase, y: frame.maxY)])
        box.closeSubpath()
        hole.addEllipse(in: CGRect(x: pointBase - tagHoleRadius, y: frame.midY - tagHoleRadius, width: 2 * tagHoleRadius, height: 2 * tagHoleRadius))
    }

    /// The paths of one lane color, which every use of the color adds to.
    private final class GroupPaths {
        var laneLines = DiagramScenePath()
        var nameBoxes = DiagramScenePath()
        var curves = DiagramScenePath()
        var cherryPickCurves = DiagramScenePath()
        var straightLines = DiagramScenePath()
        var rings = DiagramScenePath()
        var symbols = DiagramScenePath()

        /// The group, or nil when nothing takes its color: no lane, and no commit when lanes are hidden.
        func group(seriesIndex: Int) -> ColorGroup? {
            guard !laneLines.isEmpty || !symbols.isEmpty || !rings.isEmpty else { return nil }
            return ColorGroup(seriesIndex: seriesIndex, laneLinesScenePath: laneLines, nameBoxesScenePath: nameBoxes, curvesScenePath: curves,
                              cherryPickCurvesScenePath: cherryPickCurves, straightLinesScenePath: straightLines, ringsScenePath: rings,
                              symbolsScenePath: symbols)
        }
    }
}
