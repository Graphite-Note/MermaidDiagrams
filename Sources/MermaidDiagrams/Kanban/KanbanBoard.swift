/**
 * File: KanbanBoard.swift
 * -----------------------
 * Layer: Core
 * Description: A Mermaid kanban board as its text describes it: its columns in order, each with its cards and their
 *              metadata, and the options its front matter sets.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import Foundation

/// A Mermaid kanban board (`kanban`): columns side by side, each with its cards, as Mermaid's database holds them. The
/// first node written is a column, and so is every later node indented as far as it; a node indented more is a card of
/// the column before it.
public struct KanbanBoard: Equatable, Sendable {
    public internal(set) var columns: [KanbanColumn] = []
    /// `title:` in the front matter, or nil: a kanban board has no title statement.
    public internal(set) var title: String?
    /// `::icon(…)` and `:::class` decorations, and icons in metadata, read and not drawn: Pele draws an icon only from its
    /// host's icons, which take no room when the host has none, and classes only a style sheet applies.
    public internal(set) var unappliedDecorationCount = 0
    public internal(set) var options = KanbanOptions()
}

/// A column of a kanban board: its title and its cards in order.
public struct KanbanColumn: Equatable, Sendable {
    /// The identifier written before the column's delimiters, or its text when it has none.
    public let identifier: String
    /// Its title: the text written, or the metadata's `label`, read as Markdown.
    public internal(set) var label: DiagramLabel
    public internal(set) var cards: [KanbanCard] = []
}

/// A card of a kanban board, with what its metadata (`@{ ticket: MC-1, assigned: knsv, priority: 'High' }`) gives it.
public struct KanbanCard: Equatable, Sendable {
    public let identifier: String
    /// The text written, or the metadata's `label`, read as Markdown.
    public let label: DiagramLabel
    /// The metadata's `ticket`, or nil.
    public let ticket: String?
    /// The metadata's `assigned`, or nil.
    public let assignee: String?
    /// The metadata's `priority`, by Mermaid's five names in any case, or nil for none, `Medium` or another name.
    public let priority: KanbanPriority?
}

/// Mermaid's priorities that Pele marks on a card: the high ones in the critical color, the low ones muted, the
/// nearer to `Medium` the fainter. `Medium` has no mark.
public enum KanbanPriority: String, Equatable, Sendable, CaseIterable {
    case veryHigh = "very high"
    case high
    case low
    case veryLow = "very low"

    /// The priority a card's `priority` names, its spaces at either end and its case not counted, or nil.
    init?(written: String) {
        self.init(rawValue: written.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}

/// A kanban board's options from its front matter (`config:` then `kanban:`) and its directives, as Pele applies them.
public struct KanbanOptions: Equatable, Sendable {
    /// `sectionWidth`, the width of a column, from 80 to 2,000 points: 200 unless a positive number sets it.
    public internal(set) var columnWidth: Double = 200
    /// Whether `ticketBaseUrl` is set: a card's ticket is then a link, drawn in the accent color.
    public internal(set) var linksTickets = false

    static let narrowestColumnWidth = 80.0
    static let widestColumnWidth = 2_000.0

    init() {}

    init(_ options: MermaidConfigurationOptions) {
        if case .number(let width) = options.values["sectionWidth"], width > 0 {
            columnWidth = min(max(width, Self.narrowestColumnWidth), Self.widestColumnWidth)
        }
        if case .text(let address) = options.values["ticketBaseUrl"], !address.isEmpty { linksTickets = true }
    }
}

extension KanbanBoard: TitledMermaidDiagram {}
