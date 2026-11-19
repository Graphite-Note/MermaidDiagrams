/**
 * File: MermaidDiagramAccessibility.swift
 * ---------------------------------------
 * Layer: Core
 * Description: What a screen reader says of a prepared diagram: its label, the title or the type's name, and its value,
 *              the description or a summary of what it shows.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// What a screen reader says of a diagram: its title, else the type's name, then its description, else a summary of
/// what it shows (the nodes' text, the slices with their shares, each message), as the reading view says it.
public struct MermaidDiagramAccessibility: Equatable, Sendable {
    /// `accTitle`, else the diagram's title, else nil.
    public let title: String?
    /// `accDescr`, or nil.
    public let description: String?
    /// What the diagram shows, part by part, in the order it is written.
    public let summary: [String]
    /// What the summary's parts are joined with: a comma for names, a semicolon for parts that hold commas.
    public let summarySeparator: String
    let kind: MermaidDiagramKind

    init(kind: MermaidDiagramKind, title: String?, description: String?, summary: [String], summarySeparator: String = ", ") {
        self.kind = kind
        self.title = title
        self.description = description
        self.summary = summary
        self.summarySeparator = summarySeparator
    }

    /// The title, else the type's name (`MermaidDiagramKind.spokenName`).
    public var label: String {
        title ?? kind.spokenName
    }

    /// The description, else the summary.
    public var value: String {
        description ?? summary.joined(separator: summarySeparator)
    }
}
