/**
 * File: GitGraphSymbolDrawing.swift
 * ---------------------------------
 * Layer: Core
 * Description: The geometry of a Git graph's commit symbols and their marks, Pele's.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

import CoreGraphics

/// The geometry of commits' symbols, Pele's: a dot 7 points in radius; a square a point wider than the dot on each
/// side with rounded corners; a ring 6 points in radius around a dot of 2.5; and the marks drawn on a dot in the
/// background color, a cross on a reverse commit and a cherry on a cherry-pick. `GitGraphScenePaths` records them.
enum GitGraphSymbolDrawing {
    static let squareCornerRadius: CGFloat = 2
    static let ringRadius: CGFloat = GitGraphGeometry.dotRadius - 1
    static let mergeDotRadius: CGFloat = 2.5
    /// How far each arm of a reverse commit's cross reaches from the center, across and down.
    static let crossReach: CGFloat = 3
    /// The cherry's stem, from the left fruit up to its top and down to the right fruit, from the dot's center.
    static let cherryStemPoints = [CGVector(dx: -2.6, dy: 1), CGVector(dx: 0.8, dy: -4.2), CGVector(dx: 2.6, dy: 1)]
    static let cherryFruitCenters = [CGVector(dx: -2.6, dy: 2.2), CGVector(dx: 2.6, dy: 2.2)]
    static let cherryFruitRadius: CGFloat = 1.8

    /// The square around a circle of `radius` at `center`.
    static func circle(at center: CGPoint, radius: CGFloat) -> CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius)
    }
}
