/**
 * File: IshikawaLayout.swift
 * --------------------------
 * Layer: Core
 * Description: An Ishikawa diagram laid out: across, its spine, head, categories with their bones and causes; or down
 *              for a narrow column, its effect, categories and causes as an indented list; and the title.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// An Ishikawa diagram laid out on a page whose origin is the top left corner and whose y runs down, in points: across
/// as a fishbone (`spine`, `categories`, `head`), or down as an outline (`outlineEntries`, `outlineConnectors`).
public struct IshikawaLayout: Equatable, Sendable {
    public let size: CGSize
    /// The font the text was measured in.
    public let font: DiagramFont
    public let title: DiagramTextBlock?
    /// The spine, from the tail to the head's arrow, or nil when the diagram has no effect or runs down.
    public let spine: DiagramPath?
    /// The arrow where the spine meets the head.
    public let spineArrow: DiagramEdgeMark?
    /// The categories, alternately above and below the spine, in the order written.
    public let categories: [IshikawaLayoutCategory]
    public let head: IshikawaLayoutHead?
    /// Down the page: the effect, the categories and the causes in the order written, each set in by its depth.
    public let outlineEntries: [IshikawaLayoutOutlineEntry]
    /// Down the page: from under each entry's parent down and across to it.
    public let outlineConnectors: [DiagramPath]
}

/// A category with its bones and causes.
public struct IshikawaLayoutCategory: Equatable, Sendable {
    /// Its bone from the spine to its box, then each cause's bone.
    public let bones: [DiagramPath]
    /// The arrow where its bone meets the spine.
    public let arrow: DiagramEdgeMark
    /// Its box at the end of its bone, outlined, with its name.
    public let box: CGRect
    public let label: DiagramTextBlock
    /// Each cause's text, at seven eighths of the size, ending where its bone starts.
    public let causes: [IshikawaLayoutCause]
}

public struct IshikawaLayoutCause: Equatable, Sendable {
    public let text: DiagramTextBlock
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
