/**
 * File: DiagramEdgeMark.swift
 * ---------------------------
 * Layer: Core
 * Description: The mark at an end of an edge (an arrow, a circle, a cross): its kind, its tip and the way it points, and
 *              how much of the line it takes; plain numbers that a layout's flat records hold.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.2
 * Date: 26/11/2026
 */

import CoreGraphics

/// The mark at an end of an edge: its kind, the point it touches the node at, and the unit direction it points in.
public struct DiagramEdgeMark: Equatable, Sendable, BitwiseCopyable {
    public let arrowhead: FlowchartArrowhead
    public let tip: CGPoint
    public let direction: CGVector

    /// The length of an arrow, and the part of an edge's line its mark takes, in points: Pele's.
    static let arrowLength: CGFloat = 8
    static func lineTrim(for arrowhead: FlowchartArrowhead) -> CGFloat {
        switch arrowhead {
        case .none: 0
        case .arrow: arrowLength - 1
        case .circle: arrowLength
        case .cross: 4
        }
    }
}

extension DiagramEdgeMark {
    func translated(by offset: CGVector) -> DiagramEdgeMark {
        DiagramEdgeMark(arrowhead: arrowhead, tip: tip.translated(by: offset), direction: direction)
    }
}
