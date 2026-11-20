/**
 * File: UseCaseBoundaryTitles.swift
 * ---------------------------------
 * Layer: Core
 * Description: A use case diagram's system boundary placed as Pele's renderUsecase places it: a box with its title in
 *              the middle of its top, moved clear of the lines that enter there, or a package's tab holding its title.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

enum UseCaseBoundaryTitles {
    /// The room kept inside the box's ends and around the title.
    static let edgeRoom: CGFloat = 6
    /// Between the box's top and its title.
    static let titleMargin: CGFloat = 8

    /// Where lines cross the page's rows: the x of each point of every route, by its y rounded (Pele's `markCrossings`).
    static func crossings(of routes: [LayeredClusterRoute]) -> [Int: [CGFloat]] {
        var crossings: [Int: [CGFloat]] = [:]
        for route in routes {
            for point in route.points where point.y.isFinite { crossings[Int(point.y.rounded()), default: []].append(point.x) }
        }
        return crossings
    }

    /// A boundary's box and its title: a package's in the middle of its tab, others along the top.
    static func boundary(_ view: UseCaseNodeView, frame: CGRect, crossings: [Int: [CGFloat]]) -> UseCaseLayoutBoundary {
        var title = view.label
        let titleSize = title.size
        guard view.node.boundaryType == .package else {
            title.center = CGPoint(x: titleX(frame: frame, width: titleSize.width, crossings: crossings), y: frame.minY + titleMargin + titleSize.height / 2)
            return UseCaseLayoutBoundary(identifier: view.node.identifier, frame: frame, tabFrame: nil, title: title, look: view.look)
        }
        let tabWidth = min(titleSize.width + 2 * UseCaseNodeMeasurement.tabPadding + 8, frame.width)
        let tabHeight = titleSize.height + 2 * UseCaseNodeMeasurement.tabPadding
        title.center = CGPoint(x: frame.minX + tabWidth / 2, y: frame.minY + tabHeight / 2)
        return UseCaseLayoutBoundary(identifier: view.node.identifier, frame: frame,
                                     tabFrame: CGRect(x: frame.minX, y: frame.minY, width: tabWidth, height: tabHeight), title: title, look: view.look)
    }

    /// A boundary's title sits in the middle of its top edge. Where lines enter through that edge it moves into the
    /// stretch between them that is nearest the middle, or the widest if none has room.
    static func titleX(frame: CGRect, width: CGFloat, crossings: [Int: [CGFloat]]) -> CGFloat {
        guard width > 0, let xs = crossings[Int(frame.minY.rounded())] else { return frame.midX }
        let left = frame.minX + edgeRoom
        let right = frame.maxX - edgeRoom
        let cuts = xs.filter { x in x > left && x < right }.sorted() + [right]
        let need = width / 2 + edgeRoom
        var best = frame.midX
        var bestOffset = CGFloat.infinity
        var widest: CGFloat = 0
        var from = left
        for cut in cuts {
            if cut - from >= 2 * need {
                let x = min(max(frame.midX, from + need), cut - need)
                if abs(x - frame.midX) < bestOffset {
                    bestOffset = abs(x - frame.midX)
                    best = x
                }
            } else if bestOffset == .infinity, cut - from > widest {
                widest = cut - from
                best = (from + cut) / 2
            }
            from = cut
        }
        return best
    }
}
