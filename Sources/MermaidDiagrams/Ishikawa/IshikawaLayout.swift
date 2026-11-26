/**
 * File: IshikawaLayout.swift
 * --------------------------
 * Layer: Core
 * Description: An Ishikawa diagram laid out: across, its spine, head, categories with their bones and causes; or down
 *              for a narrow column, its effect, categories and causes as an indented list; and the title.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 26/11/2026
 */

import CoreGraphics

/// An Ishikawa diagram laid out on a page whose origin is the top left corner and whose y runs down, in points: across
/// as a fishbone (`spine`, `categories`, `head`), or down as an outline (`outlineEntries`, `outlineConnectors`). The
/// fishbone's categories, causes and head are kept as flat records of measured texts (`IshikawaFishboneRecords`);
/// `categories` and `head` are made from them when read.
public struct IshikawaLayout: Sendable {
    public let size: CGSize
    /// The font the text was measured in.
    public let font: DiagramFont
    public let title: DiagramTextBlock?
    /// The spine, from the tail to the head's arrow, or nil when the diagram has no effect or runs down.
    public let spine: DiagramPath?
    /// The arrow where the spine meets the head.
    public let spineArrow: DiagramEdgeMark?
    /// The fishbone's categories, causes and head, none when the diagram runs down.
    let fishbone: IshikawaFishboneRecords
    /// Down the page: the effect, the categories and the causes in the order written, each set in by its depth.
    public let outlineEntries: [IshikawaLayoutOutlineEntry]
    /// Down the page: from under each entry's parent down and across to it.
    public let outlineConnectors: [DiagramPath]

    /// The categories, alternately above and below the spine, in the order written.
    public var categories: [IshikawaLayoutCategory] {
        fishbone.categories
    }

    public var head: IshikawaLayoutHead? {
        fishbone.head
    }
}

extension IshikawaLayout: Equatable {
    /// Equal when they draw the same: the same size, font, title, spine, categories, head and outline.
    public static func == (left: IshikawaLayout, right: IshikawaLayout) -> Bool {
        left.size == right.size && left.font == right.font && left.title == right.title && left.spine == right.spine
            && left.spineArrow == right.spineArrow && left.categories == right.categories && left.head == right.head
            && left.outlineEntries == right.outlineEntries && left.outlineConnectors == right.outlineConnectors
    }
}

/// A category with its bones and causes.
public struct IshikawaLayoutCategory: Equatable, Sendable {
    /// Its bone from the spine to its box, then each cause's bone, each a straight line.
    var boneLines: [IshikawaBoneLine]
    /// The arrow where its bone meets the spine.
    public internal(set) var arrow: DiagramEdgeMark
    /// Its box at the end of its bone, outlined, with its name.
    public internal(set) var box: CGRect
    public internal(set) var label: DiagramTextBlock
    /// Each cause's text, at seven eighths of the size, ending where its bone starts.
    public internal(set) var causes: [IshikawaLayoutCause]

    /// Its bone from the spine to its box, then each cause's bone, made as paths when read.
    public var bones: [DiagramPath] {
        boneLines.map { line in DiagramPath(start: line.start, segments: [.line(to: line.end)]) }
    }
}

/// A bone: a straight line from `start` to `end`.
struct IshikawaBoneLine: Equatable, Sendable {
    var start: CGPoint
    var end: CGPoint
}

public struct IshikawaLayoutCause: Equatable, Sendable {
    public internal(set) var text: DiagramTextBlock
    /// A cause of a cause, drawn muted.
    public let isMuted: Bool
}

/// The effect: a box flat on the spine's side and round on the other, with its name in bold.
public struct IshikawaLayoutHead: Equatable, Sendable {
    public let frame: CGRect
    public let label: DiagramTextBlock
}

public struct IshikawaLayoutOutlineEntry: Equatable, Sendable {
    /// 0 for the effect, 1 for a category, more for a cause.
    public let depth: Int
    /// The entry's box, outlined for the effect and the categories, the room its text takes for a cause.
    public let frame: CGRect
    /// Its name, bold for the effect and the categories.
    public let text: DiagramTextBlock

    /// The radius of the box's corners: the effect's are rounder.
    public var cornerRadius: CGFloat {
        depth == 0 ? 12 : 4
    }

    public var isFramed: Bool {
        depth < 2
    }
}
