/**
 * File: SankeyDrawingParts.swift
 * ------------------------------
 * Layer: Core
 * Description: A laid-out Sankey diagram's geometry grouped by how it is painted: bands, bars, labels and title.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// A laid-out Sankey diagram's geometry grouped by how it is painted, so that drawing it in any colors is a few fills,
/// by Core Graphics (`SankeyRenderer`) or by a view's own shapes. Back to front, as Pele draws: the bands, the bars,
/// the labels, the title.
public struct SankeyDrawingParts {
    /// Each band in the order of the rows, filled at `bandOpacity` with a gradient across from its source's series
    /// color at its start to its target's at its end, as Pele fills it in a page.
    public let bands: [SankeyBandDrawing]
    /// For each series color, the bars filled in it: entry `k` is filled in `DiagramPalette.seriesColor(at: k)` and
    /// holds the bars of the nodes whose index leaves `k` when divided by the number of series colors.
    public let nodeFills: [CGPath]
    /// The bars of the nodes the options give a color of their own, each in it.
    public let coloredNodeFills: [SankeyColoredFill]
    /// How the bands are colored, and whether the labels are outlined (`SankeyOptions`).
    public let linkColor: SankeyLinkColor
    public let hasOutlinedLabels: Bool
    /// The nodes' names, in the text color.
    public let names: [DiagramTextBlock]
    /// The nodes' values, in the muted color.
    public let values: [DiagramTextBlock]
    /// The title, drawn bold, or nil.
    public let title: DiagramTextBlock?

    /// Pele's `fill-opacity` for the bands.
    public static let bandOpacity: CGFloat = 0.4
    /// The width of the outline stroked around outlined labels' glyphs.
    public static let labelOutlineWidth: CGFloat = 3
    /// The largest corner radius of a bar; a bar under 4 points tall is rounded by half its height.
    static let barCornerRadius: CGFloat = 2
    /// Pele's eight `--pele-series-*` colors, which the nodes take in turn.
    public static let seriesColorCount = DiagramPalette.peleSeries.count

    public init(layout: SankeyLayout) {
        let nodeColors = layout.nodes.map(\.color)
        bands = layout.links.map { link in SankeyBandDrawing(link: link, sourceColor: nodeColors[link.sourceSeriesIndex], targetColor: nodeColors[link.targetSeriesIndex]) }
        let fills = (0..<min(layout.nodes.count, Self.seriesColorCount)).map { _ in CGMutablePath() }
        var coloredFills: [SankeyColoredFill] = []
        for node in layout.nodes {
            let radius = min(Self.barCornerRadius, node.frame.height / 2)
            if let color = node.color {
                let path = CGMutablePath()
                path.addRoundedRect(in: node.frame, cornerWidth: radius, cornerHeight: radius)
                coloredFills.append(SankeyColoredFill(path: path, color: color))
            } else {
                fills[node.seriesIndex % Self.seriesColorCount].addRoundedRect(in: node.frame, cornerWidth: radius, cornerHeight: radius)
            }
        }
        nodeFills = fills
        coloredNodeFills = coloredFills
        linkColor = layout.linkColor
        hasOutlinedLabels = layout.hasOutlinedLabels
        names = layout.labels.map(\.name)
        values = layout.labels.compactMap(\.value)
        title = layout.title
    }
}

/// A bar filled in a color of its own.
public struct SankeyColoredFill {
    public let path: CGPath
    public let color: DiagramColor
}

/// A band's outline and the colors of its gradient.
public struct SankeyBandDrawing {
    /// From the top of its start, an S-curve to the top of its end, down its end, and an S-curve back, the curves'
    /// control points halfway across.
    public let outline: CGPath
    /// Where the gradient starts, in the source's color, and ends, in the target's, across.
    public let startX: CGFloat
    public let endX: CGFloat
    public let sourceSeriesIndex: Int
    public let targetSeriesIndex: Int
    /// The colors the options give the source and the target, or nil for their series colors.
    public let sourceColor: DiagramColor?
    public let targetColor: DiagramColor?

    init(link: SankeyLayoutLink, sourceColor: DiagramColor?, targetColor: DiagramColor?) {
        self.sourceColor = sourceColor
        self.targetColor = targetColor
        let middleX = (link.startX + link.endX) / 2
        let half = link.halfThickness
        let path = CGMutablePath()
        path.move(to: CGPoint(x: link.startX, y: link.sourceY - half))
        path.addCurve(to: CGPoint(x: link.endX, y: link.targetY - half), control1: CGPoint(x: middleX, y: link.sourceY - half),
                      control2: CGPoint(x: middleX, y: link.targetY - half))
        path.addLine(to: CGPoint(x: link.endX, y: link.targetY + half))
        path.addCurve(to: CGPoint(x: link.startX, y: link.sourceY + half), control1: CGPoint(x: middleX, y: link.targetY + half),
                      control2: CGPoint(x: middleX, y: link.sourceY + half))
        path.closeSubpath()
        outline = path
        startX = link.startX
        endX = link.endX
        sourceSeriesIndex = link.sourceSeriesIndex
        targetSeriesIndex = link.targetSeriesIndex
    }
}
