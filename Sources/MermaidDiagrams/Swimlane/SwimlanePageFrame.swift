/**
 * File: SwimlanePageFrame.swift
 * -----------------------------
 * Layer: Core
 * Description: The page a swimlane diagram's lanes are put on, known once they are placed: its size, the title above
 *              them and how far everything moves inside it; and the finished layout, its nodes, groups and lanes moved
 *              onto that page.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics

/// The page around a swimlane diagram's placed lanes, as Pele frames a flowchart: the lanes' extent moved `padding` inside
/// the page, below the title and centered under it when the title is wider.
struct SwimlanePageFrame {
    let size: CGSize
    /// How far everything the lane layout placed moves onto the page.
    let offset: CGVector
    /// The title, centered above the lanes, or nil.
    let title: DiagramTextBlock?

    init(placementSize: CGSize, title: DiagramTextBlock?, padding: CGFloat, titleGap: CGFloat) {
        let titleSize = title?.size ?? .zero
        let titleHeight = title == nil ? 0 : titleSize.height + titleGap
        let innerWidth = max(placementSize.width, titleSize.width)
        offset = CGVector(dx: padding + (innerWidth - placementSize.width) / 2, dy: padding + titleHeight)
        let size = CGSize(width: (innerWidth + 2 * padding).rounded(.up), height: (placementSize.height + titleHeight + 2 * padding).rounded(.up))
        self.size = size
        var placedTitle = title
        placedTitle?.center = CGPoint(x: size.width / 2, y: padding + titleSize.height / 2)
        self.title = placedTitle
    }
}

extension SwimlanePageAssembly {
    /// The finished layout: the nodes, the edges (already on the page), the groups inside lanes and the lanes, on the page.
    func finished(font: DiagramFont) -> SwimlaneLayout {
        let offset = page.offset
        var nodes: [FlowchartLayoutNode] = []
        nodes.reserveCapacity(diagram.nodeCount)
        for node in 0..<diagram.nodeCount where graph.nesting.representedSubgraphs[node] < 0 { nodes.append(placedNode(node).translated(by: offset)) }
        let flowchart = FlowchartLayout(size: page.size, font: font, nodes: nodes, edges: placedEdges, title: page.title,
                                        clusters: groupsInsideLanes().map { cluster in cluster.translated(by: offset) })
        return SwimlaneLayout(flowchart: flowchart, lanes: lanes().map { lane in lane.translated(by: offset) })
    }

    private func placedNode(_ node: Int) -> FlowchartLayoutNode {
        let frame = placement.frames[graph.nodeBoxes[node]]
        let center = CGPoint(x: frame.midX, y: frame.midY)
        var text = measured.nodeTexts[node]
        text.center = CGPoint(x: center.x, y: center.y + measured.textOffsets[node])
        let size = measured.shapeSizes[node]
        return FlowchartLayoutNode(shape: diagram.nodeShape(at: node),
                                   frame: CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height),
                                   text: text, style: diagram.nodeStyle(at: node), asset: diagram.nodeAsset(at: node))
    }

    /// The groups inside lanes, each title along its box's top, clear of the edges where it can be, their depths counted from
    /// the lane they are in.
    private func groupsInsideLanes() -> [FlowchartLayoutCluster] {
        guard graph.nesting.hasGroupInsideLane else { return [] }
        let crossings = FlowchartRoutePointIndex(routePoints)
        return (0..<diagram.subgraphCount).compactMap { subgraph in
            guard graph.nesting.subgraphParents[subgraph] >= 0 else { return nil }
            let frame = placement.frames[graph.subgraphBoxes[subgraph]]
            let title = graph.titles[subgraph].map { title in FlowchartClusterTitles.placed(title, in: frame, crossings: crossings) }
            return FlowchartLayoutCluster(frame: frame, title: title?.title, depth: graph.nesting.subgraphDepths[subgraph] - 1,
                                          isTitleCrossed: title?.isCrossed ?? false)
        }
    }

    /// The lanes in the order they are placed, each title centered in the band at its start, turned where the flow runs across.
    private func lanes() -> [SwimlaneLayoutLane] {
        let isTurned = diagram.direction.runsAcross
        let depth = placement.laneTitleDepth
        return placement.lanes.map { box in
            let frame = placement.frames[box]
            let band = isTurned ? CGRect(x: frame.minX, y: frame.minY, width: depth, height: frame.height)
                                : CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: depth)
            let subgraph = graph.subgraphBoxes.firstIndex(of: box)
            let title = subgraph.flatMap { subgraph in Self.centered(graph.titles[subgraph], at: CGPoint(x: band.midX, y: band.midY)) }
            return SwimlaneLayoutLane(frame: frame, titleBand: band, title: title, isTitleTurned: isTurned)
        }
    }
}
