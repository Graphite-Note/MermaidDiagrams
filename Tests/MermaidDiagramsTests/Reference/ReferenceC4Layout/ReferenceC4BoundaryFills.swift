/**
 * File: ReferenceC4BoundaryFills.swift
 * ------------------------------------
 * Layer: Tests
 * Description: The 0.7.0 (de81532) C4 layout kept as the reference the flat C4 layout is checked against. How a C4
 *              relation is painted over the boundaries a style fills, as Pele's svg/edges.ts decides it: in the text
 *              color picked for the fill it lies on, or cased in the page's color where it crosses a border.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// A boundary a style fills: its frame and its look.
struct ReferenceC4BoundaryFill {
    let frame: CGRect
    let look: C4ElementLook
}

/// Pele's `fillUnder`, `edgeInk` and `overFills` for C4 relations.
enum ReferenceC4BoundaryFills {
    /// The line's color and whether it is cased. Off every fill it keeps its own color. Inside a fill it takes the text
    /// color picked for the fill, unless its style sets a stroke or no color is picked, when it is cased instead, as it is
    /// across a border.
    static func painting(of route: ReferenceC4Route, lineColor written: String?, fills: [ReferenceC4BoundaryFill]) -> (lineColor: DiagramColor?, isCased: Bool) {
        let ownColor = C4ElementLook.color(written, property: "stroke")
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
