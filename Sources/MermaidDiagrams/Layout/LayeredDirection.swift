/**
 * File: LayeredDirection.swift
 * ----------------------------
 * Layer: Core
 * Description: The way the ranks of a layered layout follow each other on the page, and the room inside a box.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.4
 * Date: 25/11/2026
 */

import CoreGraphics

/// The way the ranks of a layout follow each other on a page whose y runs down.
enum LayeredDirection: Equatable, Sendable {
    case topToBottom, bottomToTop, leftToRight, rightToLeft

    /// Whether ranks follow each other down or up the page, rather than across it.
    var runsVertically: Bool { self == .topToBottom || self == .bottomToTop }

    /// The side of a box the flow starts from: the first rank is nearest it.
    var startSide: DiagramSide {
        switch self {
        case .topToBottom: .top
        case .bottomToTop: .bottom
        case .leftToRight: .left
        case .rightToLeft: .right
        }
    }

    /// The side of a box the flow ends at.
    var endSide: DiagramSide {
        switch self {
        case .topToBottom: .bottom
        case .bottomToTop: .top
        case .leftToRight: .right
        case .rightToLeft: .left
        }
    }

    /// An extent on the page as `across` and `along` the ranks.
    func flowSize(of size: CGSize) -> LayeredSize {
        runsVertically ? LayeredSize(across: size.width, along: size.height) : LayeredSize(across: size.height, along: size.width)
    }
}

/// The room inside a box around what it holds, on the page.
struct LayeredClusterPadding: Equatable {
    /// On the left and on the right.
    var side: CGFloat
    /// Above, where the title is.
    var top: CGFloat
    var bottom: CGFloat

    static let none = LayeredClusterPadding(side: 0, top: 0, bottom: 0)
}
