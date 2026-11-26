/**
 * File: TreeViewReaderEquivalenceTests.swift
 * ------------------------------------------
 * Layer: Tests
 * Description: The tree view reader gives the model 0.7.0's reader gave, or its error with its line, on every corpus
 *              input and spec text, thousands of them changed at random, random tree views written with indentation or
 *              box drawing, and long, many and deep hostile ones.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 26/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class TreeViewReaderEquivalenceTests: XCTestCase {
    private static let tokens = ["treeView-beta", "├── ", "└── ", "│   ", "┣━━ ", "┗━━ ", "┃   ", "─", "│", "src/", "a.ts", "\"quoted name\"", ":::highlight",
                                 " icon(logos:react)", " icon()", " ## a description", "##", "---\nconfig:\n  treeView:\n    filenameIcons:\n      a.ts: ts\n---\n",
                                 "extensionIcons:", "filenameIcons:", "\\u0041", "title A tree", "accDescr {\nline\n}\n"]

    /// Compares the reader with the frozen one on `source`; false when `source` is no tree view.
    @discardableResult
    private func assertReadAsTheReference(_ source: String, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        guard let cursor = MapReadingEquivalence.cursor(of: source, readAs: .treeView) else { return false }
        let read = MapReadingEquivalence.outcome { () throws(MermaidDiagramReadError) in
            ReferenceTreeViewDiagram(try TreeViewParser.parse(cursor, limits: .standard))
        }
        let expected = MapReadingEquivalence.outcome { () throws(MermaidDiagramReadError) in try ReferenceTreeViewParser.parse(cursor, limits: .standard) }
        XCTAssertEqual(read, expected, source, file: file, line: line)
        return true
    }

    func testEveryTextAndItsChangesReadAsTheFrozenReaderReadThem() throws {
        let texts = MapReadingEquivalence.texts(readAs: .treeView, among: try MapReadingEquivalence.everyText(), mutationCount: 150, tokens: Self.tokens,
                                                seed: 0x7EE_5EED)
        var comparedCount = 0
        for text in texts where assertReadAsTheReference(text) { comparedCount += 1 }
        XCTAssertGreaterThan(comparedCount, 2_000)
    }

    func testRandomTreeViewsReadAsTheFrozenReaderReadThem() {
        var random = MapReadingMutations(seed: 0x7EE_0001, tokens: [])
        let names = ["src/", "index.ts", "\"spaced name\"", "README.md", "📦 packages/", "a", "é/", "x y z", ".env", "Dockerfile"]
        let levels = ["│   ", "┃   ", "    ", "\t", "│  ", "│\t", " "]
        let branches = ["├── ", "└── ", "┣━━ ", "┗━━ ", "├─", "└──── ", "├──", "├── \t", "└─ ─ "]
        let extraLines = ["  %% a comment\n", "   \n", "│\n", "│   │\n", "───\n", "  ├\n", "├── \n", "    plain\n", "title t\n", "x\n"]
        let annotations = ["", "", " :::highlight", " icon(logos:react)", " ## entry point", " :::a icon(b) ## c", " icon()", "  ##", " \u{000B}", "\u{000C} "]
        for index in 0..<2_000 {
            let usesBoxDrawing = index % 3 == 0
            var text = index % 5 == 0 ? "---\nconfig:\n  treeView:\n    extensionIcons:\n      .ts: typescript\n---\n" : ""
            text += "treeView-beta\n"
            if index % 7 == 0 { text += "title Tree \(index)\n" }
            for _ in 0..<(1 + random.below(14)) {
                let depth = random.below(5)
                let prefix = usesBoxDrawing
                    ? (0..<depth).map { _ in levels[random.below(levels.count)] }.joined() + branches[random.below(branches.count)]
                    : String(repeating: random.below(6) == 0 ? "\t" : "    ", count: depth + 1)
                text += prefix + names[random.below(names.count)] + annotations[random.below(annotations.count)] + "\n"
                if random.below(9) == 0 { text += extraLines[random.below(extraLines.count)] }
            }
            assertReadAsTheReference(text)
        }
    }

    /// Every pair of lines that may or may not be comment lines or blank, before and after entries: `%%` alone, with a
    /// character more, a directive's `%%{`, after spaces, tabs or Unicode white space, and lines of blanks of each kind.
    func testCommentAndBlankLinesReadAsTheFrozenReaderReadThem() {
        let lines = ["%%", "%%%", "%%{", "%%{x", "%% c", "  %%", "\t%%x", "\u{00A0}%% c", "\u{3000}%%", " \u{2028}%%x", "%", "%x", "", " ", "\t",
                     "\u{00A0}", "\u{3000} ", "\u{000B}", "    a", "  b/", "é", "  🚀", "a %% b"]
        for first in lines {
            for second in lines {
                assertReadAsTheReference("treeView-beta\n    root/\n" + first + "\n" + second + "\n        child\n" + second + "\n" + first)
                assertReadAsTheReference("treeView-beta\n" + first + "\n" + second + "\n    a")
            }
        }
    }

    /// Names and annotations whose bytes and Swift's characters could differ where the byte reading looks: a mark
    /// joining an opening quotation mark, a prepended character (U+0600) before a closing one, a slash or trailing
    /// blanks, Unicode white space at an annotation's ends, and plain ASCII beside them, each with every annotation,
    /// with and without icons shown and icon maps; the byte reading keeps their characters as the String reading did.
    func testNamesAndAnnotationsPastASCIIReadAsTheFrozenReaderReadThem() {
        let names = ["a", "a/", "/", "\"\"", "\"a\"", "\"/\"", "\"\u{301}a\"", "\"a\u{600}\"", "\"\u{600}\"", "\"é/\"", "\"a\u{600}/\"",
                     "a\u{600}/", "\u{600}/", "é/", "a\u{301}/", "a/\u{301}", "a\u{600} ", "a\u{600}\t ", "é ", "a  ", "a\u{301} \t", "\u{1F4E6} x/",
                     "x\u{200D} ", "\"multi\nline\"", "\"a\r\n\"", "a.ts", ".env", "README.md"]
        let annotations = ["", " :::highlight", " :::a", " ::: highlight", " :::highlightx", " icon(none)", " icon()", " icon(folder)", " icon(file)",
                           " icon(mermaid-treeview:folder)", " icon(mermaid-treeview:x)", " icon(a:file)", " ## d", " ##", " ## \u{00A0}d\u{00A0}",
                           " ## \u{3000}", " ##\u{301}d", " ## d\u{600}", " ## é", " ##  \t ", " :::a icon(b) ## c \u{2003}", " ## \u{600} d"]
        let headers = ["", "---\nconfig:\n  treeView:\n    showIcons: true\n---\n",
                       "---\nconfig:\n  treeView:\n    showIcons: true\n    filenameIcons:\n      a.ts: none\n    extensionIcons:\n      .md: folder\n---\n"]
        for header in headers {
            for name in names {
                for annotation in annotations {
                    assertReadAsTheReference(header + "treeView-beta\n    root/\n        " + name + annotation + "\n            " + name + "\n")
                }
            }
        }
    }

    /// Long lines, many entries and deep nesting read as the frozen reader reads them, each in well under a second.
    func testHostileTreeViewsReadAsTheFrozenReaderQuickly() {
        let cases = [
            "treeView-beta\n    " + String(repeating: "a", count: 40_000),
            "treeView-beta\n" + String(repeating: "    entry\n", count: 4_500),
            "treeView-beta\n" + (0..<300).map { depth in String(repeating: " ", count: depth + 1) + "d\(depth)/\n" }.joined(),
            "treeView-beta\n" + String(repeating: "├── a\n│   └── b\n", count: 1_500),
            "treeView-beta\n" + String(repeating: "%% c\n  \n", count: 4_000) + "    x\n",
            "treeView-beta\n    " + String(repeating: "\"", count: 30_000),
        ]
        for source in cases {
            assertReadAsTheReference(source)
            guard let cursor = MapReadingEquivalence.cursor(of: source, readAs: .treeView) else {
                XCTFail("a tree view: \(source.prefix(40))")
                continue
            }
            let start = Date()
            _ = try? TreeViewParser.parse(cursor, limits: .standard)
            XCTAssertLessThan(Date().timeIntervalSince(start), 1, String(source.prefix(40)))
        }
    }
}
