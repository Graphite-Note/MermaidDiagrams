/**
 * File: InfoDiagramParser.swift
 * -----------------------------
 * Layer: Core
 * Description: Reads an info diagram's statements after its `info` keyword.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// Reads what follows the `info` keyword as Mermaid's grammar does: line breaks, `showInfo` once, then `title …`,
/// `accTitle: …`, `accDescr: …` or `accDescr { … }`, each ending its line. `%%` starts a comment.
enum InfoDiagramParser {
    static func parse(_ cursor: MermaidTextCursor) throws(MermaidDiagramReadError) -> InfoDiagram {
        var cursor = cursor
        var statements = MermaidTitleStatements()
        MermaidTitleStatements.skipBlank(&cursor)
        if PieChartStatementText.isAtKeyword(showInfo, cursor) { cursor.advance(by: showInfo.count) }
        while true {
            MermaidTitleStatements.skipBlank(&cursor)
            if cursor.isAtEnd { break }
            guard try statements.read(&cursor) else { throw .invalidSyntax(line: cursor.line, problem: .unexpectedText(cursor.excerpt())) }
            try MermaidTitleStatements.expectLineEnd(&cursor)
        }
        return InfoDiagram(title: statements.title, accessibilityTitle: statements.accessibilityTitle,
                           accessibilityDescription: statements.accessibilityDescription)
    }

    private static let showInfo = Array("showInfo".utf8)
}
