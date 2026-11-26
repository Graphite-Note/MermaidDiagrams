/**
 * File: TreeViewDiagram.swift
 * ---------------------------
 * Layer: Core
 * Description: A Mermaid tree view as its text describes it: its files and folders in the order they are written, each
 *              with its place in the tree and its annotations, kept as records of ranges into its text, and the options
 *              its front matter sets.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 26/11/2026
 */

/// A Mermaid tree view (`treeView-beta`): a tree of files and folders, written by indentation or with box-drawing
/// characters (`├──`, `└──`, `│`), as Mermaid's tree view database holds it. It keeps its entries as flat records of
/// ranges into the text they were read from (`TreeViewEntryRecord`); `entries` and `topLevelIndices` are made from them
/// when read, and two diagrams are equal when those, the titles and the options are.
public struct TreeViewDiagram: Sendable {
    /// The lines after the keyword as the grammar reads them, then the text of any entry field read as a String (one
    /// past ASCII at a place where Swift's characters and the bytes differ): what the records' ranges index.
    var text: [UInt8] = []
    /// The entries in the order they are written, which is depth first: each before its children.
    var records: [TreeViewEntryRecord] = []
    /// The first and last entries at the top of the tree, -1 for none; the others follow `nextSibling`.
    var firstTopLevelIndex: Int32 = -1
    var lastTopLevelIndex: Int32 = -1
    /// The deepest entry's depth, 0 without entries.
    var deepestDepth: Int32 = 0
    /// `title …` in the diagram, else `title:` in the front matter, or nil.
    public internal(set) var title: String?
    /// `accTitle: …`, or nil.
    public internal(set) var accessibilityTitle: String?
    /// `accDescr: …` or `accDescr { … }`, or nil.
    public internal(set) var accessibilityDescription: String?
    public internal(set) var options = TreeViewOptions()

    /// How many entries the tree has.
    public var entryCount: Int { records.count }

    /// The entries in the order they are written, each made from its record when read.
    public var entries: [TreeViewEntry] {
        records.indices.map(entry(at:))
    }

    /// The indexes of the entries at the top of the tree, in order.
    public var topLevelIndices: [Int] {
        siblings(from: firstTopLevelIndex)
    }

    /// Entry `index` made from its record.
    func entry(at index: Int) -> TreeViewEntry {
        let record = records[index]
        return TreeViewEntry(name: string(record.name), isFolder: record.isFolder, depth: Int(record.depth),
                             parentIndex: record.parentIndex < 0 ? nil : Int(record.parentIndex),
                             childIndices: siblings(from: record.firstChildIndex),
                             icon: record.hasIcon ? (record.iconIsNone ? "none" : string(record.icon)) : nil,
                             classes: record.hasClasses ? string(record.classes) : nil,
                             description: record.hasDescription ? string(record.description) : nil)
    }

    /// The entry `first` and its next siblings, in order.
    private func siblings(from first: Int32) -> [Int] {
        var indices: [Int] = []
        var index = first
        while index >= 0 {
            indices.append(Int(index))
            index = records[Int(index)].nextSiblingIndex
        }
        return indices
    }

    /// The text of `range`, a range of `text`.
    func string(_ range: MermaidTextRange) -> String {
        precondition(range.start >= 0 && range.start <= range.end && range.upperBound <= text.count, "tree view range outside its text")
        return String(decoding: text[range.lowerBound..<range.upperBound], as: UTF8.self)
    }
}

extension TreeViewDiagram: Equatable {
    /// Equal when they read as the same tree: the same entries, top level, titles and options, whatever their text holds
    /// besides.
    public static func == (left: TreeViewDiagram, right: TreeViewDiagram) -> Bool {
        left.title == right.title && left.accessibilityTitle == right.accessibilityTitle
            && left.accessibilityDescription == right.accessibilityDescription && left.options == right.options
            && left.entries == right.entries && left.topLevelIndices == right.topLevelIndices
    }
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
/// a value outside its range is left at Pele's default.
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
    /// `filenameIcons` and `extensionIcons`: the icon a file shows by its name or extension when icons are shown.
    public internal(set) var iconMaps = TreeViewIconMaps()

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

    /// The icon an entry shows, or nil, as Pele's getNodeIcon gives it: `icon(none)` none; `icon(folder)` and
    /// `icon(file)` (with or without Mermaid's `mermaid-treeview:` pack) that outline; any other `icon(…)` the outline of
    /// its kind, as no host draws it. Without `icon(…)`, only when the options show icons: a file the maps give `none`
    /// none, a file they give `folder` or `file` that outline, and any other entry the outline of its kind.
    init?(entry: TreeViewEntry, showsIcons: Bool, iconMaps: TreeViewIconMaps = TreeViewIconMaps()) {
        guard let icon = entry.icon else {
            guard showsIcons else { return nil }
            let detected = entry.isFolder ? nil : iconMaps.icon(forFileNamed: entry.name)
            guard detected != "none" else { return nil }
            self.init(named: detected ?? "", isFolder: entry.isFolder)
            return
        }
        guard icon != "none" else { return nil }
        self.init(named: icon, isFolder: entry.isFolder)
    }

    /// The outline an `icon(…)` name gives, nil for `none`.
    init?(icon: String, isFolder: Bool) {
        guard icon != "none" else { return nil }
        self.init(named: icon, isFolder: isFolder)
    }

    /// The outline an `icon(…)` name of ASCII bytes gives, nil for `none`: its characters are its bytes, so it is read
    /// on them as `init(icon:isFolder:)` reads its String.
    init?(asciiIcon icon: ArraySlice<UInt8>, isFolder: Bool) {
        guard !icon.elementsEqual(Self.noneName) else { return nil }
        var builtInName = icon
        if icon.starts(with: Self.builtInPackBytes) {
            builtInName = icon.dropFirst(Self.builtInPackBytes.count)
        } else if icon.contains(MermaidByte.colon) {
            builtInName = []
        }
        if builtInName.elementsEqual(Self.folderName) {
            self = .folder
        } else if builtInName.elementsEqual(Self.fileName) {
            self = .file
        } else {
            self = isFolder ? .folder : .file
        }
    }

    private static let noneName = Array("none".utf8)
    private static let folderName = Array("folder".utf8)
    private static let fileName = Array("file".utf8)
    private static let builtInPackBytes = Array(builtInPack.utf8)

    /// The outline an icon name gives: the built-in one it names, else the entry's kind's.
    private init(named icon: String, isFolder: Bool) {
        let builtInName = icon.hasPrefix(Self.builtInPack) ? String(icon.dropFirst(Self.builtInPack.count)) : icon.contains(":") ? "" : icon
        switch builtInName {
        case "folder": self = .folder
        case "file": self = .file
        default: self = isFolder ? .folder : .file
        }
    }

    /// Mermaid's name for its built-in pack, and its separator.
    static let builtInPack = "mermaid-treeview:"
}

extension TreeViewDiagram: TitledMermaidDiagram {}
