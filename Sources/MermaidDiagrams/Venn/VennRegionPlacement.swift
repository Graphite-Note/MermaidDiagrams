/**
 * File: VennRegionPlacement.swift
 * -------------------------------
 * Layer: Core
 * Description: A Venn diagram's regions placed on the page: the overlaps a style outlines, traced around the placed
 *              circles, and each region's lines around its roomiest point in the colors Pele's ink picks.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

import CoreGraphics

extension VennRegionDrafts {
    /// The overlaps a style gives a property of a shape, in the order of the regions, traced around the placed circles;
    /// an overlap the circles do not share is left out.
    func overlaps(placedCircles: [VennCircle]) -> [VennLayoutOverlap] {
        paintedRegions.compactMap { region in
            VennRegionOutline.shared(by: region.inside.map { index in placedCircles[index] }).map { outline in
                VennLayoutOverlap(sets: region.sets, outline: outline, appearance: region.appearance)
            }
        }
    }

    /// The regions of several sets whose style gives them a look of their own.
    private var paintedRegions: [VennRegionDraft] {
        drafts.filter { region in region.sets.count > 1 && region.appearance.hasShapeDeclaration }
    }

    /// Each region's lines one under the other, centered on its roomiest point scaled and moved by `offset`, each in its
    /// style's color, else the text color picked over the fill under it.
    func placedRegions(scale: Double, offset: CGVector) -> [VennLayoutRegion] {
        let painted = paintedRegions
        return drafts.map { region in
            let total = region.lines.reduce(0) { height, line in height + Double(line.block.size.height) }
            let centerX = region.spot.x * scale + offset.dx
            var top = region.spot.y * scale + offset.dy - total / 2
            let fill = fillUnderText(of: region, painted: painted)
            var lines: [VennLayoutRegionLine] = []
            for line in region.lines {
                let own = line.textIdentifier.map { identifier in appearance(of: [identifier]) } ?? region.appearance
                let height = Double(line.block.size.height)
                let block = PlaneMapLabel.placed(line.block, at: CGPoint(x: centerX, y: top + height / 2))
                lines.append(VennLayoutRegionLine(text: block, isRegionText: line.kind == .regionText, color: own.textColor ?? fill?.ink(forTextOf: own),
                                                  opacity: own.opacity, isBold: own.isBold, isItalic: own.isItalic))
                top += height
            }
            return VennLayoutRegion(sets: region.sets, lines: lines)
        }
    }

    /// The look of the fill under a region's text: the last painted overlap all of whose sets the region holds, else the
    /// region's own circle when its style sets a fill opacity; none for text written across other circles.
    private func fillUnderText(of region: VennRegionDraft, painted: [VennRegionDraft]) -> VennAppearance? {
        if region.isAcross { return nil }
        var fill = region.sets.count == 1 && region.appearance.writesFillOpacity ? region.appearance : nil
        for other in painted where other.sets.allSatisfy(region.sets.contains) { fill = other.appearance }
        return fill
    }
}
