/**
 * File: SwimlaneLayoutEngine.swift
 * --------------------------------
 * Layer: Core
 * Description: Lays a swimlane diagram out as Pele's swimlane variant of its flowchart renderer: the flowchart measured
 *              as a flowchart, its top-level groups lanes, laid out in lanes, drawn as a flowchart inside them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// Lays a swimlane diagram (`swimlane-beta`, read as a flowchart) out as Pele does: collapsed groups folded into nodes
/// (`FlowchartCollapsedGroups`), the nodes measured and shaped as a flowchart's, wrapped at 200 points; the top-level groups
/// lanes and the nodes outside every group one unnamed lane (`SwimlaneGraph`); the whole laid out in lanes
/// (`LaneLayout`), 40 points apart in a rank and 48 points between ranks; and drawn as a flowchart inside its lanes
/// (`SwimlanePageAssembly`). For a narrow column it takes Pele's tight measurements: half the gaps across, three quarters
/// along, text wrapped at 100 points, groups and lanes padded by 12, titles wrapped to the column.
public enum SwimlaneLayoutEngine {
    static let spacing = LayeredSpacing(nodeSeparation: 40, edgeSeparation: 16, rankSeparation: 48)
    static let tightSpacing = LayeredSpacing(nodeSeparation: 20, edgeSeparation: 16, rankSeparation: 36)
    static let wrappingWidth: CGFloat = 200
    static let tightWrappingWidth: CGFloat = 100
    static let padding: CGFloat = 8
    static let titleGap: CGFloat = 12
    /// A text that is not wrapped.
    static let unwrapped: CGFloat = 4000

    /// - Parameter columnWidth: The width of the column a tight layout (`DiagramSpacing.compact`) is for, which its titles
    ///   wrap to, or nil.
    public static func layout(_ diagram: FlowchartDiagram, typography: DiagramTypography, spacing diagramSpacing: DiagramSpacing = .standard,
                              columnWidth: CGFloat? = nil) -> SwimlaneLayout {
        layout(diagram, nodeText: typography.nodeText, edgeText: typography.edgeText, titleText: typography.boldNodeText, font: typography.font,
               isTight: diagramSpacing == .compact, columnWidth: columnWidth)
    }

    static func layout<Measurer: DiagramTextMeasuring>(_ written: FlowchartDiagram, nodeText: Measurer, edgeText: Measurer, titleText: Measurer,
                                                       font: DiagramFont, isTight: Bool, columnWidth: CGFloat? = nil) -> SwimlaneLayout {
        let diagram = FlowchartCollapsedGroups.collapsing(written)
        let measured = FlowchartMeasurement(diagram: diagram, nodeText: nodeText, edgeText: edgeText,
                                            wrappingWidth: isTight ? tightWrappingWidth : wrappingWidth)
        // Pele's room for a title in a column: its width less the page's padding, at least 80 points.
        let titleRoom = isTight ? columnWidth.map { width in max(80, width - 2 * padding) } ?? unwrapped : unwrapped
        let graph = SwimlaneGraph(diagram: diagram, measured: measured, titleText: nodeText, titleWidth: isTight ? max(80, titleRoom / 2) : unwrapped,
                                  isTight: isTight, edgeTextRoom: FlowchartLayoutEngine.edgeTextRoom)
        let placement = LaneLayout.place(graph.graph, spacing: isTight ? tightSpacing : spacing)
        let page = SwimlanePageAssembly(diagram: diagram, measured: measured, graph: graph, placement: placement)
        let title = diagram.title.map { title in DiagramTextBlock(label: DiagramLabel(title), measurer: titleText, maximumWidth: titleRoom) }
        return page.finished(font: font, title: title, padding: padding, titleGap: titleGap)
    }
}
