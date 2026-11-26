/**
 * File: TreeViewEntryRecord.swift
 * -------------------------------
 * Layer: Core
 * Description: A tree view's entry as the diagram keeps it, a few numbers and ranges into its text, and the builder
 *              that puts the entries in a tree as Mermaid's database does: an entry's parent is the last entry before
 *              it indented less.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

/// An entry of a tree view: its name and annotations as ranges of the diagram's text, its place in the tree as
/// indexes of other records (-1 for none), and the icon it shows, worked out once when it is read.
struct TreeViewEntryRecord: Equatable, Sendable {
    /// The name as written, without the `/` that makes it a folder.
    var name: MermaidTextRange
    /// `icon(name)`'s name (`hasIcon`), `:::class` (`hasClasses`) and `## description` (`hasDescription`).
    var icon = MermaidTextRange.empty
    var classes = MermaidTextRange.empty
    var description = MermaidTextRange.empty
    var depth: Int32
    var parentIndex: Int32
    var firstChildIndex: Int32 = -1
    var lastChildIndex: Int32 = -1
    var nextSiblingIndex: Int32 = -1
    var isFolder: Bool
    var hasIcon = false
    /// `icon()`: the icon named `none`, which no range of the text holds.
    var iconIsNone = false
    var hasClasses = false
    var hasDescription = false
    /// Whether `highlight` is among its classes, which Pele marks with a band in the accent color.
    var isHighlighted = false
    /// The built-in icon it shows, or nil (`TreeViewGlyph(entry:showsIcons:iconMaps:)`).
    var glyph: TreeViewGlyph?
}

/// A field of an entry as read: a range of the token source's bytes, or, where Swift's characters and the bytes could
/// differ, the String the field's reading made, which the builder copies after the text.
struct TreeViewFieldText {
    var range = MermaidTextRange.empty
    var written: String?
}

/// An entry as written: its indentation, its name and its annotations.
struct TreeViewWrittenFields {
    var indentation = 0
    var name = TreeViewFieldText()
    var isFolder = false
    var classes: TreeViewFieldText?
    var icon: TreeViewFieldText?
    var description: TreeViewFieldText?
}

/// Builds the tree's records over the token source's bytes, which it takes and keeps as the diagram's text.
struct TreeViewTreeBuilder {
    private(set) var text: [UInt8]
    private(set) var records: [TreeViewEntryRecord] = []
    private(set) var firstTopLevelIndex: Int32 = -1
    private(set) var lastTopLevelIndex: Int32 = -1
    private(set) var deepestDepth: Int32 = 0
    private let limits: MermaidDiagramLimits
    private let options: TreeViewOptions
    /// The entries that can still take children, by strictly increasing indentation.
    private var openEntries: [(index: Int32, indentation: Int)] = []

    init(text: [UInt8], options: TreeViewOptions, limits: MermaidDiagramLimits) {
        self.text = text
        self.options = options
        self.limits = limits
    }

    mutating func reserveCapacity(_ entryCount: Int) {
        records.reserveCapacity(entryCount)
        openEntries.reserveCapacity(min(entryCount, Self.typicalDepth))
    }

    /// Deeper than most trees are written.
    private static let typicalDepth = 16

    mutating func add(_ written: TreeViewWrittenFields) throws(MermaidDiagramReadError) {
        guard records.count < limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
        while let last = openEntries.last, written.indentation <= last.indentation { openEntries.removeLast() }
        let parentIndex = openEntries.last?.index ?? -1
        let index = Int32(records.count)
        var record = TreeViewEntryRecord(name: kept(written.name), depth: Int32(openEntries.count), parentIndex: parentIndex,
                                         isFolder: written.isFolder)
        if let icon = written.icon {
            record.hasIcon = true
            record.icon = kept(icon)
            record.iconIsNone = record.icon.isEmpty
        }
        if let classes = written.classes {
            record.classes = kept(classes)
            record.hasClasses = !record.classes.isEmpty
            record.isHighlighted = record.hasClasses && TreeViewEntryText.namesHighlight(text, record.classes)
        }
        if let description = written.description {
            record.description = kept(description)
            record.hasDescription = !record.description.isEmpty
        }
        record.glyph = glyph(of: record)
        deepestDepth = max(deepestDepth, record.depth)
        records.append(record)
        link(index, toParent: parentIndex)
        openEntries.append((index, written.indentation))
    }

    /// Entry `index` added after its parent's last child, or after the last entry at the top.
    private mutating func link(_ index: Int32, toParent parentIndex: Int32) {
        let previous = parentIndex >= 0 ? records[Int(parentIndex)].lastChildIndex : lastTopLevelIndex
        if previous >= 0 {
            records[Int(previous)].nextSiblingIndex = index
        } else if parentIndex >= 0 {
            records[Int(parentIndex)].firstChildIndex = index
        } else {
            firstTopLevelIndex = index
        }
        if parentIndex >= 0 { records[Int(parentIndex)].lastChildIndex = index } else { lastTopLevelIndex = index }
    }

    /// The field's range of the text, its String's bytes copied after the text first when it was read as one.
    private mutating func kept(_ field: TreeViewFieldText) -> MermaidTextRange {
        guard let written = field.written else { return field.range }
        let start = text.count
        text.append(contentsOf: written.utf8)
        return MermaidTextRange(start: start, end: text.count)
    }

    /// The icon the entry shows, as `TreeViewGlyph(entry:showsIcons:iconMaps:)` gives it from the entry's Strings: an
    /// `icon(…)`'s name, which the grammar writes in ASCII, read on its bytes; a file's name looked up in the icon maps
    /// only when the options show icons and the maps hold one.
    private func glyph(of record: TreeViewEntryRecord) -> TreeViewGlyph? {
        if record.hasIcon {
            if record.iconIsNone { return nil }
            let icon = text[record.icon.lowerBound..<record.icon.upperBound]
            guard !icon.contains(where: { byte in byte >= 0x80 }) else {
                return TreeViewGlyph(icon: String(decoding: icon, as: UTF8.self), isFolder: record.isFolder)
            }
            return TreeViewGlyph(asciiIcon: icon, isFolder: record.isFolder)
        }
        guard options.showsIcons else { return nil }
        guard !record.isFolder, !options.iconMaps.isEmpty else { return record.isFolder ? .folder : .file }
        let name = String(decoding: text[record.name.lowerBound..<record.name.upperBound], as: UTF8.self)
        let detected = options.iconMaps.icon(forFileNamed: name)
        guard detected != "none" else { return nil }
        return TreeViewGlyph(icon: detected ?? "", isFolder: false)
    }
}
