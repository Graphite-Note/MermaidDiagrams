/**
 * File: TreemapDiagram.swift
 * --------------------------
 * Layer: Core
 * Description: A Mermaid treemap as its text describes it: sections and leaves in an outline, their classes and titles.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

/// A Mermaid treemap (`treemap`, `treemap-beta`): an outline of quoted names, a leaf (`"Name": value`) sized by its value, a
/// section (`"Name"`) holding the rows indented more than it, as many levels as the text nests. The nodes are kept in the
/// order they are written, each after its parent; a row belongs to the nearest section above it that is indented less.
public struct TreemapDiagram: Equatable, Sendable {
    public internal(set) var nodes: [TreemapNode]
    /// What each class a `classDef` names sets, by the class's name: the look of the nodes that name it (`:::name`).
    public internal(set) var classStyles: [String: DiagramElementStyle]
    /// What each class sets of its nodes' text (`font-size`, `font-weight`, `font-style`), by the class's name.
    public internal(set) var classTextStyles: [String: TreemapClassTextStyle] = [:]
    /// The options its front matter and directives set.
    public internal(set) var options = TreemapOptions()
    /// `title …` in the treemap, else `title:` in the front matter, or nil.
    public internal(set) var title: String?
    /// `accTitle: …`, the short name a screen reader gives the treemap, or nil.
    public internal(set) var accessibilityTitle: String?
    /// `accDescr: …` or `accDescr { … }`, the longer description a screen reader reads, or nil.
    public internal(set) var accessibilityDescription: String?
    /// Style declarations of `classDef` statements read and not applied (an opacity, a font family, a font size in `em`): the
    /// drawing may differ from Obsidian's.
    public internal(set) var unappliedStatementCount: Int

    init(nodes: [TreemapNode] = [], classStyles: [String: DiagramElementStyle] = [:], title: String? = nil, accessibilityTitle: String? = nil,
         accessibilityDescription: String? = nil, unappliedStatementCount: Int = 0) {
        self.nodes = nodes
        self.classStyles = classStyles
        self.title = title
        self.accessibilityTitle = accessibilityTitle
        self.accessibilityDescription = accessibilityDescription
        self.unappliedStatementCount = unappliedStatementCount
    }
}

/// One row of a treemap: a section, or a leaf with its value.
public struct TreemapNode: Equatable, Sendable {
    /// The text between the quotation marks, as written (entity codes not yet read).
    public let name: String
    /// A leaf's value as written; nil when it is not a number (`_`, `.`). A section has none.
    public let value: Double?
    public let isSection: Bool
    /// The index in the diagram's nodes of the section that holds the node, or nil for a top-level node.
    public let parentIndex: Int?
    /// The class the row names with `:::`, or nil.
    public let className: String?

    init(name: String, value: Double?, isSection: Bool, parentIndex: Int?, className: String?) {
        self.name = name
        self.value = value
        self.isSection = isSection
        self.parentIndex = parentIndex
        self.className = className
    }

    /// What a leaf adds to its area: its value when that is a finite number above zero, else nothing; a section's own is 0.
    var size: Double {
        guard !isSection, let value, value.isFinite, value > 0 else { return 0 }
        return value
    }
}
