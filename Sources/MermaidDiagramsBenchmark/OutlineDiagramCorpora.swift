/**
 * File: OutlineDiagramCorpora.swift
 * ---------------------------------
 * Layer: Benchmark
 * Description: The kanban, tree view and Ishikawa inputs of the benchmark and the tests: Mermaid's documentation
 *              examples, as Pele collects them, and generated boards, trees and fishbones.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import Foundation

/// The documentation examples of a type, from the benchmark's resources (`<name>-docs.json`, Pele's `tests/corpus`).
enum DocumentationCorpus {
    static func examples(named name: String) throws -> [String] {
        guard let location = Bundle.module.url(forResource: "\(name)-docs", withExtension: "json", subdirectory: "Resources") else {
            throw FlowchartCorpus.MissingResource()
        }
        return try JSONDecoder().decode([String].self, from: Data(contentsOf: location))
    }
}

/// Mermaid's 3 kanban examples, and boards of columns whose cards carry every kind of metadata.
enum KanbanCorpus {
    static func documentationExamples() throws -> [String] {
        try DocumentationCorpus.examples(named: "kanban")
    }

    /// `columnCount` columns of `cardsPerColumn` cards, every third with a ticket, an assignee and a priority in turn.
    static func board(columnCount: Int, cardsPerColumn: Int) -> String {
        let priorities = ["Very High", "High", "Medium", "Low", "Very Low"]
        var source = "kanban\n"
        for column in 0..<columnCount {
            source += "  column\(column)[Column \(column)]\n"
            for card in 0..<cardsPerColumn {
                let metadata = card % 3 == 0 ? "@{ ticket: T-\(column * 100 + card), assigned: 'person \(card % 4)', priority: '\(priorities[card % 5])' }" : ""
                source += "    card\(column)x\(card)[Card \(card) of column \(column), with some words to wrap]\(metadata)\n"
            }
        }
        return source
    }
}

/// Mermaid's 13 tree view examples, and trees of folders and files in the shape of Pele's generated trees.
enum TreeViewCorpus {
    static func documentationExamples() throws -> [String] {
        try DocumentationCorpus.examples(named: "treeview")
    }

    /// A tree of `entryCount` entries in which each entry's parent is the one `fan` places before it, written with
    /// indentation, every fifth entry with a description and every seventh highlighted.
    static func tree(entryCount: Int, fan: Int = 3) -> String {
        var childrenByEntry = [[Int]](repeating: [], count: entryCount)
        for entry in 1..<max(entryCount, 1) { childrenByEntry[(entry - 1) / fan].append(entry) }
        var source = "treeView-beta\n"
        var pending: [(entry: Int, depth: Int)] = entryCount > 0 ? [(0, 1)] : []
        while let (entry, depth) = pending.popLast() {
            let name = childrenByEntry[entry].isEmpty ? "file\(entry).swift" : "folder\(entry)/"
            let annotations = (entry % 7 == 0 ? " :::highlight" : "") + (entry % 5 == 0 ? " ## entry \(entry)" : "")
            source += String(repeating: "    ", count: depth) + name + annotations + "\n"
            for child in childrenByEntry[entry].reversed() { pending.append((child, depth + 1)) }
        }
        return source
    }
}

/// Mermaid's Ishikawa example, and fishbones of categories with causes nested a few levels deep.
enum IshikawaCorpus {
    static func documentationExamples() throws -> [String] {
        try DocumentationCorpus.examples(named: "ishikawa")
    }

    /// An effect with `categoryCount` categories, each with `causesPerCategory` causes, every other cause with two causes
    /// of its own and the first of those with one more.
    static func fishbone(categoryCount: Int, causesPerCategory: Int) -> String {
        var source = "ishikawa-beta\n    Effect\n"
        for category in 0..<categoryCount {
            source += "    Category \(category)\n"
            for cause in 0..<causesPerCategory {
                source += "        Cause \(category).\(cause)\n"
                guard cause % 2 == 0 else { continue }
                source += "            Reason \(cause) a\n                Deeper reason\n            Reason \(cause) b\n"
            }
        }
        return source
    }
}
