/**
 * File: ReferenceSwimlaneLayoutEngine.swift
 * -----------------------------------------
 * Layer: Tests
 * Description: The 0.7.0 SwimlaneLayoutEngine kept as the reference the swimlane layout is checked against: the flowchart
 *              measured, its graph made, laid out in lanes by the reference lane layout, and put on the page; fitted to a
 *              column by laying each fitting out whole.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// Lays a swimlane diagram (`swimlane-beta`, read as a flowchart) out as Pele does: collapsed groups folded into nodes
/// (`FlowchartCollapsedGroups`), the nodes measured and shaped as a flowchart's, wrapped at 200 points; the top-level groups
/// lanes and the nodes outside every group one unnamed lane (`ReferenceSwimlaneGraph`); the whole laid out in lanes
/// (`LaneLayout`), 40 points apart in a rank and 48 points between ranks; and drawn as a flowchart inside its lanes
/// (`ReferenceSwimlanePageAssembly`). For a narrow column it takes Pele's tight measurements: half the gaps across, three quarters
/// along, text wrapped at 100 points, groups and lanes padded by 12, titles wrapped to the column.
enum ReferenceSwimlaneLayoutEngine {
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
    static func layout(_ diagram: FlowchartDiagram, typography: DiagramTypography, spacing diagramSpacing: DiagramSpacing = .standard,
                              columnWidth: CGFloat? = nil) -> SwimlaneLayout {
        layout(diagram, nodeText: typography.nodeText, edgeText: typography.edgeText, titleText: typography.boldNodeText, font: typography.font,
               isTight: diagramSpacing == .compact, columnWidth: columnWidth)
    }

    /// The diagram for a container `availableWidth` wide (nil for none), as Pele fits its flowchart variant: one that runs
    /// across is turned to run down (`swimlaneTurnedToRunDown`) when it does not fit a container under 640 points and
    /// turned is narrower (`turnToFit`); either way it takes the tight measurements when it does not fit and tight is
    /// narrower (`tighten`).
    static func layout(_ diagram: FlowchartDiagram, typography: DiagramTypography, availableWidth: CGFloat?) -> SwimlaneLayout {
        func fitted(_ diagram: FlowchartDiagram) -> SwimlaneLayout {
            DiagramWidthFitting.tighten(availableWidth: availableWidth, width: { (layout: SwimlaneLayout) in layout.size.width }) { isTight in
                layout(diagram, typography: typography, spacing: isTight ? .compact : .standard, columnWidth: availableWidth)
            }
        }
        guard let turned = diagram.swimlaneTurnedToRunDown else { return fitted(diagram) }
        return DiagramWidthFitting.turnToFit(availableWidth: availableWidth, width: { (layout: SwimlaneLayout) in layout.size.width }) { isDown in
            fitted(isDown ? turned : diagram)
        }
    }

    static func layout<Measurer: DiagramTextMeasuring>(_ written: FlowchartDiagram, nodeText: Measurer, edgeText: Measurer, titleText: Measurer,
                                                       font: DiagramFont, isTight: Bool, columnWidth: CGFloat? = nil) -> SwimlaneLayout {
        let diagram = FlowchartCollapsedGroups.collapsing(written)
        let measured = FlowchartMeasurement(diagram: diagram, nodeText: nodeText, edgeText: edgeText,
                                            wrappingWidth: isTight ? tightWrappingWidth : wrappingWidth)
        // Pele's room for a title in a column: its width less the page's padding, at least 80 points.
        let titleRoom = isTight ? columnWidth.map { width in max(80, width - 2 * padding) } ?? unwrapped : unwrapped
        let graph = ReferenceSwimlaneGraph(diagram: diagram, measured: measured, titleText: nodeText, titleWidth: isTight ? max(80, titleRoom / 2) : unwrapped,
                                  isTight: isTight, edgeTextRoom: FlowchartLayoutEngine.edgeTextRoom)
        let placement = ReferenceLaneLayout.place(graph.graph, spacing: isTight ? tightSpacing : spacing)
        let page = ReferenceSwimlanePageAssembly(diagram: diagram, measured: measured, graph: graph, placement: placement)
        let title = diagram.title.map { title in DiagramTextBlock(label: DiagramLabel(title), measurer: titleText, maximumWidth: titleRoom) }
        return page.finished(font: font, title: title, padding: padding, titleGap: titleGap)
    }
}
