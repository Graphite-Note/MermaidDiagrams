/**
 * File: ReferenceGitGraphScene.swift
 * ----------------------------------
 * Layer: Tests
 * Description: 0.7.0's Git graph scene, frozen as main 2a0cc65 made it from the drawing parts' Core Graphics paths,
 *              which the scene recorded into lanes is compared with.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

enum ReferenceGitGraphScene {
    /// The Git graph's painting: the lanes and their names' boxes in the lanes' series colors, the names, the lines
    /// between lanes, to cherry-picks and along lanes, the rings and symbols and their marks, the ids turned on their
    /// patches, the tags with their text, the title.
    static func scene(layout: GitGraphLayout) -> DiagramScene {
        var builder = DiagramSceneBuilder()
        ReferenceGitGraphDrawingParts(layout: layout).addScene(to: &builder)
        return builder.scene(size: layout.size, font: layout.font, seriesColors: layout.seriesColors)
    }
}

extension ReferenceGitGraphDrawingParts {
    func addScene(to builder: inout DiagramSceneBuilder) {
        for group in colorGroups {
            let paint = DiagramPaint.series(group.seriesIndex)
            builder.stroke(group.laneLines, paint, DiagramStroke(lineWidth: Self.laneLineWidth, dashLengths: Self.laneDashLengths), part: .cluster)
            builder.fill(group.nameBoxes, paint, part: .cluster)
        }
        for (name, paint) in zip(names, namePaints) { builder.text(name, paint, part: .clusterLabel) }
        let connector = DiagramStroke(lineWidth: Self.connectorLineWidth, lineCap: .round)
        for group in colorGroups { builder.stroke(group.curves, .series(group.seriesIndex), connector, part: .edge) }
        for group in colorGroups {
            builder.stroke(group.cherryPickCurves, .series(group.seriesIndex),
                           DiagramStroke(lineWidth: Self.connectorLineWidth, dashLengths: Self.cherryPickDashLengths, lineCap: .round), part: .edge)
        }
        for group in colorGroups { builder.stroke(group.straightLines, .series(group.seriesIndex), connector, part: .edge) }
        for group in colorGroups {
            let paint = DiagramPaint.series(group.seriesIndex)
            builder.fillAndStroke(group.rings, fill: .background, stroke: paint, DiagramStroke(lineWidth: Self.ringLineWidth), part: .node)
            builder.fill(group.symbols, paint, part: .node)
        }
        builder.stroke(reverseCrosses, .background, DiagramStroke(lineWidth: Self.crossLineWidth, lineCap: .round), part: .marker)
        builder.stroke(cherryStems, .background, DiagramStroke(lineWidth: Self.cherryStemLineWidth, lineJoin: .round), part: .marker)
        builder.fill(cherryFruits, .background, part: .marker)
        builder.fill(labelPatches, .background, part: .labelBackground)
        for label in labels { builder.text(label.text, .muted, rotation: label.angle, part: .label) }
        builder.fillAndStroke(tagBoxes, fill: .surface, stroke: .border, DiagramStroke(lineWidth: Self.tagLineWidth, lineJoin: .round), part: .marker)
        builder.fill(tagHoles, .border, part: .marker)
        builder.texts(tagTexts, .foreground, part: .label)
        builder.title(title)
    }
}


/// A laid-out Git graph's geometry grouped by how it is painted, so that drawing it in any colors is a few fills and
/// strokes per color, by Core Graphics (`GitGraphRenderer`) or by a view's own shapes. Back to front, as Pele draws: the
/// lanes and their names, the lines between lanes, then along them, the commits' symbols and their marks, the ids on
/// their patches, the tags, the title.
struct ReferenceGitGraphDrawingParts {
    /// What is painted in one series color: the lanes whose index leaves `seriesIndex` when divided by
    /// `seriesColorCount`, and the commits and lines that take their color.
    struct ColorGroup {
        let seriesIndex: Int
        /// The lanes' lines, stroked `laneLineWidth` wide, dashed with `laneDashLengths`.
        let laneLines: CGPath
        /// The boxes behind branch names, filled.
        let nameBoxes: CGPath
        /// The lines between lanes, stroked `connectorLineWidth` wide with round caps.
        let curves: CGPath
        /// The lines to cherry-picks, stroked like `curves` and dashed with `cherryPickDashLengths`.
        let cherryPickCurves: CGPath
        /// The lines along lanes, stroked like `curves`, over them.
        let straightLines: CGPath
        /// Merges' rings: filled in the background color, then stroked `ringLineWidth` wide in the group's color.
        let rings: CGPath
        /// Dots, squares and the small dots inside rings, filled, over the rings.
        let symbols: CGPath
    }

    let colorGroups: [ColorGroup]
    /// The crosses on reverse commits, stroked `crossLineWidth` wide in the background color with round caps.
    let reverseCrosses: CGPath
    /// The cherries' stems, stroked `cherryStemLineWidth` wide in the background color with round joins.
    let cherryStems: CGPath
    /// The cherries' two fruits, filled in the background color.
    let cherryFruits: CGPath
    /// The patches behind ids, turned with them, filled in the background color.
    let labelPatches: CGPath
    /// The ids, each drawn turned by its angle about its center, in the muted color.
    let labels: [GitGraphLayoutCommitLabel]
    /// The tags' boxes, filled in the surface color and stroked `tagLineWidth` wide in the border color with round joins.
    let tagBoxes: CGPath
    /// The tags' holes, filled in the border color.
    let tagHoles: CGPath
    /// The tags' text, in the foreground color.
    let tagTexts: [DiagramTextBlock]
    /// The branch names, in the background color on their boxes.
    let names: [DiagramTextBlock]
    /// The paint of each of `names`: the background color, or Pele's ink on its lane's color where the graph's theme
    /// variables set that color (`DiagramSeriesColors.inks`).
    let namePaints: [DiagramPaint]
    /// The title, drawn bold, or nil.
    let title: DiagramTextBlock?

    static let laneLineWidth: CGFloat = 1
    static let laneDashLengths: [CGFloat] = [2, 4]
    static let connectorLineWidth: CGFloat = 2
    static let cherryPickDashLengths: [CGFloat] = [4, 3]
    static let ringLineWidth: CGFloat = 2
    static let crossLineWidth: CGFloat = 1.5
    static let cherryStemLineWidth: CGFloat = 1
    static let tagLineWidth: CGFloat = 1
    /// Pele's eight `--pele-series-*` colors, which lanes take in turn.
    static let seriesColorCount = DiagramPalette.peleSeries.count
    /// The corner radius of a name's box: Pele's `--pele-radius`.
    static let nameBoxCornerRadius: CGFloat = 4
    static let labelPatchCornerRadius: CGFloat = 3
    static let tagHoleRadius: CGFloat = 1.5

    init(layout: GitGraphLayout) {
        let groups = (0..<Self.seriesColorCount).map { _ in GroupPaths() }
        let marks = ReferenceGitGraphSymbolDrawing()
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
            case .alongLane: paths.straightLines.addPath(DiagramEdgeDrawing.path(connector.path))
            case .acrossLanes: paths.curves.addPath(DiagramEdgeDrawing.path(connector.path))
            case .cherryPick: paths.cherryPickCurves.addPath(DiagramEdgeDrawing.path(connector.path))
            }
        }
        let labelPatches = CGMutablePath()
        let tagBoxes = CGMutablePath()
        let tagHoles = CGMutablePath()
        for commit in layout.commits {
            let paths = groups[commit.laneIndex % Self.seriesColorCount]
            marks.add(commit.symbol, at: commit.center, symbols: paths.symbols, rings: paths.rings)
            if let label = commit.label { Self.addPatch(of: label, to: labelPatches) }
            for tag in commit.tags { Self.addTag(tag.frame, box: tagBoxes, hole: tagHoles) }
        }
        colorGroups = groups.enumerated().compactMap { seriesIndex, paths in paths.group(seriesIndex: seriesIndex) }
        reverseCrosses = marks.reverseCrosses
        cherryStems = marks.cherryStems
        cherryFruits = marks.cherryFruits
        self.labelPatches = labelPatches
        labels = layout.commits.compactMap(\.label)
        self.tagBoxes = tagBoxes
        self.tagHoles = tagHoles
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
    private static func addPatch(of label: GitGraphLayoutCommitLabel, to patches: CGMutablePath) {
        let center = label.text.center
        let frame = CGRect(x: center.x - label.patchSize.width / 2, y: center.y - label.patchSize.height / 2, width: label.patchSize.width,
                           height: label.patchSize.height)
        let turn = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: label.angle).translatedBy(x: -center.x, y: -center.y)
        patches.addRoundedRect(in: frame, cornerWidth: labelPatchCornerRadius, cornerHeight: labelPatchCornerRadius, transform: turn)
    }

    /// A tag's box, its point at the middle of its left side, and the hole at the point's base.
    private static func addTag(_ frame: CGRect, box: CGMutablePath, hole: CGMutablePath) {
        let pointBase = frame.minX + GitGraphGeometry.tagPointLength
        box.addLines(between: [CGPoint(x: frame.minX, y: frame.midY), CGPoint(x: pointBase, y: frame.minY), CGPoint(x: frame.maxX, y: frame.minY),
                               CGPoint(x: frame.maxX, y: frame.maxY), CGPoint(x: pointBase, y: frame.maxY)])
        box.closeSubpath()
        hole.addEllipse(in: CGRect(x: pointBase - tagHoleRadius, y: frame.midY - tagHoleRadius, width: 2 * tagHoleRadius, height: 2 * tagHoleRadius))
    }

    /// Core Graphics paths are references: a copy of these adds to the same paths.
    private struct GroupPaths {
        let laneLines = CGMutablePath()
        let nameBoxes = CGMutablePath()
        let curves = CGMutablePath()
        let cherryPickCurves = CGMutablePath()
        let straightLines = CGMutablePath()
        let rings = CGMutablePath()
        let symbols = CGMutablePath()

        /// The group, or nil when nothing takes its color: no lane, and no commit when lanes are hidden.
        func group(seriesIndex: Int) -> ColorGroup? {
            guard !laneLines.isEmpty || !symbols.isEmpty || !rings.isEmpty else { return nil }
            return ColorGroup(seriesIndex: seriesIndex, laneLines: laneLines, nameBoxes: nameBoxes, curves: curves, cherryPickCurves: cherryPickCurves,
                              straightLines: straightLines, rings: rings, symbols: symbols)
        }
    }
}


/// The geometry of commits' symbols, Pele's: a dot 7 points in radius; a square a point wider than the dot on each
/// side with rounded corners; a ring 6 points in radius around a dot of 2.5; and the marks drawn on a dot in the
/// background color, a cross on a reverse commit and a cherry on a cherry-pick. The marks of every commit gather here.
struct ReferenceGitGraphSymbolDrawing {
    let reverseCrosses = CGMutablePath()
    let cherryStems = CGMutablePath()
    let cherryFruits = CGMutablePath()

    static let squareCornerRadius: CGFloat = 2
    static let ringRadius: CGFloat = GitGraphGeometry.dotRadius - 1
    static let mergeDotRadius: CGFloat = 2.5
    /// How far each arm of a reverse commit's cross reaches from the center, across and down.
    static let crossReach: CGFloat = 3
    /// The cherry's stem, from the left fruit up to its top and down to the right fruit, from the dot's center.
    static let cherryStemPoints = [CGVector(dx: -2.6, dy: 1), CGVector(dx: 0.8, dy: -4.2), CGVector(dx: 2.6, dy: 1)]
    static let cherryFruitCenters = [CGVector(dx: -2.6, dy: 2.2), CGVector(dx: 2.6, dy: 2.2)]
    static let cherryFruitRadius: CGFloat = 1.8

    /// Adds `symbol` at `center`: its fills to `symbols`, a merge's ring to `rings`, its marks to the shared paths.
    func add(_ symbol: GitGraphCommitSymbol, at center: CGPoint, symbols: CGMutablePath, rings: CGMutablePath) {
        switch symbol {
        case .normal:
            symbols.addEllipse(in: Self.circle(at: center, radius: GitGraphGeometry.dotRadius))
        case .reverse:
            symbols.addEllipse(in: Self.circle(at: center, radius: GitGraphGeometry.dotRadius))
            let reach = Self.crossReach
            reverseCrosses.addLines(between: [CGPoint(x: center.x - reach, y: center.y - reach), CGPoint(x: center.x + reach, y: center.y + reach)])
            reverseCrosses.addLines(between: [CGPoint(x: center.x - reach, y: center.y + reach), CGPoint(x: center.x + reach, y: center.y - reach)])
        case .highlight:
            let square = Self.circle(at: center, radius: GitGraphGeometry.dotRadius + 1)
            symbols.addRoundedRect(in: square, cornerWidth: Self.squareCornerRadius, cornerHeight: Self.squareCornerRadius)
        case .merge:
            rings.addEllipse(in: Self.circle(at: center, radius: Self.ringRadius))
            symbols.addEllipse(in: Self.circle(at: center, radius: Self.mergeDotRadius))
        case .cherryPick:
            symbols.addEllipse(in: Self.circle(at: center, radius: GitGraphGeometry.dotRadius))
            cherryStems.addLines(between: Self.cherryStemPoints.map { offset in center.translated(by: offset) })
            for fruit in Self.cherryFruitCenters { cherryFruits.addEllipse(in: Self.circle(at: center.translated(by: fruit), radius: Self.cherryFruitRadius)) }
        }
    }

    /// The square around a circle of `radius` at `center`.
    private static func circle(at center: CGPoint, radius: CGFloat) -> CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius)
    }
}
