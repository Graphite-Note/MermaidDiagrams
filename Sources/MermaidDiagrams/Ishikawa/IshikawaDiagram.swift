/**
 * File: IshikawaDiagram.swift
 * ---------------------------
 * Layer: Core
 * Description: A Mermaid Ishikawa (fishbone) diagram as its text describes it: the effect, its categories of causes and
 *              their causes, nested by indentation.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// A Mermaid Ishikawa diagram (`ishikawa-beta`, `ishikawa`): the first line is the effect, the fish's head; the lines
/// after it are causes, nested by their indentation relative to the first cause, so the effect may be indented more than
/// the causes. The effect's children are the categories, theirs the causes, and so on as deep as the text goes.
public struct IshikawaDiagram: Equatable, Sendable {
    /// The effect first, then the causes in the order they are written, which is depth first. Empty when the text names none.
    public internal(set) var nodes: [IshikawaNode] = []
    /// `title:` in the front matter, or nil: the diagram has no title statement.
    public internal(set) var title: String?
}

/// The effect or a cause.
public struct IshikawaNode: Equatable, Sendable {
    /// The line's text without the blanks around it.
    public let text: String
    /// The index of its parent in `IshikawaDiagram.nodes`, nil for the effect.
    public let parentIndex: Int?
    public internal(set) var childIndices: [Int] = []
}

extension IshikawaDiagram: TitledMermaidDiagram {}
