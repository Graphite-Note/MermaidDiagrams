/**
 * File: GitGraphScenePaths.swift
 * ------------------------------
 * Layer: Core
 * Description: A laid-out Git graph's geometry grouped by how it is painted, recorded into Core Graphics paths for the
 *              drawing parts or into a scene's lanes: per series color the lanes, name boxes, lines, rings and symbols;
 *              then the marks, the ids' patches and the tags.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics

/// A path the Git graph's drawing records into: what every drawing records, and rounded rectangles turned by a
/// transform, as `CGMutablePath.addRoundedRect(in:cornerWidth:cornerHeight:transform:)` adds them.
protocol GitGraphPathRecording: DiagramPathRecording {
    func addRoundedRect(in rect: CGRect, cornerWidth: CGFloat, cornerHeight: CGFloat, transform: CGAffineTransform?)
}

extension DiagramPathLane: GitGraphPathRecording {}

extension DiagramCoreGraphicsPath: GitGraphPathRecording {
    /// Only for a path the Core Graphics maker made with `makePath()`, a mutable one: the Git graph's drawing adds rounded
    /// rectangles to nothing else.
    func addRoundedRect(in rect: CGRect, cornerWidth: CGFloat, cornerHeight: CGFloat, transform: CGAffineTransform?) {
        // A Core Foundation cast, which does not check: `path` is the mutable path `makePath()` made.
        let mutablePath = path as! CGMutablePath
        mutablePath.addRoundedRect(in: rect, cornerWidth: cornerWidth, cornerHeight: cornerHeight, transform: transform ?? .identity)
    }
}

/// A Git graph's shapes, each made once, in any kind its drawing records: the drawing parts' Core Graphics paths, or a
/// scene's lanes, which hold Core Graphics' elements for the same calls, bit for bit.
struct GitGraphScenePaths<Path: GitGraphPathRecording> {
    /// What is painted in one series color (`GitGraphDrawingParts.ColorGroup`).
    struct Group {
        let laneLines: Path
        let nameBoxes: Path
        let curves: Path
        let cherryPickCurves: Path
        let straightLines: Path
        let rings: Path
        let symbols: Path

        init<Maker: DiagramPathMaking>(making maker: Maker) where Maker.Path == Path {
            laneLines = maker.makePath()
            nameBoxes = maker.makePath()
            curves = maker.makePath()
            cherryPickCurves = maker.makePath()
            straightLines = maker.makePath()
            rings = maker.makePath()
            symbols = maker.makePath()
        }

        /// Whether anything takes the group's color: a lane, or a commit when lanes are hidden.
        var isPainted: Bool { !laneLines.isEmpty || !symbols.isEmpty || !rings.isEmpty }
    }

    /// By series index, `GitGraphDrawingParts.seriesColorCount` of them.
    let groups: [Group]
    let reverseCrosses: Path
    let cherryStems: Path
    let cherryFruits: Path
    let labelPatches: Path
    let tagBoxes: Path
    let tagHoles: Path

    init<Maker: DiagramPathMaking>(layout: GitGraphLayout, making maker: Maker) where Maker.Path == Path {
        let groups = (0..<GitGraphDrawingParts.seriesColorCount).map { _ in Group(making: maker) }
        self.groups = groups
        reverseCrosses = maker.makePath()
        cherryStems = maker.makePath()
        cherryFruits = maker.makePath()
        labelPatches = maker.makePath()
        tagBoxes = maker.makePath()
        tagHoles = maker.makePath()
        for (laneIndex, lane) in layout.lanes.enumerated() {
            let paths = groups[laneIndex % groups.count]
            paths.laneLines.addLines(between: [lane.lineStart, lane.lineEnd])
            if let frame = lane.nameFrame {
                let corner = GitGraphDrawingParts.nameBoxCornerRadius
                paths.nameBoxes.addRoundedRect(in: frame, cornerWidth: corner, cornerHeight: corner, transform: nil)
            }
        }
        for connector in layout.connectors {
            let paths = groups[connector.laneIndex % groups.count]
            let madeCount = maker.madePathCount
            let line = maker.makePath()
            DiagramEdgeDrawing.record(connector.path, into: line)
            switch connector.style {
            case .alongLane: paths.straightLines.addPath(line)
            case .acrossLanes: paths.curves.addPath(line)
            case .cherryPick: paths.cherryPickCurves.addPath(line)
            }
            maker.givePathsBack(downTo: madeCount)
        }
        for commit in layout.commits {
            let paths = groups[commit.laneIndex % groups.count]
            addSymbol(commit.symbol, at: commit.center, symbols: paths.symbols, rings: paths.rings)
            if let label = commit.label { addPatch(of: label) }
            for tag in commit.tags { addTag(tag.frame) }
        }
    }

    /// The rounded patch behind an id, centered on its text and turned with it.
    private func addPatch(of label: GitGraphLayoutCommitLabel) {
        let center = label.text.center
        let frame = CGRect(x: center.x - label.patchSize.width / 2, y: center.y - label.patchSize.height / 2, width: label.patchSize.width,
                           height: label.patchSize.height)
        let turn = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: label.angle).translatedBy(x: -center.x, y: -center.y)
        let corner = GitGraphDrawingParts.labelPatchCornerRadius
        labelPatches.addRoundedRect(in: frame, cornerWidth: corner, cornerHeight: corner, transform: turn)
    }

    /// A tag's box, its point at the middle of its left side, and the hole at the point's base.
    private func addTag(_ frame: CGRect) {
        let pointBase = frame.minX + GitGraphGeometry.tagPointLength
        tagBoxes.addLines(between: [CGPoint(x: frame.minX, y: frame.midY), CGPoint(x: pointBase, y: frame.minY), CGPoint(x: frame.maxX, y: frame.minY),
                                    CGPoint(x: frame.maxX, y: frame.maxY), CGPoint(x: pointBase, y: frame.maxY)])
        tagBoxes.closeSubpath()
        let radius = GitGraphDrawingParts.tagHoleRadius
        tagHoles.addEllipse(in: CGRect(x: pointBase - radius, y: frame.midY - radius, width: 2 * radius, height: 2 * radius))
    }

    /// Adds `symbol` at `center`: its fills to `symbols`, a merge's ring to `rings`, its marks to the shared lanes
    /// (`GitGraphSymbolDrawing`'s geometry).
    private func addSymbol(_ symbol: GitGraphCommitSymbol, at center: CGPoint, symbols: Path, rings: Path) {
        typealias Drawing = GitGraphSymbolDrawing
        switch symbol {
        case .normal:
            symbols.addEllipse(in: Drawing.circle(at: center, radius: GitGraphGeometry.dotRadius))
        case .reverse:
            symbols.addEllipse(in: Drawing.circle(at: center, radius: GitGraphGeometry.dotRadius))
            let reach = Drawing.crossReach
            reverseCrosses.addLines(between: [CGPoint(x: center.x - reach, y: center.y - reach), CGPoint(x: center.x + reach, y: center.y + reach)])
            reverseCrosses.addLines(between: [CGPoint(x: center.x - reach, y: center.y + reach), CGPoint(x: center.x + reach, y: center.y - reach)])
        case .highlight:
            let square = Drawing.circle(at: center, radius: GitGraphGeometry.dotRadius + 1)
            symbols.addRoundedRect(in: square, cornerWidth: Drawing.squareCornerRadius, cornerHeight: Drawing.squareCornerRadius, transform: nil)
        case .merge:
            rings.addEllipse(in: Drawing.circle(at: center, radius: Drawing.ringRadius))
            symbols.addEllipse(in: Drawing.circle(at: center, radius: Drawing.mergeDotRadius))
        case .cherryPick:
            symbols.addEllipse(in: Drawing.circle(at: center, radius: GitGraphGeometry.dotRadius))
            cherryStems.addLines(between: Drawing.cherryStemPoints.map { offset in center.translated(by: offset) })
            for fruit in Drawing.cherryFruitCenters {
                cherryFruits.addEllipse(in: Drawing.circle(at: center.translated(by: fruit), radius: Drawing.cherryFruitRadius))
            }
        }
    }
}

extension GitGraphScenePaths where Path == DiagramPathLane {
    /// The scene's shapes and texts, back to front as `GitGraphDrawingParts` describes them.
    func addScene(of layout: GitGraphLayout, to builder: inout DiagramSceneBuilder) {
        typealias Parts = GitGraphDrawingParts
        let painted = groups.indices.filter { seriesIndex in groups[seriesIndex].isPainted }
        for seriesIndex in painted {
            let paint = DiagramPaint.series(seriesIndex)
            builder.stroke(groups[seriesIndex].laneLines, paint, DiagramStroke(lineWidth: Parts.laneLineWidth, dashLengths: Parts.laneDashLengths), part: .cluster)
            builder.fill(groups[seriesIndex].nameBoxes, paint, part: .cluster)
        }
        for (laneIndex, lane) in layout.lanes.enumerated() {
            guard let name = lane.name else { continue }
            builder.text(name, layout.seriesColors.ink(ofSeries: laneIndex).map(DiagramPaint.color) ?? .background, part: .clusterLabel)
        }
        let connector = DiagramStroke(lineWidth: Parts.connectorLineWidth, lineCap: .round)
        for seriesIndex in painted { builder.stroke(groups[seriesIndex].curves, .series(seriesIndex), connector, part: .edge) }
        let cherryPick = DiagramStroke(lineWidth: Parts.connectorLineWidth, dashLengths: Parts.cherryPickDashLengths, lineCap: .round)
        for seriesIndex in painted { builder.stroke(groups[seriesIndex].cherryPickCurves, .series(seriesIndex), cherryPick, part: .edge) }
        for seriesIndex in painted { builder.stroke(groups[seriesIndex].straightLines, .series(seriesIndex), connector, part: .edge) }
        for seriesIndex in painted {
            let paint = DiagramPaint.series(seriesIndex)
            builder.fillAndStroke(groups[seriesIndex].rings, fill: .background, stroke: paint, DiagramStroke(lineWidth: Parts.ringLineWidth), part: .node)
            builder.fill(groups[seriesIndex].symbols, paint, part: .node)
        }
        builder.stroke(reverseCrosses, .background, DiagramStroke(lineWidth: Parts.crossLineWidth, lineCap: .round), part: .marker)
        builder.stroke(cherryStems, .background, DiagramStroke(lineWidth: Parts.cherryStemLineWidth, lineJoin: .round), part: .marker)
        builder.fill(cherryFruits, .background, part: .marker)
        builder.fill(labelPatches, .background, part: .labelBackground)
        for commit in layout.commits {
            if let label = commit.label { builder.text(label.text, .muted, rotation: label.angle, part: .label) }
        }
        builder.fillAndStroke(tagBoxes, fill: .surface, stroke: .border, DiagramStroke(lineWidth: Parts.tagLineWidth, lineJoin: .round), part: .marker)
        builder.fill(tagHoles, .border, part: .marker)
        for commit in layout.commits {
            for tag in commit.tags { builder.text(tag.text, .foreground, part: .label) }
        }
        builder.title(layout.title)
    }
}
