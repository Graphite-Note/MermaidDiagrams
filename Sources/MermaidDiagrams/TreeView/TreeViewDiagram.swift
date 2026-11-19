/**
 * File: TreeViewDiagram.swift
 * ---------------------------
 * Layer: Core
 * Description: A Mermaid tree view as its text describes it: its files and folders in the order they are written, each
 *              with its place in the tree and its annotations, and the options its front matter sets.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// A Mermaid tree view (`treeView-beta`): a tree of files and folders, written by indentation or with box-drawing
/// characters (`├──`, `└──`, `│`), as Mermaid's tree view database holds it.
public struct TreeViewDiagram: Equatable, Sendable {
    /// The entries in the order they are written, which is depth first: each before its children.
    public internal(set) var entries: [TreeViewEntry] = []
    /// `title …` in the diagram, else `title:` in the front matter, or nil.
    public internal(set) var title: String?
    /// `accTitle: …`, or nil.
    public internal(set) var accessibilityTitle: String?
    /// `accDescr: …` or `accDescr { … }`, or nil.
    public internal(set) var accessibilityDescription: String?
    public internal(set) var options = TreeViewOptions()

    /// The indexes of the entries at the top of the tree, in order.
    public internal(set) var topLevelIndices: [Int] = []
}

/// A file or folder of a tree view.
public struct TreeViewEntry: Equatable, Sendable {
    /// The name as written, without the `/` that makes it a folder.
    public let name: String
    public let isFolder: Bool
    /// How deep in the tree it is: 0 at the top.
    public let depth: Int
    public let parentIndex: Int?
    public internal(set) var childIndices: [Int] = []
    /// `icon(name)` as written, `none` for `icon()` and `icon(none)`, or nil.
    public let icon: String?
    /// `:::class`, or nil.
    public let classes: String?
    /// `## description`, or nil.
    public let description: String?

    /// Whether `:::highlight` is among its classes, which Pele marks with a band in the accent color.
    public var isHighlighted: Bool {
        classes?.split(whereSeparator: \.isWhitespace).contains("highlight") ?? false
    }
}

/// A tree view's options from its front matter (`config:` then `treeView:`) and its directives, as Pele applies them:
/// a value outside its range is left at Pele's default. The maps of icons by file name and extension are not read.
public struct TreeViewOptions: Equatable, Sendable {
    /// Across and down around an entry's row.
    public internal(set) var paddingAcross: Double = 5
    public internal(set) var paddingDown: Double = 2
    /// How far each level is set in, before the padding across.
    public internal(set) var rowIndent: Double = 15
    /// The width of the guide lines.
    public internal(set) var lineThickness: Double = 1
    /// `showIcons`: every entry shows a file or folder icon, not only those with `icon(…)`.
    public internal(set) var showsIcons = false

    init() {}

    init(_ options: MermaidConfigurationOptions) {
        paddingAcross = Self.number(options.values["paddingX"], within: 0...100) ?? paddingAcross
        paddingDown = Self.number(options.values["paddingY"], within: 0...100) ?? paddingDown
        rowIndent = Self.number(options.values["rowIndent"], within: 0...400) ?? rowIndent
        lineThickness = Self.number(options.values["lineThickness"], within: 0.25...12) ?? lineThickness
        switch options.values["showIcons"] {
        case .boolean(let shows): showsIcons = shows
        case .number(let number): showsIcons = number != 0 && !number.isNaN
        case .text(let text): showsIcons = !text.isEmpty
        case .collection: showsIcons = true
        case nil: showsIcons = false
        }
    }

    private static func number(_ value: MermaidConfigurationOptions.Value?, within range: ClosedRange<Double>) -> Double? {
        guard case .number(let number) = value, range.contains(number) else { return nil }
        return number
    }
}

/// The icon Pele draws for an entry without its host's icons: the built-in file or folder outline.
public enum TreeViewGlyph: Equatable, Sendable {
    case file
    case folder

    /// The icon an entry shows, or nil: `icon(none)` none; `icon(folder)` and `icon(file)` (with or without Mermaid's
    /// `mermaid-treeview:` pack) that outline; any other `icon(…)` the outline of its kind, as no host draws it; without
    /// `icon(…)`, the outline of its kind when the options show icons.
    init?(entry: TreeViewEntry, showsIcons: Bool) {
        guard let icon = entry.icon else {
            guard showsIcons else { return nil }
            self = entry.isFolder ? .folder : .file
            return
        }
        guard icon != "none" else { return nil }
        let builtInName = icon.hasPrefix(Self.builtInPack) ? String(icon.dropFirst(Self.builtInPack.count)) : icon.contains(":") ? "" : icon
        switch builtInName {
        case "folder": self = .folder
        case "file": self = .file
        default: self = entry.isFolder ? .folder : .file
        }
    }

    /// Mermaid's name for its built-in pack, and its separator.
    static let builtInPack = "mermaid-treeview:"
}

extension TreeViewDiagram: TitledMermaidDiagram {}
