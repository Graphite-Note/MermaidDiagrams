/**
 * File: RailroadLayout.swift
 * --------------------------
 * Layer: Core
 * Description: A railroad diagram laid out as Pele lays it out: per rule its name, its track of lines and quarter turns,
 *              the arrows on its loops and folds, the dots at its ends, and its boxes with their text.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// A railroad diagram laid out on a page whose origin is the top left and whose y runs down, in points: the title,
/// then each rule below the one before, its name above its track. Drawing it needs only colors.
public struct RailroadLayout: Equatable, Sendable {
    public let size: CGSize
    /// The font the text was measured in; terminals are drawn in the system's monospaced font, special sequences in
    /// italics.
    public let font: DiagramFont
    public let title: DiagramTextBlock?
    public let rules: [RailroadLayoutRule]
    /// The width of the track and of the boxes' outlines.
    public let lineWidth: CGFloat
    /// The radius of the dots at a track's ends; zero when the options hide them.
    public let markerRadius: CGFloat
    /// Whether it was laid out with Pele's tighter gaps and turns for a narrow column, long sequences folded into rows.
    public let isTight: Bool
}

/// A rule's drawing.
public struct RailroadLayoutRule: Equatable, Sendable {
    /// Its name, bold, starting at the page's padding.
    public let name: DiagramTextBlock
    /// The track's pieces, each a line from a point, with quarter turns as curves.
    public let track: [DiagramPath]
    /// The arrows on loops (pointing back) and where a folded sequence enters its next row.
    public let arrows: [RailroadLayoutArrow]
    /// The centers of the dots where the track starts and ends.
    public let markerCenters: [CGPoint]
    public let boxes: [RailroadLayoutBox]
    /// The counts under repetitions (`2×`, `≥3×`, `≤4×`, `2–4×`), in the muted color.
    public let counts: [DiagramTextBlock]
}

/// A filled triangle: its tip and the two ends of its base.
public struct RailroadLayoutArrow: Equatable, Sendable {
    public let points: [CGPoint]
}

/// A box on the track: a terminal in a pill on the surface color, its text in the monospaced font; a name of a rule in
/// a rounded box; a special sequence in a dashed one, its text in italics between a muted `? ` and ` ?`.
public struct RailroadLayoutBox: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case terminal
        case nonterminal
        case special
    }

    public let kind: Kind
    public let frame: CGRect
    public let text: DiagramTextBlock
    /// A special sequence's `? ` and ` ?`, in the muted color; empty for the others.
    public let questionMarks: [DiagramTextBlock]
}
