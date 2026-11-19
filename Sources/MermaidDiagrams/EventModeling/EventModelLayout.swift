/**
 * File: EventModelLayout.swift
 * ----------------------------
 * Layer: Core
 * Description: An event model laid out as Pele lays it out: across, its lanes as bands and its frames along them, or
 *              down a narrow column, a card per frame under its lane's name; the relations' lines, the notes and
 *              specifications' cards, the title.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// An event model laid out on a page whose origin is the top left and whose y runs down, in points. Across, time runs
/// to the right through bands, one per lane, the lanes' names at their left; down, for a narrow column, each frame is a
/// card under its lane's name, one below the other, the relations that skip a card running on rails at the right.
/// The notes and specifications are cards below. Drawing it needs only colors.
public struct EventModelLayout: Equatable, Sendable {
    public let size: CGSize
    /// The font the text was measured in; each block is drawn in it at its own size, a frame's data in the system's
    /// monospaced font.
    public let font: DiagramFont
    /// Whether it runs down a narrow column, as Pele turns an event model that does not fit.
    public let runsDown: Bool
    public let title: DiagramTextBlock?
    /// Across, one band per lane, top to bottom; down, none.
    public let laneBands: [CGRect]
    /// The lanes' names, bold in the muted color: across, one per band; down, one per frame, above its card, each
    /// line a block of its own that starts at the card's text.
    public let laneNames: [DiagramTextBlock]
    public let relations: [EventModelLayoutRelation]
    public let frames: [EventModelLayoutFrame]
    /// The notes, then the specifications.
    public let cards: [EventModelLayoutCard]
}

/// A frame's box: its kind's series color (none for a user interface, drawn plain), its name, its number in the narrow
/// layout, and its data, each line a block of its own that starts at the box's text.
public struct EventModelLayoutFrame: Equatable, Sendable {
    public let frame: CGRect
    public let kind: EventModelEntityKind
    public let isReset: Bool
    /// Pele's series slot of the kind: a command 0, an event 1, a read model 2, a processor 6, a user interface none.
    public let seriesIndex: Int?
    /// Whether the box is outlined in the border color under its series color, as the narrow layout draws every box.
    public let isOutlinedInBorder: Bool
    public let name: DiagramTextBlock
    /// The frame's number at its top right, in the narrow layout; nil across.
    public let number: DiagramTextBlock?
    public let dataLines: [DiagramTextBlock]
}

/// A relation's line and the arrow at its target.
public struct EventModelLayoutRelation: Equatable, Sendable {
    public let path: DiagramPath
    public let arrow: DiagramEdgeMark
}

/// A note's or a specification's card: its heading and its lines, each a block of its own that starts at the card's text.
public struct EventModelLayoutCard: Equatable, Sendable {
    public let frame: CGRect
    public let isSpecification: Bool
    public let heading: DiagramTextBlock
    public let lines: [DiagramTextBlock]
}
