/**
 * File: BlockLayoutEngine.swift
 * -----------------------------
 * Layer: Core
 * Description: Lays a block diagram out as Pele's renderBlock does: the blocks measured and placed in their nested
 *              grids, the edges routed and their texts settled, gaps widened where texts do not fit, and the page.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// Lays a block diagram out in Pele's measurements: 12 points between cells and inside each composite's border (the
/// diagram's `block.padding` when it sets one, 6 at most when tight), a block's text wrapped at 200 points (80 tight), an
/// edge's at seven eighths of the size, 8 points of padding round the page and the bold title 12 points above.
public enum BlockLayoutEngine {
    static let gap: CGFloat = 12
    static let tightGap: CGFloat = 6
    static let largestPadding: CGFloat = 200
    static let wrappingWidth: CGFloat = 200
    static let tightWrappingWidth: CGFloat = 80
    static let padding: CGFloat = 8
    static let titleGap: CGFloat = 12
    /// How many times a widened gap is laid out again, as a container stretched by its row gives some of it back.
    static let wideningRounds = 3

    /// The diagram laid out with room to spare, or tightly (`isTight`, Pele's drawing for a host too narrow for it), its
    /// titles wrapped and its widening kept within `availableWidth`.
    public static func layout(_ diagram: BlockDiagram, typography: DiagramTypography, availableWidth: CGFloat? = nil,
                              isTight: Bool = false) throws(BlockLayoutError) -> BlockLayout {
        let font = typography.font
        let measurers = BlockMeasurers(nodeText: typography.nodeText, edgeText: typography.edgeText, titleText: typography.boldNodeText,
                                       restyled: { fontSize, isBold, isItalic in
                                           CoreTextDiagramTextMeasurer(font: font.resized(to: fontSize), isBold: isBold, isItalic: isItalic)
                                       })
        return try layout(diagram, measurers: measurers, font: font, availableWidth: availableWidth, isTight: isTight)
    }

    static func layout<Measurer: DiagramTextMeasuring>(_ diagram: BlockDiagram, measurers: BlockMeasurers<Measurer>, font: DiagramFont,
                                                       availableWidth: CGFloat? = nil, isTight: Bool = false) throws(BlockLayoutError) -> BlockLayout {
        let gap = min(diagram.padding ?? Self.gap, isTight ? tightGap : .infinity)
        let titleWidth = isTight ? DiagramWidthFitting.titleRoom(availableWidth: availableWidth) : PlaneMapLabel.unwrappedWidth
        let views = BlockViews(diagram, measurers: measurers, gap: gap, wrappingWidth: isTight ? tightWrappingWidth : wrappingWidth, titleWidth: titleWidth)
        var placement = BlockPlacement(views, gap: gap)
        try placement.place()
        var edges = edgePlacement(of: diagram, views: views, edgeText: measurers.edgeText, obstacleCount: placement.obstacleIndices.count)
        try settle(&edges, &placement, isTight: isTight, availableWidth: availableWidth)
        let title = PlaneMapLabel.block(diagram.title, measurer: measurers.titleText, maximumWidth: titleWidth)
        var assembly = BlockLayoutAssembly(diagram: diagram, placement: placement, edges: edges, measurers: measurers)
        return assembly.layout(title: title, font: font)
    }

    /// The edges whose both ends are drawn, with their texts measured.
    private static func edgePlacement<Measurer: DiagramTextMeasuring>(of diagram: BlockDiagram, views: BlockViews, edgeText: Measurer,
                                                                      obstacleCount: Int) -> BlockEdgePlacement {
        var edgeIndices: [Int] = []
        var ends: [(source: Int, target: Int)] = []
        var textSizes: [CGSize] = []
        for (index, edge) in diagram.edges.enumerated() {
            guard let source = views.cellIndicesByIdentifier[edge.sourceIdentifier], let target = views.cellIndicesByIdentifier[edge.targetIdentifier] else { continue }
            edgeIndices.append(index)
            ends.append((source, target))
            textSizes.append(PlaneMapLabel.block(edge.label, measurer: edgeText, maximumWidth: wrappingWidth)?.size ?? .zero)
        }
        return BlockEdgePlacement(edgeIndices: edgeIndices, ends: ends, textSizes: textSizes, edgeTextSize: edgeText.fontSize,
                                  obstacleCount: obstacleCount, cellCount: views.cells.count)
    }

    /// Pele's rounds: the texts stacked, and where they do not fit the gaps widened and the grid laid out again, up to
    /// three times; kept only when that leaves the texts covering each other less and the drawing within the width.
    private static func settle(_ edges: inout BlockEdgePlacement, _ placement: inout BlockPlacement, isTight: Bool,
                               availableWidth: CGFloat?) throws(BlockLayoutError) {
        let mayGrow = edges.ends.count * edges.ends.count <= BlockEdgePlacement.obstacleBudget
        guard edges.settle(&placement, grow: mayGrow, isTight: isTight) else { return }
        let before = edges.textOverlap
        let narrow = edges.extent(contentSize: placement.contentSize, outlines: placement.outlines).width
        var grown = true
        var round = 0
        while round < wideningRounds, grown {
            try placement.place()
            grown = edges.settle(&placement, grow: round < wideningRounds - 1, isTight: isTight)
            round += 1
        }
        let wide = edges.extent(contentSize: placement.contentSize, outlines: placement.outlines).width
        let room = DiagramWidthFitting.limit(availableWidth) ?? .infinity
        if edges.textOverlap > before - 1 || (wide > narrow && (wide + 2 * padding).rounded(.up) > room) {
            placement.clearGaps()
            try placement.place()
            _ = edges.settle(&placement, grow: false, isTight: isTight)
        }
    }
}
