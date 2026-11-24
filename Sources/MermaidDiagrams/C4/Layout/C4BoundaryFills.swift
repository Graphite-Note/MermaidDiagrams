/**
 * File: C4BoundaryFills.swift
 * ---------------------------
 * Layer: Core
 * Description: How a C4 relation is painted over the boundaries a style fills, as Pele's svg/edges.ts decides it: in
 *              the text color picked for the fill it lies on, or cased in the page's color where it crosses a border.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 24/11/2026
 */

import CoreGraphics

/// A boundary a style fills: its frame and its look.
struct C4BoundaryFill {
    let frame: CGRect
    let look: C4ElementLook
}

/// Pele's `fillUnder`, `edgeInk` and `overFills` for C4 relations.
enum C4BoundaryFills {
    /// The line's color and whether it is cased. Off every fill it keeps its own color. Inside a fill it takes the text
    /// color picked for the fill, unless its style sets a stroke or no color is picked, when it is cased instead, as it is
    /// across a border.
    /// `ownColor` is `C4ElementLook.color(written, property: "stroke")`, read once for the drawing (`C4StyleColors`).
    static func painting(of route: C4Route, lineColor written: String?, ownColor: DiagramColor?,
                         fills: [C4BoundaryFill]) -> (lineColor: DiagramColor?, isCased: Bool) {
        // Off every fill when there is none, as the placement finds it, without the lists it is asked with.
        guard !fills.isEmpty else { return (ownColor, false) }
        switch DiagramFillPlacement.placement(of: route.path, tips: [route.start, route.end], among: fills.map(\.frame)) {
        case .onNone: return (ownColor, false)
        case .acrossBorder: return (ownColor, true)
        case .inside(let place):
            if C4ElementLook.isWritten(written) { return (ownColor, true) }
            guard let ink = fills[place].look.inkForLines else { return (nil, true) }
            return (ink, false)
        }
    }
}
