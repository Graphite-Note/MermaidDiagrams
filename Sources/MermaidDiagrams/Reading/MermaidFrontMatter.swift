/**
 * File: MermaidFrontMatter.swift
 * ------------------------------
 * Layer: Core
 * Description: Finds a diagram's front matter as Pele's preprocess.ts finds it, on the text's own bytes, and reads it
 *              once as YAML into a flat tree: its title, its configuration, and whether it is YAML at all.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 24/11/2026
 */

/// A `---` fenced YAML block at the start of a diagram's text, found as Pele's `matchFrontMatter` finds it (the way
/// Mermaid's front matter pattern does): the opening `---` after spaces or tabs only on the first line, then white space
/// up to a line break; the closing fence is the first line, after the opening one, that is the same indent and `---`
/// followed by white space up to a line break. The body loses the indent on each line that has it.
struct MermaidFrontMatter {
    /// The UTF-8 bytes of the YAML between the fences.
    let bodyBytes: [UInt8]
    /// Where the text after the front matter starts, after the line break that ends the closing fence.
    let end: Int

    /// The YAML between the fences.
    var body: String { String(decoding: bodyBytes, as: UTF8.self) }

    /// The front matter at the start of `bytes`, whose line breaks are line feeds; nil when there is none.
    static func find(in bytes: [UInt8]) -> MermaidFrontMatter? {
        bytes.withUnsafeBufferPointer { buffer in find(in: buffer) }
    }

    /// The front matter at the start of `bytes` where they stand, a String's own or an array's: only its body is copied.
    static func find(in bytes: UnsafeBufferPointer<UInt8>) -> MermaidFrontMatter? {
        var indentEnd = 0
        while indentEnd < bytes.count, !isLineBreak(bytes[indentEnd]), case let length = JavaScriptWhitespace.length(in: bytes, at: indentEnd),
              length > 0 { indentEnd += length }
        guard hasDashes(in: bytes, at: indentEnd) else { return nil }
        var openingEnds: [Int] = []
        var index = indentEnd + dashes.count
        while index < bytes.count, case let length = JavaScriptWhitespace.length(in: bytes, at: index), length > 0 {
            if isLineBreak(bytes[index]) { openingEnds.append(index) }
            index += length
        }
        guard let firstOpeningEnd = openingEnds.first, let lastOpeningEnd = openingEnds.last else { return nil }
        // Pele bounds its search by the last closing fence, found scanning back from the end, and takes the body from
        // the last line break of the opening line before that fence. A fence after the opening line's last line break
        // makes that line break the body's start, and the first such fence is the one Pele finds: it is looked for
        // forward, from there. Without one, the opening line's own last line break, followed by a fence, is the only
        // other fence (any earlier one would start in the white space that ends there), and the body then starts after
        // the line break before it.
        var lineBreak = lastOpeningEnd + 1
        while let candidate = MermaidPreprocessing.firstIndex(of: MermaidByte.newline, in: bytes, from: lineBreak) {
            if let end = closingEnd(indentEnd: indentEnd, in: bytes, at: candidate) {
                return MermaidFrontMatter(bodyBytes: body(bytes[(lastOpeningEnd + 1)..<candidate], indent: bytes[..<indentEnd]), end: end + 1)
            }
            lineBreak = candidate + 1
        }
        guard lastOpeningEnd > firstOpeningEnd, bytes[lastOpeningEnd] == MermaidByte.newline,
              let end = closingEnd(indentEnd: indentEnd, in: bytes, at: lastOpeningEnd) else { return nil }
        let bodyStart = openingEnds[openingEnds.count - 2] + 1
        return MermaidFrontMatter(bodyBytes: body(bytes[bodyStart..<lastOpeningEnd], indent: bytes[..<indentEnd]), end: end + 1)
    }

    /// What the YAML holds, read once into a flat tree, or nil when Pele's reader refuses it (Pele then refuses the
    /// diagram: `Front matter is not valid YAML`).
    func tree() -> MermaidYAMLTree? {
        MermaidYAMLTree.read(bodyBytes)
    }

