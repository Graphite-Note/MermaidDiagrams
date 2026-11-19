/**
 * File: VennLayoutEngine.swift
 * ----------------------------
 * Layer: Core
 * Description: Lays a Venn diagram out as Pele's renderVenn does: the circles placed, a region per set and stated
 *              overlap with its text at its roomiest point, the scale grown until each region holds its text, the page.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics
import Foundation

/// Lays a Venn diagram out in Pele's measurements: the largest circle 100 points in radius, grown up to 1.6 times so
/// that each region's text fits at its roomiest point, a text still too wide wrapped to its region, 8 points of padding
/// and the bold title 12 points above the circles.
public enum VennLayoutEngine {
    /// The radius of the largest circle before it grows: Pele's `RADIUS`.
    static let largestRadius: Double = 100
    /// The most the circles grow to hold their regions' text: Pele's `MAX_GROWTH`.
    static let mostGrowth: Double = 1.6
    static let padding: CGFloat = 8
    static let titleGap: CGFloat = 12
    /// The room a region's text needs past half its diagonal.
    static let textClearance: Double = 4
    /// A region's text wraps at this share of its margin, scaled, but never narrower than `narrowestWrap`.
    static let wrappingShare: Double = 1.8
    static let narrowestWrap: Double = 72
    /// A region with less room than this share of its smallest circle's radius is written across the circles over it.
    static let acrossShare: Double = 0.2

    public static func layout(_ diagram: VennDiagram, typography: DiagramTypography,
                              limits: MermaidDiagramLimits = .standard) throws(VennLayoutError) -> VennLayout {
        try layout(diagram, measurers: VennMeasurers(setText: typography.nodeText, overlapText: typography.edgeText, regionText: typography.rowText,
                                                     titleText: typography.boldNodeText), font: typography.font, limits: limits)
    }

    static func layout<Measurer: DiagramTextMeasuring>(_ diagram: VennDiagram, measurers: VennMeasurers<Measurer>, font: DiagramFont,
                                                       limits: MermaidDiagramLimits) throws(VennLayoutError) -> VennLayout {
        let placement = try VennCirclePlacement(subsets: diagram.subsets, limits: limits)
        var regions = try VennRegionDrafts(diagram: diagram, placement: placement, measurers: measurers, limits: limits)
        let circles = placement.circles
        let largest = circles.map(\.radius).max() ?? 0
        let scale = (largest > 0 ? largestRadius / largest : 1) * regions.growth(scale: largest > 0 ? largestRadius / largest : 1)
        regions.wrapToRooms(scale: scale, measurers: measurers)
        let bounds = Self.bounds(circles: circles, regions: regions.drafts, scale: scale)
        let title = PlaneMapLabel.block(diagram.title, measurer: measurers.titleText)
        let titleHeight = title.map { block in Double(block.size.height + titleGap) } ?? 0
        let titleWidth = Double(title?.size.width ?? 0)
        let inner = max(bounds.width, titleWidth)
        let offset = CGVector(dx: Double(padding) + (inner - bounds.width) / 2 - bounds.minX, dy: Double(padding) + titleHeight - bounds.minY)
        let size = CGSize(width: (inner + 2 * Double(padding)).rounded(.up), height: (bounds.height + titleHeight + 2 * Double(padding)).rounded(.up))
        let placed = circles.map { circle in
            VennCircle(identifier: circle.identifier, x: circle.x * scale + offset.dx, y: circle.y * scale + offset.dy, radius: circle.radius * scale)
        }
        let sets = placed.enumerated().map { index, circle in
            VennLayoutSet(identifier: circle.identifier, center: CGPoint(x: circle.x, y: circle.y), radius: circle.radius, seriesIndex: index,
                          appearance: regions.appearance(of: [circle.identifier]))
        }
        return VennLayout(size: size, font: font, title: title.map { block in PlaneMapLabel.placed(block, at: CGPoint(x: size.width / 2, y: padding + block.size.height / 2)) },
                          sets: sets, overlaps: regions.overlaps(placedCircles: placed),
                          regions: regions.placedRegions(scale: scale, offset: offset))
    }

    /// The circles' extent and the extent of each region's text around its spot, scaled; nothing for no circles.
    private static func bounds(circles: [VennCircle], regions: [VennRegionDraft], scale: Double) -> (minX: Double, minY: Double, width: Double, height: Double) {
        guard !circles.isEmpty else { return (0, 0, 0, 0) }
        var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
        for circle in circles {
            minX = min(minX, (circle.x - circle.radius) * scale)
            minY = min(minY, (circle.y - circle.radius) * scale)
            maxX = max(maxX, (circle.x + circle.radius) * scale)
            maxY = max(maxY, (circle.y + circle.radius) * scale)
        }
        for region in regions {
            let (wide, tall) = region.textExtent
            minX = min(minX, region.spot.x * scale - wide / 2)
            maxX = max(maxX, region.spot.x * scale + wide / 2)
            minY = min(minY, region.spot.y * scale - tall / 2)
            maxY = max(maxY, region.spot.y * scale + tall / 2)
        }
        return (minX, minY, maxX - minX, maxY - minY)
    }
}

/// The measurers of a Venn diagram's text: a set's label, an overlap's, a region's texts, the title in bold.
struct VennMeasurers<Measurer: DiagramTextMeasuring> {
    let setText: Measurer
    let overlapText: Measurer
    let regionText: Measurer
    let titleText: Measurer
}
