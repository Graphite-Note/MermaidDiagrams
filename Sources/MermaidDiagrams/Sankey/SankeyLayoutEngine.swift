/**
 * File: SankeyLayoutEngine.swift
 * ------------------------------
 * Layer: Core
 * Description: Lays a Sankey diagram out as Pele does, with its options and for a narrow column.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import CoreGraphics
import Foundation

/// Lays a Sankey diagram out as Pele does, with the options of its front matter (`SankeyOptions`): a chart of 600 by
/// 400 points (narrower in a narrow column), nodes 10 points wide in columns (`SankeyPlacement`) with 27 points between nodes (12, and 15 for the
/// value under each label), each node's label beside its bar (`SankeyLabelPlacement`), its name and its value rounded
/// to two decimals, at seven eighths of the text size, smaller when a column holds so many nodes that each would have
/// less than 1.8 lines (down to five eighths), the bold title above, and the page around the chart and its labels.
public enum SankeyLayoutEngine {
    /// The room values add between two nodes of a column, when they are shown.
    static let valuePadding = 15.0
    /// Around the page.
    static let padding: CGFloat = 8
    /// Between the title and the chart.
    static let titleGap: CGFloat = 12
    /// The labels' size, as a share of the text size, and the least they shrink to.
    static let labelScale: CGFloat = 0.875
    static let smallestLabelScale: CGFloat = 0.625
    /// The lines of room each node of the fullest column keeps for its label before labels shrink.
    static let linesPerNode = 1.8
    /// A thin node keeps room for its label's height: the label's size times this.
    static let labelHeightRatio = 1.15
    /// Beyond this, a value is written as it is, not rounded to two decimals.
    static let largestRoundedValue = 1e15
    /// The narrowest a narrow column makes the chart, labels left out.
    static let narrowestChartWidth: CGFloat = 160

    /// `availableWidth`, the width of the column the diagram is shown in, narrows the chart as Pele narrows it
    /// (`DiagramWidthFitting.fitWidth`: the chart gives up what its labels overflow, down to 160 points, drawn again up to
    /// three times) and the labels shrink with it; nil keeps the chart's own width.
    public static func layout(_ diagram: SankeyDiagram, typography: DiagramTypography, availableWidth: CGFloat? = nil) throws(SankeyLayoutError) -> SankeyLayout {
        let labelSize = typography.edgeText.fontSize
        return try layout(diagram, titleText: typography.boldNodeText, font: typography.font, availableWidth: availableWidth) { size in
            size == labelSize ? typography.edgeText : CoreTextDiagramTextMeasurer(font: typography.font.resized(to: size))
        }
    }

    /// `labelText` gives the measurer of the labels at a size: seven eighths of the font's, or less when crowded or narrowed.
    static func layout<Measurer: DiagramTextMeasuring>(_ diagram: SankeyDiagram, titleText: some DiagramTextMeasuring, font: DiagramFont,
                                                       availableWidth: CGFloat? = nil,
                                                       labelText: (CGFloat) -> Measurer) throws(SankeyLayoutError) -> SankeyLayout {
        let natural = diagram.options.chartWidth
        return try DiagramWidthFitting.fitWidth(availableWidth: availableWidth, natural: CGFloat(natural), least: narrowestChartWidth,
                                                width: { (layout: SankeyLayout) in layout.size.width }) { (plot: CGFloat, _: Bool) throws(SankeyLayoutError) in
            try layout(diagram, titleText: titleText, font: font, chartWidth: Double(plot), availableWidth: availableWidth, labelText: labelText)
        }
    }

    /// The diagram on a chart `chartWidth` wide, whose own width is `options.chartWidth`.
    private static func layout<Measurer: DiagramTextMeasuring>(_ diagram: SankeyDiagram, titleText: some DiagramTextMeasuring, font: DiagramFont,
                                                               chartWidth: Double, availableWidth: CGFloat?,
                                                               labelText: (CGFloat) -> Measurer) throws(SankeyLayoutError) -> SankeyLayout {
        let options = diagram.options
        let nodeWidth = min(options.nodeWidth, chartWidth)
        let smallest = (font.size * smallestLabelScale).rounded()
        // Labels shrink with a chart narrowed to fit, as they would if the whole picture were scaled down.
        var labelSize = max(smallest, (font.size * labelScale * CGFloat(min(1, chartWidth / options.chartWidth))).rounded())
        var placement = try place(diagram, labelSize: labelSize, chartWidth: chartWidth, nodeWidth: nodeWidth)
        let fullestColumn = max(1, placement.columns.map(\.count).max() ?? 1)
        let roomPerNode = CGFloat(options.chartHeight) / CGFloat(fullestColumn) / CGFloat(linesPerNode)
        let crowdedSize = max(smallest, roomPerNode.rounded())
        if crowdedSize < labelSize {
            labelSize = crowdedSize
            placement = try place(diagram, labelSize: labelSize, chartWidth: chartWidth, nodeWidth: nodeWidth)
        }
        let measurer = labelText(labelSize)
        let texts = diagram.nodes.indices.map { index in labelTexts(name: diagram.nodes[index].name, value: placement.nodes[index].value, options: options) }
        let widths = texts.map { text in Double(measurer.width(of: text.value.map { value in text.name + " " + value } ?? text.name)) }
        let labels = SankeyLabelPlacement(nodes: placement.nodes, widths: widths, fontSize: Double(labelSize),
                                          chartSize: (chartWidth, options.chartHeight), nodeWidth: nodeWidth,
                                          centralLayer: options.isOutlined ? centralLayer(of: placement.nodes) : nil)
        let title = diagram.title.map { title in
            DiagramTextBlock(label: DiagramLabelDecoder.label(from: title, form: .plain), measurer: titleText,
                             maximumWidth: DiagramWidthFitting.titleRoom(availableWidth: availableWidth))
        }.flatMap { block in block.lines.isEmpty ? nil : block }
        let page = SankeyPage(labels: labels, title: title, nodeWidth: nodeWidth)
        return SankeyLayout(size: page.size, font: font, title: page.placedTitle,
                            nodes: placement.nodes.enumerated().map { index, node in
                                page.node(node, seriesIndex: index, paint: options.nodePaints[diagram.nodes[index].name])
                            },
                            links: placement.links.map { link in page.link(link, nodes: placement.nodes) },
                            labels: zip(texts, labels.labels).map { text, label in
                                page.label(name: text.name, value: text.value, label: label, measurer: measurer)
                            }, linkColor: options.linkColor, fixedLinkPaint: options.fixedLinkPaint,
                            hasOutlinedLabels: options.isOutlined)
    }

    /// The column of the first node with the most flow through it: outlined labels stand after the bars from there on.
    private static func centralLayer(of nodes: [SankeyPlacement.Node]) -> Int {
        var central = 0
        var most = 0.0
        for node in nodes where node.value > most {
            most = node.value
            central = node.layer
        }
        return central
    }

    private static func place(_ diagram: SankeyDiagram, labelSize: CGFloat, chartWidth: Double, nodeWidth: Double) throws(SankeyLayoutError) -> SankeyPlacement {
        let options = diagram.options
        return try SankeyPlacement(diagram: diagram, options: SankeyPlacement.Options(
            width: chartWidth, height: options.chartHeight, nodeWidth: nodeWidth,
            nodePadding: options.nodePadding + (options.showsValues ? valuePadding : 0), labelHeight: Double(labelSize) * labelHeightRatio,
            alignment: options.alignment))
    }

    /// A node's name with its entity codes decoded and its whitespace runs as one space, as an SVG shows it, and its
    /// value rounded to two decimals, written as JavaScript writes it between the options' prefix and suffix, or nil
    /// when the options hide values.
    /// Whether a name has no entity code to decode and no whitespace but single spaces, so that it is shown as written.
    private static func isPlain(_ name: String) -> Bool {
        var followsSpace = false
        for byte in name.utf8 {
            if byte == MermaidByte.semicolon || byte >= 0x80 || (byte < MermaidByte.space && byte != MermaidByte.space) { return false }
            if byte == MermaidByte.space, followsSpace { return false }
            followsSpace = byte == MermaidByte.space
        }
        return true
    }

    private static func labelTexts(name: String, value: Double, options: SankeyOptions) -> (name: String, value: String?) {
        let decoded = isPlain(name) ? name : DiagramLabelDecoder.decodingEntities(name).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard options.showsValues else { return (decoded, nil) }
        let rounded = value.magnitude < largestRoundedValue ? ((value * 100) + 0.5).rounded(.down) / 100 : value
        return (decoded, options.valuePrefix + JavaScriptNumberText.text(rounded) + options.valueSuffix)
    }
}