    /// The front matter's `title`, as Pele takes it: `String(title)` when it is truthy.
    static func title(in value: DirectiveValue) -> String? {
        guard case .object(let entries) = value, let title = entries["title"], MermaidYAMLDocument.isTruthy(title) else { return nil }
        return MermaidYAMLDocument.javaScriptText(title)
    }

    /// The `title` of the front matter's tree, as Pele takes it: `String(title)` when it is truthy.
    static func title(in tree: MermaidYAMLTree) -> String? {
        guard let title = tree.entry(of: MermaidYAMLTree.root, named: "title"), tree.isTruthy(title) else { return nil }
        return tree.javaScriptText(title)
    }

    /// The position of the line break that ends the closing fence starting after the line break at `position`: the
    /// last line break in the white space after the fence (the opening fence's indent, the first `indentEnd` bytes, and
    /// `---`); nil when the fence does not stand there or no line break ends it.
    private static func closingEnd(indentEnd: Int, in bytes: UnsafeBufferPointer<UInt8>, at position: Int) -> Int? {
        let fenceStart = position + 1
        guard fenceStart + indentEnd <= bytes.count else { return nil }
        for offset in 0..<indentEnd where bytes[fenceStart + offset] != bytes[offset] { return nil }
        guard hasDashes(in: bytes, at: fenceStart + indentEnd) else { return nil }
        var lastBreak: Int?
        var index = fenceStart + indentEnd + dashes.count
        while index < bytes.count, case let length = JavaScriptWhitespace.length(in: bytes, at: index), length > 0 {
            if isLineBreak(bytes[index]) { lastBreak = index }
            index += length
        }
        return lastBreak
    }

    /// The body's bytes, each line without the indent when it starts with it. The lines are compared as Swift's
    /// characters, as `hasPrefix` compares them, so that a combining mark after the indent keeps a line as it is.
    private static func body(_ written: Slice<UnsafeBufferPointer<UInt8>>, indent: Slice<UnsafeBufferPointer<UInt8>>) -> [UInt8] {
        guard !indent.isEmpty else { return Array(written) }
        let indentText = String(decoding: indent, as: UTF8.self)
        let lines = String(decoding: written, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in line.hasPrefix(indentText) ? String(line.dropFirst(indentText.count)) : String(line) }
        return Array(lines.joined(separator: "\n").utf8)
    }

    private static func isLineBreak(_ byte: UInt8) -> Bool {
        byte == MermaidByte.newline || byte == MermaidByte.carriageReturn
    }

    private static func hasDashes(in bytes: UnsafeBufferPointer<UInt8>, at position: Int) -> Bool {
        position + 3 <= bytes.count && bytes[position] == MermaidByte.hyphen && bytes[position + 1] == MermaidByte.hyphen
            && bytes[position + 2] == MermaidByte.hyphen
    }

    private static let dashes = Array("---".utf8)
}

/// A diagram's front matter as the reader found it, its YAML read once: no front matter, or the front matter and the
/// tree of what it holds (nil when it is not YAML). The reader keeps it on its cursor, so that a type's options do not
/// read the YAML again (`MermaidConfigurationOptions`).
struct MermaidReadFrontMatter {
    let frontMatter: MermaidFrontMatter?
    let tree: MermaidYAMLTree?

    /// No front matter.
    static let absent = MermaidReadFrontMatter(frontMatter: nil)

    /// The front matter at the start of `bytes`, found and read.
    init(in bytes: [UInt8]) {
        self.init(frontMatter: MermaidFrontMatter.find(in: bytes))
    }

    init(frontMatter: MermaidFrontMatter?) {
        self.frontMatter = frontMatter
        tree = frontMatter?.tree()
    }

    /// What the YAML holds as a configuration's values, made from the tree each time it is asked for.
    var value: DirectiveValue? {
        tree.map { tree in tree.value(of: MermaidYAMLTree.root) }
    }
}
