/**
 * File: VennRegionDrafts.swift
 * ----------------------------
 * Layer: Core
 * Description: A Venn diagram's regions before they are placed on the page, as Pele's renderVenn makes them: one per set
 *              and stated overlap, its style, its roomiest point, and its lines of text measured and wrapped.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

import CoreGraphics
import Foundation

/// A region of the diagram in the layout's units: its sets (each once), their circles, its roomiest point, its lines,
/// its style, and whether its text is written across other circles.
struct VennRegionDraft {
    /// The sets as stated, a set named twice included, which its style is found by.
    let key: [String]
    let sets: [String]
    let inside: [Int]
    let spot: VennRegionSpot
    var lines: [VennRegionLineDraft]
    let appearance: VennAppearance
    let isAcross: Bool

    /// The widest line and the lines' height together.
    var textExtent: (width: Double, height: Double) {
        lines.reduce((0, 0)) { extent, line in (max(extent.0, Double(line.block.size.width)), extent.1 + Double(line.block.size.height)) }
    }
}

/// A line of a region: its text's identifier for one of the region's texts, else nil for the label, its block, and
/// whether it is measured in bold or italic (a label whose region's style asks for it).
struct VennRegionLineDraft {
    let textIdentifier: String?
    let raw: String
    let kind: Kind
    var block: DiagramTextBlock
    var isBold = false
    var isItalic = false

    enum Kind {
        case setLabel
        case overlapLabel
        case regionText
    }
}

/// The regions of a Venn diagram: one per set and stated overlap, a later statement about the same sets replacing an
/// earlier one where it stood; the styles merged by target, later declarations winning.
struct VennRegionDrafts {
    private(set) var drafts: [VennRegionDraft] = []
    private var styles: [[String]: [VennStyleDeclaration]] = [:]

    init<Measurer: DiagramTextMeasuring>(diagram: VennDiagram, placement: VennCirclePlacement, measurers: VennMeasurers<Measurer>,
                                         limits: MermaidDiagramLimits) throws(VennLayoutError) {
        styles = Self.mergedStyles(diagram.styles)
        let neighbors = Self.neighbors(of: placement.circles)
        var keys: [[String]] = []
        var stated: [[String]: VennSubset] = [:]
        for subset in diagram.subsets {
            if stated[subset.sets] == nil { keys.append(subset.sets) }
            stated[subset.sets] = subset
        }
        var work = 0
        var indexByKey: [[String]: Int] = [:]
        for key in keys {
            guard let subset = stated[key],
                  let draft = try Self.draft(of: subset, appearance: appearance(of: key), placement: placement, neighbors: neighbors,
                                             measurers: measurers, work: &work, limits: limits)
            else { continue }
            indexByKey[key] = drafts.count
            drafts.append(draft)
        }
        for text in diagram.texts {
            guard let index = indexByKey[text.sets],
                  let line = Self.line(text.label ?? text.identifier, identifier: text.identifier, kind: .regionText, measurers: measurers) else { continue }
            drafts[index].lines.append(line)
        }
    }

    /// A stated set's or overlap's region: its sets once each, its circles, its roomiest point clear of the other circles
    /// that cut into its smallest (else across them, when they leave less than a fifth of its radius), and its label,
    /// measured in the bold and italic its style writes. The circles weighed are added to `work`, which the layout limit
    /// bounds.
    private static func draft<Measurer: DiagramTextMeasuring>(of subset: VennSubset, appearance: VennAppearance, placement: VennCirclePlacement,
                                                              neighbors: [[Int]],
                                                              measurers: VennMeasurers<Measurer>, work: inout Int,
                                                              limits: MermaidDiagramLimits) throws(VennLayoutError) -> VennRegionDraft? {
        let circles = placement.circles
        var seen: Set<String> = []
        let sets = subset.sets.filter { identifier in seen.insert(identifier).inserted }
        let inside = sets.compactMap { identifier in placement.indexByIdentifier[identifier] }
        guard let first = inside.first else { return nil }
        let smallest = inside.reduce(first) { smallest, index in circles[index].radius < circles[smallest].radius ? index : smallest }
        let within = Set(inside)
        let others = neighbors[smallest].filter { index in !within.contains(index) }
        work += inside.count + others.count
        guard work <= limits.maximumLayoutPointCount else { throw .tooManyOverlaps(limit: limits.maximumLayoutPointCount) }
        var spot = VennRegionSpot.find(in: circles, inside: inside, outside: others)
        let isAcross = !others.isEmpty && spot.margin < circles[smallest].radius * VennLayoutEngine.acrossShare
        if isAcross { spot = VennRegionSpot.find(in: circles, inside: inside, outside: []) }
        var lines: [VennRegionLineDraft] = []
        if let text = subset.label ?? (subset.sets.count == 1 ? subset.sets[0] : nil),
           let line = line(text, identifier: nil, kind: sets.count == 1 ? .setLabel : .overlapLabel, isBold: appearance.isBold,
                           isItalic: appearance.isItalic, measurers: measurers) {
            lines.append(line)
        }
        return VennRegionDraft(key: subset.sets, sets: sets, inside: inside, spot: spot, lines: lines, appearance: appearance, isAcross: isAcross)
    }

    /// The look of a target's merged styles.
    func appearance(of key: [String]) -> VennAppearance {
        styles[key].map(VennAppearance.init) ?? VennAppearance()
    }

    /// Each target's declarations, a later one of a property as written replacing an earlier one where it stood.
    private static func mergedStyles(_ styles: [VennStyle]) -> [[String]: [VennStyleDeclaration]] {
        var merged: [[String]: [VennStyleDeclaration]] = [:]
        var placeByProperty: [[String]: [String: Int]] = [:]
        for style in styles {
            var declarations = merged[style.targets] ?? []
            var places = placeByProperty[style.targets] ?? [:]
            for declaration in style.declarations {
                if let index = places[declaration.property] {
                    declarations[index] = declaration
                } else {
                    places[declaration.property] = declarations.count
                    declarations.append(declaration)
                }
            }
            merged[style.targets] = declarations
            placeByProperty[style.targets] = places
        }
        return merged
    }

    /// The circles that overlap each circle: only those can cut into a region of it.
    private static func neighbors(of circles: [VennCircle]) -> [[Int]] {
        var neighbors = [[Int]](repeating: [], count: circles.count)
        for first in circles.indices {
            for second in circles.indices where second > first
                && hypot(circles[first].x - circles[second].x, circles[first].y - circles[second].y) < circles[first].radius + circles[second].radius {
                neighbors[first].append(second)
                neighbors[second].append(first)
            }
        }
        return neighbors
    }

    private static func line<Measurer: DiagramTextMeasuring>(_ raw: String, identifier: String?, kind: VennRegionLineDraft.Kind, isBold: Bool = false,
                                                             isItalic: Bool = false, measurers: VennMeasurers<Measurer>) -> VennRegionLineDraft? {
        let measurer = measurers.measurer(for: kind, isBold: isBold, isItalic: isItalic)
        guard let block = PlaneMapLabel.block(raw, measurer: measurer) else { return nil }
        return VennRegionLineDraft(textIdentifier: identifier, raw: raw, kind: kind, block: block, isBold: isBold, isItalic: isItalic)
    }

    /// How much the circles grow, at `scale`, for every region with room to hold its text: at most 1.6.
    func growth(scale: Double) -> Double {
        var growth = 1.0
        for region in drafts where region.spot.margin > 0 {
            let (width, height) = region.textExtent
            let need = hypot(width, height) / 2 + VennLayoutEngine.textClearance
            growth = max(growth, min(need / (region.spot.margin * scale), VennLayoutEngine.mostGrowth))
        }
        return growth
    }

    /// Each line still wider than its region's room wrapped to it.
    mutating func wrapToRooms<Measurer: DiagramTextMeasuring>(scale: Double, measurers: VennMeasurers<Measurer>) {
        for regionIndex in drafts.indices {
            let room = max(drafts[regionIndex].spot.margin * scale * VennLayoutEngine.wrappingShare, VennLayoutEngine.narrowestWrap)
            for lineIndex in drafts[regionIndex].lines.indices where Double(drafts[regionIndex].lines[lineIndex].block.size.width) > room {
                let line = drafts[regionIndex].lines[lineIndex]
                let measurer = measurers.measurer(for: line.kind, isBold: line.isBold, isItalic: line.isItalic)
                if let block = PlaneMapLabel.block(line.raw, measurer: measurer, maximumWidth: CGFloat(room)) {
                    drafts[regionIndex].lines[lineIndex].block = block
                }
            }
        }
    }
}

extension VennMeasurers {
    func measurer(for kind: VennRegionLineDraft.Kind, isBold: Bool, isItalic: Bool) -> Measurer {
        let base = switch kind {
        case .setLabel: setText
        case .overlapLabel: overlapText
        case .regionText: regionText
        }
        return isBold || isItalic ? restyled(base, isBold, isItalic) : base
    }
}
