/**
 * File: ReferenceFlowchartFlowAxes.swift
 * --------------------------------------
 * Layer: Tests
 * Description: The 0.7.0 FlowchartFlowAxes kept as the reference the 0.8.0 flowchart layout is checked against: how a
 *              flowchart's direction maps flow space onto the page.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// How a flowchart's direction maps flow space (`across` the ranks as x, `along` the flow as y, from 0) onto the page,
/// whose y runs down.
struct ReferenceFlowchartFlowAxes {
    let direction: FlowchartDirection
    /// The placement's extent along the flow, which a flow that runs up or to the left is mirrored in.
    let alongExtent: CGFloat

    /// Whether ranks follow each other down or up the page.
    var flowIsVertical: Bool { !direction.runsAcross }

    /// A size on the page as `across` and `along`.
    func flowSize(of size: CGSize) -> LayeredSize {
        flowIsVertical ? LayeredSize(across: size.width, along: size.height) : LayeredSize(across: size.height, along: size.width)
    }

    /// A point of flow space on the page.
    func pagePoint(_ flowPoint: CGPoint) -> CGPoint {
        switch direction {
        case .topToBottom: flowPoint
        case .bottomToTop: CGPoint(x: flowPoint.x, y: alongExtent - flowPoint.y)
        case .leftToRight: CGPoint(x: flowPoint.y, y: flowPoint.x)
        case .rightToLeft: CGPoint(x: alongExtent - flowPoint.y, y: flowPoint.x)
        }
    }

    /// The side of a node that faces the ranks after it.
    var downstreamSide: DiagramSide {
        switch direction {
        case .topToBottom: .bottom
        case .bottomToTop: .top
        case .leftToRight: .right
        case .rightToLeft: .left
        }
    }

    /// The side of a node that faces the ranks before it.
    var upstreamSide: DiagramSide {
        switch direction {
        case .topToBottom: .top
        case .bottomToTop: .bottom
        case .leftToRight: .left
        case .rightToLeft: .right
        }
    }

    /// The side across the flow that a node's edges to itself loop out of: its right in a vertical flow, its bottom
    /// in a horizontal one.
    var loopSide: DiagramSide { flowIsVertical ? .right : .bottom }
}
