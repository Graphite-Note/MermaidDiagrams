/**
 * File: TreeViewParser.swift
 * --------------------------
 * Layer: Core
 * Description: Reads a tree view's entries, their annotations and its title and accessibility text, and builds its tree
 *              from their indentation, as Mermaid's tree view grammar and database do.
 *
 * Authors: Bahey Shalash
 * Version: 0.5
 * Date: 24/11/2026
 */

import Foundation

/// Reads a tree view after its `treeView-beta` keyword, which ends its line, as Pele's tree view parser reads it: the
/// text drawn with box-drawing characters turned into indentation first (`TreeViewBoxDrawingReader`), then `title`,
/// `accTitle` and `accDescr` before the entries, then each entry: its indentation, its name (quoted, or bare to the end
/// of its line or the annotations), and its annotations (`:::class`, `icon(name)`, `## description`). A name ending
/// with `/` is a folder. An entry's parent is the last entry before it indented less.
enum TreeViewParser {
    static func parse(_ cursor: MermaidTextCursor, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> TreeViewDiagram {
        // Mermaid's lexer takes a keyword with anything after it on its line, blanks too, as a name.
        if let byte = cursor.peek(), byte != MermaidByte.newline, !(byte == MermaidByte.carriageReturn && cursor.peek(1) == MermaidByte.newline) {
            throw .invalidSyntax(line: cursor.line, problem: .treeViewExpectedName(cursor.excerpt()))
        }
        let source: TreeViewTokenSource
        if let read = try TreeViewByteLines.tokenSource(after: cursor.line, in: cursor.bytes, from: cursor.position) {
            source = read
        } else {
            let text = cursor.text(from: cursor.position, to: cursor.bytes.count)
            source = TreeViewTokenSource(lines: Array(try TreeViewBoxDrawingReader.lines(after: cursor.line, in: text).dropFirst()))
        }
        var tokenizer = TreeViewTokenizer(bytes: source.bytes)
        let tokens: [TreeViewToken]
        switch tokenizer.tokens() {
        case .success(let read): tokens = read
        case .failure(let failure): throw .invalidSyntax(line: source.writtenLine(at: failure.offset), problem: .unexpectedText(source.excerpt(at: failure.offset)))
        }
        var diagram = TreeViewDiagram()
        diagram.options = TreeViewOptions(MermaidConfigurationOptions(section: "treeView", in: cursor))
        diagram.options.iconMaps = TreeViewIconMaps(frontMatterOf: cursor.sourceBytes)
        var index = 0
        while index < tokens.count, let statement = source.headerStatement(tokens[index]) {
            switch statement {
            case .title(let title): diagram.title = title
            case .accessibilityTitle(let title): diagram.accessibilityTitle = title
            case .accessibilityDescription(let description): diagram.accessibilityDescription = description
            }
            index += 1
        }
        var tree = TreeViewTreeBuilder(limits: limits)
        // An entry takes a token or more: room for one per token left is made once.
        tree.reserveCapacity(min(tokens.count - index, limits.maximumNodeCount))
        while index < tokens.count {
            let entry = try source.entry(in: tokens, from: &index)
            try tree.add(entry)
        }
        diagram.entries = tree.entries
        diagram.topLevelIndices = tree.topLevelIndices
        return diagram
    }
}

/// An entry as written: its indentation, its name and its annotations.
struct TreeViewWrittenEntry {
    var indentation = 0
    var name = ""
    var classes: String?
    var icon: String?
    var description: String?
}

/// Builds the tree as Mermaid's database does: an entry's parent is the last entry before it indented less.
struct TreeViewTreeBuilder {
    private(set) var entries: [TreeViewEntry] = []
    private(set) var topLevelIndices: [Int] = []
    private let limits: MermaidDiagramLimits
    /// The entries that can still take children, by strictly increasing indentation.
    private var openEntries: [(index: Int, indentation: Int)] = []

    init(limits: MermaidDiagramLimits) {
        self.limits = limits
    }

    mutating func reserveCapacity(_ entryCount: Int) {
        entries.reserveCapacity(entryCount)
        openEntries.reserveCapacity(min(entryCount, Self.typicalDepth))
    }

    /// Deeper than most trees are written.
    private static let typicalDepth = 16

    mutating func add(_ written: TreeViewWrittenEntry) throws(MermaidDiagramReadError) {
        guard entries.count < limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
        while let last = openEntries.last, written.indentation <= last.indentation { openEntries.removeLast() }
        let parentIndex = openEntries.last?.index
        let isFolder = written.name.hasSuffix("/")
        let index = entries.count
        entries.append(TreeViewEntry(name: isFolder ? String(written.name.dropLast()) : written.name, isFolder: isFolder, depth: openEntries.count,
                                     parentIndex: parentIndex, icon: written.icon.map { icon in icon.isEmpty ? "none" : icon },
                                     classes: written.classes.flatMap { classes in classes.isEmpty ? nil : classes },
                                     description: written.description.flatMap { description in description.isEmpty ? nil : description }))
        if let parentIndex { entries[parentIndex].childIndices.append(index) } else { topLevelIndices.append(index) }
        openEntries.append((index, written.indentation))
    }
}
