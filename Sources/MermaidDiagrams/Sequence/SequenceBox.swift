/**
 * File: SequenceBox.swift
 * -----------------------
 * Layer: Core
 * Description: A sequence diagram's `box … end`: participants grouped under a title, behind a background in the color
 *              the box's line names first.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// `box Aqua Front end … end`: the participants declared between the two lines drawn in a background reaching from
/// above their boxes to below them, its title at its top.
public struct SequenceBox: Equatable, Sendable {
    /// The text after the color, or nil when the box has none.
    public let title: DiagramLabel?
    /// Whether the title wraps to the width Mermaid gives it (`wrap:` before it).
    public let wrapsTitle: Bool
    /// The color the line starts with (`box Aqua …`, `box rgb(…) …`), or nil for Pele's default shade: no color,
    /// `transparent`, or a CSS keyword that names no color of its own (`inherit`, `canvas`, …).
    public let color: SequenceHighlightColor?
}
