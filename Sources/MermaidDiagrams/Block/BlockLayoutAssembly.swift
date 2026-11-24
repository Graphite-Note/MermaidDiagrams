/**
 * File: BlockLayoutAssembly.swift
 * -------------------------------
 * Layer: Core
 * Description: Puts a placed block diagram on its page as Pele's block renderer draws it: everything moved under the
 *              title and clear of the padding, the composites, blocks and arrows with their text, the edges' lines and marks.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

import CoreGraphics

/// The page of a placed block diagram.
struct BlockLayoutAssembly<Measurer: DiagramTextMeasuring> {
    let diagram: BlockDiagram
    let placement: BlockPlacement
    let edges: BlockEdgePlacement
    var cache: BlockMeasurerCache<Measurer>

    init(diagram: BlockDiagram, placement: BlockPlacement, edges: BlockEdgePlacement, measurers: BlockMeasurers<Measurer>) {
        self.diagram = diagram
        self.placement = placement
        self.edges = edges
        cache = BlockMeasurerCache(measurers: measurers)
    }

    mutating func layout(title: DiagramTextBlock?, font: DiagramFont) -> BlockLayout {
        let extent = edges.extent(contentSize: placement.contentSize, outlines: placement.outlines)
        let padding = BlockLayoutEngine.padding
        let titleHeight = title.map { block in block.size.height + BlockLayoutEngine.titleGap } ?? 0
        let inner = max(extent.width, title?.size.width ?? 0)
        let offset = CGVector(dx: padding - extent.minX + (inner - extent.width) / 2, dy: padding + titleHeight - extent.minY)
        let size = CGSize(width: (inner + 2 * padding).rounded(.up), height: (extent.height + titleHeight + 2 * padding).rounded(.up))
        var composites: [BlockLayoutComposite] = []
        var nodes: [BlockLayoutNode] = []
        for index in placement.cells.indices.dropFirst() {
            let view = placement.views[index]
            let identifier = diagram.blocks[view.blockIndex].identifier
            switch view.kind {
            case .space: continue
            case .composite:
                let cell = placement.cells[index]
                let frame = CGRect(x: cell.center.x - cell.width / 2 + offset.dx, y: cell.center.y - cell.height / 2 + offset.dy, width: cell.width, height: cell.height)
                let titleCenter = placement.titleCenter(of: index).translated(by: offset)
                composites.append(BlockLayoutComposite(identifier: identifier, frame: frame, title: view.text.map { text in PlaneMapLabel.placed(text, at: titleCenter) },
                                                       appearance: view.appearance))
            case .leaf, .arrow: nodes.append(node(at: index, identifier: identifier, offset: offset))
            }
        }
        let placedTitle = title.map { block in PlaneMapLabel.placed(block, at: CGPoint(x: size.width / 2, y: padding + block.size.height / 2)) }
        return BlockLayout(size: size, font: font, title: placedTitle, composites: composites, nodes: nodes, edges: edgeLayouts(offset: offset))
    }

    /// A block or an arrow on the page. A block spanning columns whose text wrapped is wrapped again in its wider cell,
    /// the shape and the routes left as they were, as Pele reuses the room.
    private mutating func node(at index: Int, identifier: String, offset: CGVector) -> BlockLayoutNode {
        let view = placement.views[index]
        let cell = placement.cells[index]
        let center = cell.center.translated(by: offset)
        let drawn = view.drawnSize
        var text = view.text
        let keepsOwnSize = if case .leaf(let shape) = view.kind { BlockViews.keepsOwnSize.contains(shape) } else { false }
        if let measured = view.text, cell.span > 1, measured.size.width > 0, measured.lineCount > 1, drawn.width > cell.neededWidth, !keepsOwnSize {
            let room = measured.size.width + (drawn.width - cell.neededWidth)
            text = PlaneMapLabel.block(diagram.blocks[view.blockIndex].label, measurer: cache.measurer(for: view.appearance), maximumWidth: room)
        }
        let frame = CGRect(x: center.x - drawn.width / 2, y: center.y - drawn.height / 2, width: drawn.width, height: drawn.height)
        let form: BlockLayoutNodeForm
        switch view.kind {
        case .arrow(let directions):
            form = .arrow(BlockArrowShape.corners(of: directions, size: drawn).map { corner in CGPoint(x: corner.x + center.x, y: corner.y + center.y) })
        case .leaf(let shape): form = .shape(shape)
        default: form = .shape(.rectangle)
        }
        let textCenter = CGPoint(x: center.x + view.textOffset.dx, y: center.y + view.textOffset.dy)
        return BlockLayoutNode(identifier: identifier, form: form, frame: frame, text: text.map { block in PlaneMapLabel.placed(block, at: textCenter) },
                               appearance: view.appearance)
    }

    /// Each edge's line through its route (or its loop) on the page, cut back for its marks, and its text.
    private func edgeLayouts(offset: CGVector) -> [BlockLayoutEdge] {
        edges.routes.enumerated().map { index, route in
            let edge = diagram.edges[edges.edgeIndices[index]]
            let startTrim = DiagramEdgeMark.lineTrim(for: edge.sourceArrowhead)
            let endTrim = DiagramEdgeMark.lineTrim(for: edge.targetArrowhead)
            let line: BlockEdgeLine
            if route.loopCount > 0 {
                let outline = placement.outlines[edges.ends[index].source]
                let moved = BlockOutline(center: outline.center.translated(by: offset), size: outline.size, form: outline.form)
                line = BlockEdgePaths.loop(on: moved, count: route.loopCount, startTrim: startTrim, endTrim: endTrim)
            } else {
                line = BlockEdgePaths.traced(route.points.map { point in point.translated(by: offset) }, startTrim: startTrim, endTrim: endTrim)
            }
            let text = PlaneMapLabel.block(edge.label, measurer: cache.measurers.edgeText, maximumWidth: BlockLayoutEngine.wrappingWidth)
                .map { block in PlaneMapLabel.placed(block, at: route.textCenter.translated(by: offset)) }
            return BlockLayoutEdge(identifier: edge.identifier, path: line.path,
                                   sourceMark: Self.mark(edge.sourceArrowhead, at: line.start, pointing: line.startDirection),
                                   targetMark: Self.mark(edge.targetArrowhead, at: line.end, pointing: line.endDirection),
                                   isThick: edge.isThick, isDotted: edge.isDotted, text: text)
        }
    }

    private static func mark(_ arrowhead: FlowchartArrowhead, at tip: CGPoint, pointing direction: CGVector) -> DiagramEdgeMark? {
        arrowhead == .none ? nil : DiagramEdgeMark(arrowhead: arrowhead, tip: tip, direction: direction)
    }
}
