/**
 * File: TreeViewParser.swift
 * --------------------------
 * Layer: Core
 * Description: Reads a tree view's entries, their annotations and its title and accessibility text, and builds its tree
 *              from their indentation, as Mermaid's tree view grammar and database do.
 *
 * Authors: Bahey Shalash
 * Version: 0.6
 * Date: 26/11/2026
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
        try addEntries(of: source, tokens: tokens, from: index, to: &diagram, limits: limits)
        return diagram
    }

    /// The entries whose tokens start at `index`, built into a tree over the token source's bytes.
    private static func addEntries(of source: TreeViewTokenSource, tokens: [TreeViewToken], from index: Int, to diagram: inout TreeViewDiagram,
                                   limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) {
        var index = index
        var tree = TreeViewTreeBuilder(text: source.bytes, options: diagram.options, limits: limits)
        // An entry takes a token or more: room for one per token left is made once.
        tree.reserveCapacity(min(tokens.count - index, limits.maximumNodeCount))
        while index < tokens.count {
            let entry = try source.entry(in: tokens, from: &index)
            try tree.add(entry)
        }
        diagram.text = tree.text
        diagram.records = tree.records
        diagram.firstTopLevelIndex = tree.firstTopLevelIndex
        diagram.lastTopLevelIndex = tree.lastTopLevelIndex
        diagram.deepestDepth = tree.deepestDepth
    }
}
