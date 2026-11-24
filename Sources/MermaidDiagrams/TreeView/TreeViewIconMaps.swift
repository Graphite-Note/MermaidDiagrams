/**
 * File: TreeViewIconMaps.swift
 * ----------------------------
 * Layer: Core
 * Description: A tree view's icons by file name and by extension (`filenameIcons`, `extensionIcons`), read from its front
 *              matter, and the icon they give a file, as Pele's detectIcon finds it.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 23/11/2026
 */

/// The icons a tree view's options give files by name and by extension, as Pele's `iconConfig` keeps them: only the
/// values that are text. They are read from the front matter's block mappings (`config:`, `treeView:`, then
/// `extensionIcons:` and a `.ts: typescript` line per extension); a map written as a flow mapping or in a directive is
/// not read.
public struct TreeViewIconMaps: Equatable, Sendable {
    public internal(set) var filenameIcons: [String: String] = [:]
    public internal(set) var extensionIcons: [String: String] = [:]

    init() {}

    init(filenameIcons: [String: String], extensionIcons: [String: String]) {
        self.filenameIcons = filenameIcons
        self.extensionIcons = extensionIcons
    }

    /// The maps in the front matter at the start of `bytes`, none without one.
    init(frontMatterOf bytes: [UInt8]) {
        // A text without `Icons` or a backslash anywhere has none in its front matter's lines either.
        guard Self.mayNameAnIconMap(bytes[...]) else { return }
        var keys: [(indentation: Int, key: String)] = []
        let lines = Self.frontMatterLines(of: bytes)
        // The two maps' keys can only be written with `Icons` in them, or with an escape, which takes a backslash.
        guard lines.contains(where: { line in Self.mayNameAnIconMap(ArraySlice(line.utf8)) }) else { return }
        for line in lines {
            let indentation = line.prefix { character in character == " " }.count
            let content = FoundationTextOnBytes.trimmed(line, includingLineBreaks: false)
            guard !content.isEmpty, !content.hasPrefix("#"), let (key, value) = Self.keyAndValue(content) else { continue }
            while let last = keys.last, last.indentation >= indentation { keys.removeLast() }
            let path = keys.map(\.key)
            if value.isEmpty {
                keys.append((indentation, key))
            } else if let text = Self.text(value) {
                if path == ["config", "treeView", "filenameIcons"] { filenameIcons[key] = text }
                if path == ["config", "treeView", "extensionIcons"] { extensionIcons[key] = text }
            }
        }
    }

    /// Whether bytes hold `Icons` or a backslash, without which no key of them is `filenameIcons` or `extensionIcons`.
    private static func mayNameAnIconMap(_ bytes: ArraySlice<UInt8>) -> Bool {
        guard !bytes.contains(UInt8(ascii: "\\")) else { return true }
        var searchStart = bytes.startIndex
        while let candidate = bytes[searchStart...].firstIndex(of: iconsWord[0]) {
            if bytes[candidate...].starts(with: iconsWord) { return true }
            searchStart = candidate + 1
        }
        return false
    }

    private static let iconsWord = Array("Icons".utf8)

    /// The icon a file is mapped to, or nil: by its whole name first, else by its last extension in lower case, with or
    /// without its dot. A name starting with its only dot (`.env`) has no extension. An empty icon is none found.
    func icon(forFileNamed name: String) -> String? {
        if let icon = filenameIcons[name], !icon.isEmpty { return icon }
        guard let dot = name.lastIndex(of: "."), dot > name.startIndex else { return nil }
        let fileExtension = name[dot...].lowercased()
        let icon = extensionIcons[fileExtension] ?? extensionIcons[String(fileExtension.dropFirst())]
        return icon?.isEmpty == false ? icon : nil
    }

    /// The lines between the opening `---` and the closing one, none when the front matter is missing or never closed.
    private static func frontMatterLines(of bytes: [UInt8]) -> [String] {
        var cursor = MermaidTextCursor(bytes: bytes)
        if cursor.hasPrefix([0xEF, 0xBB, 0xBF]) { cursor.advance(by: 3) }
        cursor.skipWhitespace()
        guard cursor.hasPrefix(Array("---".utf8)), cursor.readRestOfLine() == "---" else { return [] }
        var lines: [String] = []
        while !cursor.isAtEnd {
            cursor.advance()
            let line = cursor.readRestOfLine()
            if FoundationTextOnBytes.trimmed(line, includingLineBreaks: false) == "---" { return lines }
            lines.append(line)
        }
        return []
    }

    /// `key: value` or `key:`, the key plain or quoted, the value without a comment after it.
    private static func keyAndValue(_ content: String) -> (String, String)? {
        var reader = KanbanFlowReader(bytes: Array(content.utf8))
        guard let key = try? reader.readKey(), reader.skipsColonBeforeValue() else { return nil }
        let rest = FoundationTextOnBytes.trimmed(reader.rest, includingLineBreaks: false)
        if let first = rest.first, first == "\"" || first == "'" { return (key, rest) }
        // Without a space and a number sign in its bytes the value holds no comment, which is looked for only then.
        let mayHoldComment = rest.utf8.indices.contains { index in
            rest.utf8[index] == MermaidByte.space && rest.utf8.index(after: index) < rest.utf8.endIndex
                && rest.utf8[rest.utf8.index(after: index)] == UInt8(ascii: "#")
        }
        let withoutComment = mayHoldComment ? rest.range(of: " #").map { comment in String(rest[..<comment.lowerBound]) } ?? rest : rest
        return (key, FoundationTextOnBytes.trimmed(withoutComment, includingLineBreaks: false))
    }

    /// A value that YAML's JSON schema reads as text, or nil for null, a Boolean, a number or a collection.
    private static func text(_ written: String) -> String? {
        var reader = KanbanFlowReader(bytes: Array(written.utf8))
        guard let first = written.first, first != "{", first != "[" else { return nil }
        if first == "\"" || first == "'" {
            guard case .text(let text) = try? reader.readDocument() else { return nil }
            return text
        }
        guard case .text(let text) = KanbanYAMLValue(plainScalar: written) else { return nil }
        return text
    }
}
