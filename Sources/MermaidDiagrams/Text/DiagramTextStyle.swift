/**
 * File: DiagramTextStyle.swift
 * ----------------------------
 * Layer: Core
 * Description: The emphasis of a piece of a label (bold, italic, monospaced), as Pele's spans carry it, and a piece of a
 *              line in one emphasis with its measured width.
 *
 * Authors: Bahey Shalash
 * Version: 0.5
 * Date: 23/11/2026
 */

import CoreGraphics

/// The emphasis of a piece of text beyond the font its whole text is drawn in: Markdown's `**bold**` and `*italic*`,
/// HTML's `<b>`, `<strong>`, `<i>`, `<em>`, `<cite>`, `<dfn>`, `<var>`, and `<code>`, `<kbd>`, `<samp>`, `<tt>` in the
/// system's monospaced font, as Pele's `Style` bits mark a span (text/measurer.ts).
public struct DiagramTextStyle: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let bold = DiagramTextStyle(rawValue: 1 << 0)
    public static let italic = DiagramTextStyle(rawValue: 1 << 1)
    public static let monospaced = DiagramTextStyle(rawValue: 1 << 2)
}

/// A piece of one line of text in one emphasis, as Pele's `Span`: its characters, its emphasis beyond the text's own
/// (`DiagramSceneText.isBold` and the others), and its width measured in that emphasis. A line's runs follow each other
/// from the line's start, each `width` after the one before.
public struct DiagramTextRun: Equatable, Sendable {
    public let text: String
    public let style: DiagramTextStyle
    public let width: CGFloat

    public init(text: String, style: DiagramTextStyle, width: CGFloat) {
        self.text = text
        self.style = style
        self.width = width
    }
}

/// A piece of a label's line in one emphasis, before it is measured.
struct DiagramLabelSpan: Equatable, Sendable {
    var text: String
    let style: DiagramTextStyle
}
