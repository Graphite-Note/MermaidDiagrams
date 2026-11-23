/**
 * File: MermaidFrontMatter.swift
 * ------------------------------
 * Layer: Core
 * Description: Finds a diagram's front matter as Pele's preprocess.ts finds it and reads it as YAML: its title, its
 *              configuration, and whether it is YAML at all.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

/// A `---` fenced YAML block at the start of a diagram's text, found as Pele's `matchFrontMatter` finds it (the way
/// Mermaid's front matter pattern does): the opening `---` after spaces or tabs only on the first line, then white space
/// up to a line break; the closing fence is the first line, after the opening one, that is the same indent and `---`
/// followed by white space up to a line break. The body loses the indent on each line that has it.
struct MermaidFrontMatter {
    /// The YAML between the fences.
    let body: String
    /// Where the text after the front matter starts, after the line break that ends the closing fence.
    let end: Int

    /// The front matter at the start of `bytes`, whose line breaks are line feeds; nil when there is none.
    static func find(in bytes: [UInt8]) -> MermaidFrontMatter? {
        var indentEnd = 0
        while indentEnd < bytes.count, !isLineBreak(bytes[indentEnd]), case let length = JavaScriptWhitespace.length(in: bytes, at: indentEnd),
              length > 0 { indentEnd += length }
        let fence = Array(bytes[..<indentEnd]) + dashes
        guard hasText(dashes, in: bytes, at: indentEnd) else { return nil }
        var openingEnds: [Int] = []
        var index = indentEnd + dashes.count
        while index < bytes.count, case let length = JavaScriptWhitespace.length(in: bytes, at: index), length > 0 {
            if isLineBreak(bytes[index]) { openingEnds.append(index) }
            index += length
        }
        guard let firstOpeningEnd = openingEnds.first else { return nil }
        // The last closing fence after the opening line bounds the search, as Pele's backward scan does.
        var lastFence: Int?
        var candidate = bytes.count - 1
        while candidate > firstOpeningEnd {
            if bytes[candidate] == MermaidByte.newline, closingEnd(of: fence, in: bytes, at: candidate) != nil {
                lastFence = candidate
                break
            }
            candidate -= 1
        }
        guard let lastFence else { return nil }
        let openingEnd = openingEnds.last { end in end < lastFence } ?? firstOpeningEnd
        let bodyStart = openingEnd + 1
        var fenceStart = max(bodyStart - 1, 0)
        while fenceStart <= lastFence {
            if fenceStart >= bodyStart, bytes[fenceStart] == MermaidByte.newline, let end = closingEnd(of: fence, in: bytes, at: fenceStart) {
                let indent = String(decoding: bytes[..<indentEnd], as: UTF8.self)
                return MermaidFrontMatter(body: withoutIndent(String(decoding: bytes[bodyStart..<fenceStart], as: UTF8.self), indent: indent),
                                          end: end + 1)
            }
            fenceStart += 1
        }
        return nil
    }

    /// What the YAML holds, or nil when Pele's reader refuses it (Pele then refuses the diagram: `Front matter is not
    /// valid YAML`).
    func value() -> DirectiveValue? {
        MermaidYAMLDocument.value(of: body)
    }

    /// The front matter's `title`, as Pele takes it: `String(title)` when it is truthy.
    static func title(in value: DirectiveValue) -> String? {
        guard case .object(let entries) = value, let title = entries["title"], MermaidYAMLDocument.isTruthy(title) else { return nil }
        return MermaidYAMLDocument.javaScriptText(title)
    }

    /// The position of the line break that ends the closing fence starting after the line break at `position`: the
    /// last line break in the white space after `fence`; nil when `fence` does not stand there or no line break ends it.
    private static func closingEnd(of fence: [UInt8], in bytes: [UInt8], at position: Int) -> Int? {
        guard hasText(fence, in: bytes, at: position + 1) else { return nil }
        var lastBreak: Int?
        var index = position + 1 + fence.count
        while index < bytes.count, case let length = JavaScriptWhitespace.length(in: bytes, at: index), length > 0 {
            if isLineBreak(bytes[index]) { lastBreak = index }
            index += length
        }
        return lastBreak
    }

    private static func withoutIndent(_ body: String, indent: String) -> String {
        guard !indent.isEmpty else { return body }
        return body.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in line.hasPrefix(indent) ? String(line.dropFirst(indent.count)) : String(line) }.joined(separator: "\n")
    }

    private static func isLineBreak(_ byte: UInt8) -> Bool {
        byte == MermaidByte.newline || byte == MermaidByte.carriageReturn
    }

    private static func hasText(_ literal: [UInt8], in bytes: [UInt8], at position: Int) -> Bool {
        position >= 0 && position + literal.count <= bytes.count && bytes[position..<position + literal.count].elementsEqual(literal)
    }

    private static let dashes = Array("---".utf8)
}
