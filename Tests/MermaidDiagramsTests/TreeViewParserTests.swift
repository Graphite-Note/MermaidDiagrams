/**
 * File: TreeViewParserTests.swift
 * -------------------------------
 * Layer: Tests
 * Description: A tree view is read as Mermaid reads it: Mermaid 12.1.0's parser, grammar, database and value converter
 *              specs as Pele ports them, its box-drawing preprocessor's spec, and its icons.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

/// Reads a tree view for a test, from its whole text, through `MermaidDiagramReader`.
enum TreeViewReading {
    struct NotATreeView: Error {}

    static func tree(_ source: String, limits: MermaidDiagramLimits = .standard) throws -> TreeViewDiagram {
        guard case .treeView(let tree) = try MermaidDiagramReader.read(source, limits: limits) else { throw NotATreeView() }
        return tree
    }

    static func readError(_ source: String) -> MermaidDiagramReadError? {
        do {
            _ = try MermaidDiagramReader.read(source, limits: .standard)
            return nil
        } catch {
            return error
        }
    }
}

final class TreeViewParserTests: XCTestCase {
    private func entry(_ line: String) throws -> TreeViewEntry {
        try XCTUnwrap(try TreeViewReading.tree("treeView-beta\n" + line).entries.first)
    }

    func testBareAndQuotedNames() throws {
        XCTAssertEqual(try entry("index.js").name, "index.js")
        XCTAssertFalse(try entry("index.js").isFolder)
        let folder = try entry("src/")
        XCTAssertEqual(folder.name, "src")
        XCTAssertTrue(folder.isFolder)
        XCTAssertNil(folder.icon)
        XCTAssertEqual(try entry(".gitignore").name, ".gitignore")
        XCTAssertEqual(try entry("docker-compose.yml").name, "docker-compose.yml")
        XCTAssertEqual(try entry("\"my file.js\"").name, "my file.js")
        let quotedFolder = try entry("'my folder/'")
        XCTAssertEqual(quotedFolder.name, "my folder")
        XCTAssertTrue(quotedFolder.isFolder)
        XCTAssertEqual(try entry("\"\"").name, "")
        XCTAssertEqual(try entry("My Documents/").name, "My Documents")
        XCTAssertEqual(try entry("But  _  _ton💓.tsx").name, "But  _  _ton💓.tsx")
        XCTAssertEqual(try entry("\"But  _  _ton💓.tsx\"").name, "But  _  _ton💓.tsx")
        XCTAssertEqual(try entry("index.js  ").name, "index.js")
    }

    func testAnnotations() throws {
        let annotated = try entry("App.tsx :::highlight icon(logos:react) ## main component")
        XCTAssertEqual(annotated.name, "App.tsx")
        XCTAssertEqual(annotated.classes, "highlight")
        XCTAssertEqual(annotated.icon, "logos:react")
        XCTAssertEqual(annotated.description, "main component")
        XCTAssertTrue(annotated.isHighlighted)
        let quoted = try entry("\"my app.tsx\" :::highlight icon(logos:react) ## main component")
        XCTAssertEqual([quoted.name, quoted.classes, quoted.icon, quoted.description], ["my app.tsx", "highlight", "logos:react", "main component"])
        XCTAssertEqual(try entry("\"my file.js\" :::important").classes, "important")
        XCTAssertEqual(try entry("file.ts :::my-class").classes, "my-class")
        XCTAssertEqual(try entry("data.bin icon(folder)").icon, "folder")
        XCTAssertEqual(try entry("\"my file.js\" ## the main file").description, "the main file")
        XCTAssertNil(try entry("file.txt ##").description)
        let folder = try entry("My Documents/ :::highlight")
        XCTAssertEqual([folder.name, folder.classes], ["My Documents", "highlight"])
        XCTAssertTrue(folder.isFolder)
    }

    func testIconSuppression() throws {
        XCTAssertEqual(try entry("index.js icon(none)").icon, "none")
        XCTAssertEqual(try entry("index.js icon()").icon, "none")
        XCTAssertEqual(try entry("src/ icon(none)").icon, "none")
        let combined = try entry("app.ts icon(none) :::highlight ## entry point")
        XCTAssertEqual([combined.name, combined.icon, combined.classes, combined.description], ["app.ts", "none", "highlight", "entry point"])
        XCTAssertNil(try entry("utils.ts").icon, "Defaults are resolved when laid out")
    }

    func testTheTreeIsBuiltFromIndentationAsMermaidsDatabaseBuildsIt() throws {
        XCTAssertTrue(try TreeViewReading.tree("treeView-beta").entries.isEmpty)
        let tree = try TreeViewReading.tree("treeView-beta\n\"Root\"\n    \"Child1\"\n    \"Child2\"\n        \"Child3\"")
        XCTAssertEqual(tree.entries.map(\.name), ["Root", "Child1", "Child2", "Child3"])
        XCTAssertEqual(tree.entries.map(\.depth), [0, 1, 1, 2])
        XCTAssertEqual(tree.entries.map(\.parentIndex), [nil, 0, 0, 2])
        let deep = try TreeViewReading.tree("treeView-beta\nsrc/\n    components/\n        Button.tsx\n        Header.tsx\n    utils/\n        helpers.ts\nREADME.md")
        XCTAssertEqual(deep.topLevelIndices, [0, 6])
        XCTAssertEqual(deep.entries[0].childIndices, [1, 4])
        XCTAssertEqual(deep.entries[1].childIndices, [2, 3])
        XCTAssertEqual(deep.entries[4].childIndices.map { index in deep.entries[index].name }, ["helpers.ts"])
        XCTAssertEqual(try TreeViewReading.tree("treeView-beta\n%% this is a comment\nindex.js").entries.map(\.name), ["index.js"])
        XCTAssertEqual(try TreeViewReading.tree("treeView-beta\na\n   \n    %% a comment after blanks\n    b").entries.map(\.depth), [0, 1],
                       "A comment line goes with the blank lines before it, as Mermaid's preprocessing removes them")
    }

    func testTitleAndAccessibilityTextComeBeforeTheEntries() throws {
        let tree = try TreeViewReading.tree("treeView-beta\ntitle My TreeView Diagram\naccTitle: Accessible Title\naccDescr: This is an accessible description\n"
                                            + "\"Root\"\n  \"Child\"")
        XCTAssertEqual(tree.title, "My TreeView Diagram")
        XCTAssertEqual(tree.accessibilityTitle, "Accessible Title")
        XCTAssertEqual(tree.accessibilityDescription, "This is an accessible description")
        XCTAssertEqual(tree.entries.count, 2)
        XCTAssertEqual(try TreeViewReading.tree("treeView-beta\naccDescr {\n  Two\n    lines\n}\na").accessibilityDescription, "Two\nlines")
        XCTAssertEqual(try TreeViewReading.tree("---\ntitle: From the front matter\n---\ntreeView-beta\na").title, "From the front matter")
        XCTAssertEqual(try TreeViewReading.tree("treeView-beta\ntitle.txt").entries.map(\.name), ["title.txt"], "A name that starts with title")
    }

    func testWhatTheGrammarRefusesIsATypedErrorWithItsLine() {
        XCTAssertEqual(TreeViewReading.readError("treeView-beta\na\ntitle Late"), .invalidSyntax(line: 3, problem: .treeViewExpectedName("title Late")))
        XCTAssertEqual(TreeViewReading.readError("treeView-beta\na icon(bad name)"), .invalidSyntax(line: 2, problem: .unexpectedText("icon(bad name)")))
        XCTAssertEqual(try TreeViewReading.tree("treeView-beta\na :::").entries.map(\.name), ["a :::"], "No class name: the name runs on")
        XCTAssertEqual(TreeViewReading.readError("treeView-beta extra"), .invalidSyntax(line: 1, problem: .treeViewExpectedName(" extra")))
        XCTAssertEqual(TreeViewReading.readError("treeView-beta\na :::x   \n  b"), .invalidSyntax(line: 3, problem: .treeViewExpectedName("  b")),
                       "Blanks after an annotation are a second indentation, as Mermaid's lexer reads them")
        XCTAssertEqual(TreeViewReading.readError("treeView-beta\nsrc/\n    treeView-beta"), .invalidSyntax(line: 3, problem: .treeViewExpectedName("treeView-beta")),
                       "The keyword again is its token, not a name, as in Pele")
        XCTAssertEqual(TreeViewReading.readError("treeView-beta\na\ntreeView-beta ## note"),
                       .invalidSyntax(line: 3, problem: .treeViewExpectedName("treeView-beta ## note")))
        XCTAssertEqual(try TreeViewReading.tree("treeView-beta\na\ntreeView-beta.md\ntreeView-beta%%x").entries.map(\.name),
                       ["a", "treeView-beta.md", "treeView-beta%%x"], "A longer bare name wins over the keyword")
        XCTAssertEqual(TreeViewReading.readError("treeView-beta\n├── src/\n    index.js"),
                       .invalidSyntax(line: 3, problem: .treeViewIndentationWithoutBoxDrawing))
        XCTAssertEqual(TreeViewReading.readError("treeView-beta\nroot/\n├── src/\n│   └── "), .invalidSyntax(line: 4, problem: .treeViewEntryWithoutName))
        var limits = MermaidDiagramLimits.standard
        limits.maximumNodeCount = 2
        XCTAssertEqual(try? TreeViewReading.tree("treeView-beta\na\nb", limits: limits).entries.count, 2)
        XCTAssertThrowsError(try TreeViewReading.tree("treeView-beta\na\nb\nc", limits: limits))
    }

    func testTheFrontMatterSetsTheTreesMeasurementsWithinTheirRanges() throws {
        let tree = try TreeViewReading.tree("---\nconfig:\n    treeView:\n        rowIndent: 80\n        lineThickness: 3\n        paddingX: 200\n"
                                            + "        showIcons: true\n---\ntreeView-beta\na")
        XCTAssertEqual(tree.options.rowIndent, 80)
        XCTAssertEqual(tree.options.lineThickness, 3)
        XCTAssertEqual(tree.options.paddingAcross, 5, "200 is past paddingX's 100")
        XCTAssertTrue(tree.options.showsIcons)
    }

    func testIconsAreTheBuiltInOutlinesByNameOrByKind() {
        func glyph(_ name: String, isFolder: Bool = false, icon: String?, showsIcons: Bool = false) -> TreeViewGlyph? {
            TreeViewGlyph(entry: TreeViewEntry(name: name, isFolder: isFolder, depth: 0, parentIndex: nil, icon: icon, classes: nil, description: nil),
                          showsIcons: showsIcons)
        }
        XCTAssertNil(glyph("a.ts", icon: nil))
        XCTAssertEqual(glyph("a.ts", icon: nil, showsIcons: true), .file)
        XCTAssertEqual(glyph("src", isFolder: true, icon: nil, showsIcons: true), .folder)
        XCTAssertNil(glyph("a.ts", icon: "none", showsIcons: true))
        XCTAssertEqual(glyph("data.bin", icon: "folder"), .folder)
        XCTAssertEqual(glyph("src", isFolder: true, icon: "mermaid-treeview:file"), .file)
        XCTAssertEqual(glyph("App.tsx", icon: "logos:react"), .file, "No host draws another pack's icon")
        XCTAssertEqual(glyph("src", isFolder: true, icon: "rocket"), .folder)
        XCTAssertEqual(glyph("x", icon: "other:folder"), .file)
    }

    /// Mermaid's icons spec (`detectIcon` and `getNodeIcon` with configured maps), as the outline each name gives.
    func testFilesShowTheIconTheirNameOrExtensionIsMappedTo() {
        let maps = TreeViewIconMaps(filenameIcons: ["Dockerfile": "docker", "notes.TXT": "folder", "empty.ts": ""],
                                    extensionIcons: [".ts": "folder", "tsx": "react", ".txt": "none", ".md": ""])
        XCTAssertEqual(maps.icon(forFileNamed: "Dockerfile"), "docker")
        XCTAssertEqual(maps.icon(forFileNamed: "a.ts"), "folder")
        XCTAssertEqual(maps.icon(forFileNamed: "App.tsx"), "react", "With or without the leading dot")
        XCTAssertEqual(maps.icon(forFileNamed: "A.TS"), "folder", "Extensions match in lower case")
        XCTAssertEqual(maps.icon(forFileNamed: "notes.TXT"), "folder", "A file name wins over an extension")
        XCTAssertEqual(maps.icon(forFileNamed: "empty.ts"), "folder", "An empty file name icon is none found")
        XCTAssertEqual(maps.icon(forFileNamed: "archive.tar.ts"), "folder", "The last extension")
        XCTAssertNil(maps.icon(forFileNamed: ".ts"), "A dot file has no extension")
        XCTAssertNil(maps.icon(forFileNamed: "README.md"))
        XCTAssertNil(maps.icon(forFileNamed: "Makefile"))
        func glyph(_ name: String, isFolder: Bool = false, showsIcons: Bool = true) -> TreeViewGlyph? {
            TreeViewGlyph(entry: TreeViewEntry(name: name, isFolder: isFolder, depth: 0, parentIndex: nil, icon: nil, classes: nil, description: nil),
                          showsIcons: showsIcons, iconMaps: maps)
        }
        XCTAssertEqual([glyph("a.ts"), glyph("notes.txt"), glyph("Dockerfile"), glyph("README.md"), glyph("src.ts", isFolder: true)],
                       [.folder, nil, .file, .file, .folder], "Mapped to a built-in name, to none, to another pack's icon, unmapped, a folder")
        XCTAssertNil(glyph("a.ts", showsIcons: false), "The maps apply only when icons are shown")
    }

    func testTheIconMapsAreReadFromTheFrontMatter() throws {
        let documented = try TreeViewReading.tree(try XCTUnwrap(TreeViewCorpus.documentationExamples().dropFirst(6).first))
        XCTAssertEqual(documented.options.iconMaps, TreeViewIconMaps(filenameIcons: ["Dockerfile": "docker"],
                                                                     extensionIcons: [".ts": "typescript", ".tsx": "react-ts", ".txt": "none"]))
        let tree = try TreeViewReading.tree("---\nconfig:\n  treeView:\n    extensionIcons:\n      \".md\": 'folder' # a comment\n      .bin: 12\n"
                                            + "      .log: null\n      .js: [a]\n    other:\n      .c: file\n  extensionIcons:\n    .h: file\n---\ntreeView-beta\na")
        XCTAssertEqual(tree.options.iconMaps.extensionIcons, [".md": "folder"], "Only text values under config, treeView and the map's name")
    }
}

/// Mermaid's box-drawing preprocessor spec, through the whole reading: each tree drawn with box-drawing characters reads
/// as the indented tree it stands for.
final class TreeViewBoxDrawingTests: XCTestCase {
    /// The entries' depths and names, folders with their `/`.
    private func outline(_ lines: [String]) throws -> [String] {
        try TreeViewReading.tree((["treeView-beta"] + lines).joined(separator: "\n")).entries.map { entry in
            String(repeating: "    ", count: entry.depth) + entry.name + (entry.isFolder ? "/" : "")
        }
    }

    func testTreesOfTheStandardTreeCommandReadAsTheirIndentation() throws {
        XCTAssertEqual(try outline(["root/", "├── src/", "│   └── index.js", "└── README.md"]), ["root/", "    src/", "        index.js", "    README.md"])
        XCTAssertEqual(try outline(["root/", "├── a/", "│   ├── b/", "│   │   ├── c/", "│   │   │   └── deep.txt", "│   │   └── d.txt", "│   └── e.txt", "└── f.txt"]),
                       ["root/", "    a/", "        b/", "            c/", "                deep.txt", "            d.txt", "        e.txt", "    f.txt"])
        XCTAssertEqual(try outline(["├── file1.txt", "└── file2.txt"]), ["file1.txt", "file2.txt"], "No root line")
        XCTAssertEqual(try outline(["root/", "├── a/", "│   └── b.txt", "└── c/", "    └── d.txt"]), ["root/", "    a/", "        b.txt", "    c/", "        d.txt"])
        XCTAssertEqual(try outline(["root/", "┣━━ src/", "┃   ┗━━ index.js", "┗━━ README.md"]), ["root/", "    src/", "        index.js", "    README.md"])
        XCTAssertEqual(try outline(["my-project/", "├── src/", "│   ├── components/", "│   │   └── MyComponent.js", "│   ├── index.css", "│   └── index.js",
                                    "├── package.json", "└── README.md"]),
                       ["my-project/", "    src/", "        components/", "            MyComponent.js", "        index.css", "        index.js", "    package.json",
                        "    README.md"])
    }

    func testPrefixesOfAnyWidthTabsAnnotationsAndDecorations() throws {
        for prefix in ["├─── ", "├──", "├───── ", "└─ ", "┣━━━ ", "├──\t"] {
            XCTAssertEqual(try outline(["root/", prefix + "file.txt"]), ["root/", "    file.txt"], prefix)
        }
        XCTAssertEqual(try outline(["├── src/", "\t├── index.ts", "\t└── utils.ts"]), ["src/", "    index.ts", "    utils.ts"])
        XCTAssertEqual(try outline(["root/", "├── a.txt", "│", "└── b.txt"]), ["root/", "    a.txt", "    b.txt"])
        let annotated = try TreeViewReading.tree("treeView-beta\nmy-project/\n├── src/ :::highlight\n│   ├── App.tsx :::highlight icon(react) ## main component\n"
                                                 + "│   └── index.ts ## entry point\n└── README.md ## project docs")
        XCTAssertEqual(annotated.entries.map(\.classes), [nil, "highlight", "highlight", nil, nil])
        XCTAssertEqual(annotated.entries[2].icon, "react")
        XCTAssertEqual(annotated.entries.map(\.description), [nil, nil, "main component", "entry point", "project docs"])
    }

    func testCommentsBlankLinesAndTitlesPassAndAStrayBoxCharacterIsANamesOwn() throws {
        XCTAssertEqual(try outline(["%% a comment", "├── file.txt", "%% another comment", "└── other.txt"]), ["file.txt", "other.txt"])
        XCTAssertEqual(try outline(["", "├── file.txt", "", "└── other.txt"]), ["file.txt", "other.txt"])
        let titled = try TreeViewReading.tree("treeView-beta\ntitle My Tree\naccTitle: Accessible Title\n├── file.txt\n└── other.txt")
        XCTAssertEqual(titled.title, "My Tree")
        XCTAssertEqual(titled.accessibilityTitle, "Accessible Title")
        XCTAssertEqual(try outline(["Section ─ A.txt", "├── b.txt"]), ["Section ─ A.txt", "    b.txt"])
        XCTAssertEqual(TreeViewReading.readError("treeView-beta\n├── a.txt\n│\n└── "), .invalidSyntax(line: 4, problem: .treeViewEntryWithoutName),
                       "Errors name the line as written, after a skipped decoration line")
    }

    func testABoxDrawnTreeReadsAsItsIndentedForm() throws {
        let pairs = [("treeView-beta\n    src/\n        index.js\n        App.tsx\n    package.json", "treeView-beta\n├── src/\n│   ├── index.js\n│   └── App.tsx\n└── package.json"),
                     ("treeView-beta\n    a/\n        b/\n            c/\n                d.txt\n            e.txt\n        f.txt",
                      "treeView-beta\n└── a/\n    ├── b/\n    │   ├── c/\n    │   │   └── d.txt\n    │   └── e.txt\n    └── f.txt")]
        for (indented, drawn) in pairs { XCTAssertEqual(try TreeViewReading.tree(drawn).entries, try TreeViewReading.tree(indented).entries, drawn) }
    }
}
