/**
 * File: TreeViewIconMaps.swift
 * ----------------------------
 * Layer: Core
 * Description: A tree view's icons by file name and by extension (`filenameIcons`, `extensionIcons`), read from its front
 *              matter, and the icon they give a file, as Pele's detectIcon finds it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
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
        var keys: [(indentation: Int, key: String)] = []
        for line in Self.frontMatterLines(of: bytes) {
            let indentation = line.prefix { character in character == " " }.count
            let content = line.trimmingCharacters(in: .whitespaces)
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
            if line.trimmingCharacters(in: .whitespaces) == "---" { return lines }
            lines.append(line)
        }
        return []
    }

    /// `key: value` or `key:`, the key plain or quoted, the value without a comment after it.
    private static func keyAndValue(_ content: String) -> (String, String)? {
        var reader = KanbanFlowReader(bytes: Array(content.utf8))
        guard let key = try? reader.readKey(), reader.skipsColonBeforeValue() else { return nil }
        let rest = reader.rest.trimmingCharacters(in: .whitespaces)
        if let first = rest.first, first == "\"" || first == "'" { return (key, rest) }
        let withoutComment = rest.range(of: " #").map { comment in String(rest[..<comment.lowerBound]) } ?? rest
        return (key, withoutComment.trimmingCharacters(in: .whitespaces))
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
