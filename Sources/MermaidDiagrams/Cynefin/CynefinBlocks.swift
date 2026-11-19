/**
 * File: CynefinBlocks.swift
 * -------------------------
 * Layer: Core
 * Description: A Cynefin domain's block measured as Pele's render.ts measures it: its name, its decision model and
 *              practice, and its items as badges, at most three in confusion and a badge for the rest.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// The measurers of a Cynefin framework's text: domains' names and the title in bold, subtitles in italic, items, and
/// transitions' labels.
struct CynefinMeasurers<Measurer: DiagramTextMeasuring> {
    let nameText: Measurer
    let subtitleText: Measurer
    let itemText: Measurer
    let labelText: Measurer
}

/// A domain's block before it is placed: its measured texts and badges and its size.
struct CynefinBlockDraft {
    let domain: CynefinDomain
    let name: DiagramTextBlock
    let subtitles: [DiagramTextBlock]
    let badges: [Badge]
    let size: CGSize

    /// An item's measured text and the size of its box.
    struct Badge {
        let text: DiagramTextBlock
        let size: CGSize
        let isOverflow: Bool
    }

    /// Confusion shows at most this many items, and a badge for the rest.
    static let mostConfusionItems = 3
    /// An item's text wraps past this width: Pele's `ITEM_MAX_WIDTH`.
    static let itemWrappingWidth: CGFloat = 200
    static let itemHorizontalPadding: CGFloat = 10
    static let itemVerticalPadding: CGFloat = 4
    /// Between two items, and between the subtitles and the first item.
    static let itemGap: CGFloat = 6
    static let headingGap: CGFloat = 10
    /// An item's least line, one and a half times its size, rounded.
    static let itemLineRatio: CGFloat = 1.5

    init<Measurer: DiagramTextMeasuring>(domain: CynefinDomain, items: [String], showsDescriptions: Bool, measurers: CynefinMeasurers<Measurer>) {
        self.domain = domain
        name = PlaneMapLabel.block(domain.name, measurer: measurers.nameText) ?? DiagramTextBlock(label: DiagramLabel(domain.name), measurer: measurers.nameText,
                                                                                                    maximumWidth: PlaneMapLabel.unwrappedWidth)
        subtitles = showsDescriptions ? [domain.decisionModel, domain.practice].compactMap { text in PlaneMapLabel.block(text, measurer: measurers.subtitleText) } : []
        let shownCount = domain == .confusion ? min(items.count, Self.mostConfusionItems) : items.count
        var badges = items.prefix(shownCount).map { item in Self.badge(item, isOverflow: false, measurer: measurers.itemText) }
        if shownCount < items.count { badges.append(Self.badge("+\(items.count - shownCount) more", isOverflow: true, measurer: measurers.itemText)) }
        self.badges = badges
        var width = name.size.width
        var height = name.size.height
        for subtitle in subtitles {
            width = max(width, subtitle.size.width)
            height += subtitle.size.height
        }
        if !badges.isEmpty { height += Self.headingGap - Self.itemGap }
        for badge in badges {
            width = max(width, badge.size.width)
            height += Self.itemGap + badge.size.height
        }
        size = CGSize(width: width, height: height)
    }

    /// An item's text wrapped at 200 points, in a box 10 points wider each side and 4 points taller each way than its
    /// text, or its least line.
    private static func badge<Measurer: DiagramTextMeasuring>(_ text: String, isOverflow: Bool, measurer: Measurer) -> Badge {
        let block = PlaneMapLabel.block(text, measurer: measurer, maximumWidth: itemWrappingWidth)
            ?? DiagramTextBlock(label: DiagramLabel(lines: []), measurer: measurer, maximumWidth: itemWrappingWidth)
        let leastLine = (measurer.fontSize * itemLineRatio).rounded()
        return Badge(text: block, size: CGSize(width: block.size.width + 2 * itemHorizontalPadding,
                                               height: max(block.size.height, leastLine) + 2 * itemVerticalPadding), isOverflow: isOverflow)
    }

    /// The block centered at `center`: its texts one under the other from its top, each badge's box and text.
    func placed(at center: CGPoint) -> CynefinLayoutBlock {
        var top = center.y - size.height / 2
        let placedName = PlaneMapLabel.placed(name, at: CGPoint(x: center.x, y: top + name.size.height / 2))
        top += name.size.height
        var placedSubtitles: [DiagramTextBlock] = []
        for subtitle in subtitles {
            placedSubtitles.append(PlaneMapLabel.placed(subtitle, at: CGPoint(x: center.x, y: top + subtitle.size.height / 2)))
            top += subtitle.size.height
        }
        top += Self.headingGap - Self.itemGap
        var placedBadges: [CynefinLayoutBadge] = []
        for badge in badges {
            top += Self.itemGap
            let frame = CGRect(x: center.x - badge.size.width / 2, y: top, width: badge.size.width, height: badge.size.height)
            placedBadges.append(CynefinLayoutBadge(frame: frame, text: PlaneMapLabel.placed(badge.text, at: CGPoint(x: frame.midX, y: frame.midY)),
                                                   isOverflow: badge.isOverflow))
            top += badge.size.height
        }
        return CynefinLayoutBlock(domain: domain, name: placedName, subtitles: placedSubtitles, badges: placedBadges,
                                  frame: CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height))
    }
}
