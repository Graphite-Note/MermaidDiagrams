/**
 * File: WardleyMapLayoutEngine.swift
 * ----------------------------------
 * Layer: Core
 * Description: Lays a Wardley map out as Pele's renderWardley draws it at its natural width: the plot from the map's size
 *              or the options', the stages and axes, everything at its coordinates, then the title and the page.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// Lays a Wardley map out in Pele's measurements: a plot the map's size (else the options', else 900 by 600) less
/// Mermaid's 48-point canvas margin on each side, each side kept from 200 to 10,000 first; the stages' names 8 points
/// under it and `Evolution` 6 points under them; components 6 points in radius with their labels 8 points up and right
/// unless a link leaves that way; 8 points of padding and the bold title 12 points above the plot.
public enum WardleyMapLayoutEngine {
    /// Mermaid's room around the plot on every side of its canvas.
    static let canvasMargin: CGFloat = 48
    static let defaultWidth: Double = 900
    static let defaultHeight: Double = 600
    static let smallestSide: Double = 200
    static let largestSide: Double = 10_000
    static let padding: CGFloat = 8
    static let titleGap: CGFloat = 12
    /// Mermaid's four stages when the map names none.
    static let defaultStages = ["Genesis", "Custom Built", "Product", "Commodity"]

    public static func layout(_ map: WardleyMap, typography: DiagramTypography) -> WardleyMapLayout {
        let planeText = typography.planeMapText
        let measurers = WardleyMapMeasurers(text: typography.rowText, boldText: planeText.boldRowText, linkText: planeText.linkText,
                                            boldLinkText: planeText.boldLinkText, boldNumberText: planeText.boldSmallestText, titleText: typography.boldNodeText)
        return layout(map, measurers: measurers, font: typography.font)
    }

    static func layout<Measurer: DiagramTextMeasuring>(_ map: WardleyMap, measurers: WardleyMapMeasurers<Measurer>, font: DiagramFont) -> WardleyMapLayout {
        let plotWidth = plotSide(map.size?.width, option: map.options.width, fallback: defaultWidth)
        let plotHeight = plotSide(map.size?.height, option: map.options.height, fallback: defaultHeight)
        var placement = WardleyMapPlacement(map: map, measurers: measurers, canvas: WardleyMapCanvas(plotWidth: plotWidth, plotHeight: plotHeight), font: font)
        placement.placeFrame()
        placement.placePipelines()
        placement.placeLinks()
        placement.placeTrends()
        placement.placeNodes()
        placement.placeAnnotations()
        placement.placeNotesAndForces()
        return placement.finishedLayout()
    }

    /// A side of the plot: the map's own, else the option's, else `fallback`, kept from 200 to 10,000, less the margins.
    private static func plotSide(_ given: Double?, option: Double?, fallback: Double) -> CGFloat {
        let value = given.flatMap { side in side.isFinite ? side : nil } ?? option ?? fallback
        return CGFloat(min(max(value, smallestSide), largestSide)) - 2 * canvasMargin
    }
}

/// A Wardley map being laid out on its canvas: the layout so far, the nodes' places, the quadrants links take around
/// each node, and the anchors' labels, measured once.
struct WardleyMapPlacement<Measurer: DiagramTextMeasuring> {
    let map: WardleyMap
    let measurers: WardleyMapMeasurers<Measurer>
    var canvas: WardleyMapCanvas
    var layout: WardleyMapLayout
    /// Each node's place, in the order of `map.nodes`.
    var positions: [CGPoint]
    var indexByIdentifier: [String: Int] = [:]
    /// The quadrants around each node that a link runs through: 1 up and right, 2 down and right, 4 up and left, 8 down
    /// and left.
    var takenQuadrants: [Int]
    var anchorLabels: [Int: DiagramTextBlock] = [:]
    /// Each pipeline parent's components, by the parent's identifier.
    var pipelineMembers: [String: Set<String>] = [:]
    /// The bottom of the stages' names, and the top of what goes under the map.
    var stageBottom: CGFloat = 0
    var legendTop: CGFloat = 0

    init(map: WardleyMap, measurers: WardleyMapMeasurers<Measurer>, canvas: WardleyMapCanvas, font: DiagramFont) {
        self.map = map
        self.measurers = measurers
        self.canvas = canvas
        layout = WardleyMapLayout(size: .zero, font: font, plot: CGRect(x: 0, y: 0, width: canvas.plotWidth, height: canvas.plotHeight),
                                  axes: DiagramPath(start: .zero, segments: [.line(to: CGPoint(x: 0, y: canvas.plotHeight)),
                                                                             .line(to: CGPoint(x: canvas.plotWidth, y: canvas.plotHeight))]))
        positions = map.nodes.map { node in canvas.point(node.point) }
        takenQuadrants = Array(repeating: 0, count: map.nodes.count)
        for (index, node) in map.nodes.enumerated() {
            indexByIdentifier[node.identifier] = index
            if node.kind == .anchor {
                anchorLabels[index] = PlaneMapLabel.block(node.label, measurer: measurers.boldText)
            }
        }
    }

    /// The stages' dashed lines and names, the grid, and the axes' titles.
    mutating func placeFrame() {
        let stages = (map.stages?.isEmpty ?? true) ? WardleyMapLayoutEngine.defaultStages : map.stages ?? []
        let boundaries = map.stageBoundaries ?? []
        let isCustom = boundaries.count == stages.count
        let width = canvas.plotWidth
        let height = canvas.plotHeight
        stageBottom = height
        var previous: CGFloat = 0
        for (index, stage) in stages.enumerated() {
            let start = isCustom ? previous : CGFloat(index) / CGFloat(stages.count)
            let end = isCustom ? CGFloat(min(max(boundaries[index], 0), 1)) : CGFloat(index + 1) / CGFloat(stages.count)
            previous = end
            if index > 0 { layout.stageLines.append(DiagramPath(start: CGPoint(x: start * width, y: 0), segments: [.line(to: CGPoint(x: start * width, y: height))])) }
            guard let label = PlaneMapLabel.block(stage, measurer: measurers.text, maximumWidth: max(48, abs(end - start) * width - 12)) else { continue }
            layout.stageLabels.append(canvas.centered(label, at: CGPoint(x: (start + end) / 2 * width, y: height + 8 + label.size.height / 2)))
            stageBottom = max(stageBottom, height + 8 + label.size.height)
        }
        if map.options.showsGrid {
            for quarter in 1..<4 {
                let x = width * CGFloat(quarter) / 4
                let y = height * CGFloat(quarter) / 4
                layout.gridLines.append(DiagramPath(start: CGPoint(x: x, y: 0), segments: [.line(to: CGPoint(x: x, y: height))]))
                layout.gridLines.append(DiagramPath(start: CGPoint(x: 0, y: y), segments: [.line(to: CGPoint(x: width, y: y))]))
            }
        }
        let evolution = PlaneMapLabel.block("Evolution", measurer: measurers.text)
        let visibility = PlaneMapLabel.block("Visibility", measurer: measurers.text)
        let evolutionHeight = evolution?.size.height ?? 0
        layout.evolutionTitle = evolution.map { block in canvas.centered(block, at: CGPoint(x: width / 2, y: stageBottom + 6 + evolutionHeight / 2)) }
        layout.visibilityTitle = visibility.map { block in PlaneMapLabel.placed(block, at: CGPoint(x: -16, y: height / 2)) }
        canvas.grow(-16 - (visibility?.size.height ?? 0) / 2, 0, 0, 0)
        legendTop = stageBottom + 6 + evolutionHeight + 10
    }

    /// The title above the plot's middle, and everything moved so that the extent starts 8 points in and the title's 8
    /// points above it.
    mutating func finishedLayout() -> WardleyMapLayout {
        let title = PlaneMapLabel.block(map.title, measurer: measurers.titleText)
        let titleWidth = title?.size.width ?? 0
        let titleHeight = title.map { block in block.size.height + WardleyMapLayoutEngine.titleGap } ?? 0
        let left = min(canvas.minimumX, canvas.plotWidth / 2 - titleWidth / 2)
        let right = max(canvas.maximumX, canvas.plotWidth / 2 + titleWidth / 2)
        let padding = WardleyMapLayoutEngine.padding
        let offset = CGVector(dx: padding - left, dy: padding + titleHeight - canvas.minimumY)
        var finished = layout.translated(by: offset)
        finished.size = CGSize(width: (right - left + 2 * padding).rounded(.up), height: (canvas.maximumY - canvas.minimumY + titleHeight + 2 * padding).rounded(.up))
        finished.title = title.map { block in PlaneMapLabel.placed(block, at: CGPoint(x: offset.dx + canvas.plotWidth / 2, y: padding + block.size.height / 2)) }
        return finished
    }
}
