/**
 * File: TreeViewByteBoxDrawing.swift
 * ----------------------------------
 * Layer: Core
 * Description: The box-drawing preprocessing of a tree view read on the bytes of its kept lines, when every character
 *              after its keyword is ASCII or a box-drawing one, each a single UTF-16 unit: each branch's line set in
 *              four spaces per level as TreeViewBoxDrawingReader sets it, without a String per line.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

/// `TreeViewBoxDrawingReader.lines(after:in:)`'s conversion on lines whose characters are ASCII or box drawing
/// (U+2500 to U+257F): such a line's UTF-16 units are its characters and its scalars, each written in one byte or in
/// the three bytes `E2 94` or `E2 95` and one more, so its columns and checks are those of the String the reader reads.
enum TreeViewByteBoxDrawing {
    /// The kept lines (`kept`, the keyword's first) converted, joined as the token source joins them; nil when a line
    /// holds another character, which the box-drawing reader reads from its String.
    static func converted(_ kept: [Int], lines: [Range<Int>], in text: UnsafeBufferPointer<UInt8>,
                          keywordLine: Int) throws(MermaidDiagramReadError) -> TreeViewTokenSource? {
        var units: [[UInt16]] = []
        units.reserveCapacity(kept.count)
        for index in kept {
            guard let lineUnits = self.units(of: UnsafeBufferPointer(rebasing: text[lines[index]])) else { return nil }
            units.append(lineUnits)
        }
        let unchanged = units.indices.map { offset in passesUnchanged(units[offset], bytes: text[lines[kept[offset]]]) }
        let isContent = units.indices.map { offset in !unchanged[offset] && !isDecorationOnly(units[offset]) }
        let content = units.indices.filter { offset in offset > 0 && isContent[offset] }.map { offset in expandingTabs(units[offset]) }
        // A branch's line may be longer than written: four spaces a level for its box drawing's few units.
        var output = TreeViewSourceBuilder(byteCapacity: 2 * text.count, lineCapacity: kept.count)
        guard content.contains(where: { line in line.contains(where: TreeViewBoxDrawingReader.isBoxCharacter) }) else {
            for index in kept.dropFirst() { output.append(text[lines[index]], writtenLine: keywordLine + index) }
            return output.source
        }
        let segmentWidth = content.lazy.compactMap { line in TreeViewBoxDrawingReader.branchColumn(in: line) }.first { column in column > 0 } ?? 4
        for (offset, index) in kept.enumerated().dropFirst() {
            let writtenLine = keywordLine + index
            if unchanged[offset] {
                output.append(text[lines[index]], writtenLine: writtenLine)
                continue
            }
            if !isContent[offset] { continue }
            let normalized = expandingTabs(units[offset])
            if let column = TreeViewBoxDrawingReader.branchColumn(in: normalized) {
                let depth = Int((Double(column) / Double(segmentWidth)).rounded()) + 1
                var start = column + 1
                while start < normalized.count, TreeViewBoxDrawingReader.isDash(normalized[start]) { start += 1 }
                while start < normalized.count, normalized[start] == TreeViewBoxDrawingReader.space { start += 1 }
                var end = normalized.count
                while end > start, isASCIIWhitespace(normalized[end - 1]) { end -= 1 }
                guard end > start else { throw .invalidSyntax(line: writtenLine, problem: .treeViewEntryWithoutName) }
                output.appendBranch(depth: depth, name: normalized[start..<end], writtenLine: writtenLine)
            } else if normalized.allSatisfy({ unit in TreeViewBoxDrawingReader.isBoxCharacter(unit) || TreeViewBoxDrawingReader.isWhitespace(unit) }) {
                continue
            } else if normalized.contains(where: TreeViewBoxDrawingReader.isBoxCharacter) {
                output.append(text[lines[index]], writtenLine: writtenLine)
            } else if let first = normalized.first, TreeViewBoxDrawingReader.isWhitespace(first) {
                throw .invalidSyntax(line: writtenLine, problem: .treeViewIndentationWithoutBoxDrawing)
            } else {
                output.append(text[lines[index]], writtenLine: writtenLine)
            }
        }
        return output.source
    }

    /// The line's UTF-16 units, nil when a character of it is neither ASCII nor box drawing.
    private static func units(of line: UnsafeBufferPointer<UInt8>) -> [UInt16]? {
        var units: [UInt16] = []
        units.reserveCapacity(line.count)
        var index = 0
        while index < line.count {
            let byte = line[index]
            if byte < 0x80 {
                units.append(UInt16(byte))
                index += 1
                continue
            }
            guard byte == 0xE2, index + 2 < line.count, line[index + 1] == 0x94 || line[index + 1] == 0x95, line[index + 2] & 0xC0 == 0x80 else { return nil }
            units.append(0x2000 | (UInt16(line[index + 1] & 0x3F) << 6) | UInt16(line[index + 2] & 0x3F))
            index += 3
        }
        return units
    }

    /// `TreeViewBoxDrawingReader.passesUnchanged`: told from the first unit after the blanks when it starts none of the
    /// lines that pass, else from the line's characters.
    private static func passesUnchanged(_ units: [UInt16], bytes: Slice<UnsafeBufferPointer<UInt8>>) -> Bool {
        if let first = units.first(where: { unit in unit != TreeViewBoxDrawingReader.space && unit != 0x09 }),
           (0x21...0x7E).contains(first) || (0x2500...0x257F).contains(first), first != 0x25, first != 0x74, first != 0x61 {
            return false
        }
        return TreeViewBoxDrawingReader.passesUnchangedReadingCharacters(String(decoding: UnsafeBufferPointer(rebasing: bytes), as: UTF8.self))
    }

    /// `TreeViewBoxDrawingReader.isDecorationOnly` on the units.
    private static func isDecorationOnly(_ units: [UInt16]) -> Bool {
        !units.isEmpty && units.allSatisfy { unit in
            TreeViewBoxDrawingReader.isWhitespace(unit) || unit == TreeViewBoxDrawingReader.lightVertical || unit == TreeViewBoxDrawingReader.heavyVertical
        }
    }

    /// Each tab four spaces, as `expandingTabs` replaces a tab character.
    private static func expandingTabs(_ units: [UInt16]) -> [UInt16] {
        guard units.contains(0x09) else { return units }
        var expanded: [UInt16] = []
        expanded.reserveCapacity(units.count + 8)
        for unit in units {
            if unit == 0x09 { expanded.append(contentsOf: repeatElement(TreeViewBoxDrawingReader.space, count: 4)) } else { expanded.append(unit) }
        }
        return expanded
    }

    /// White space among ASCII's characters, the only white space characters such a line holds.
    private static func isASCIIWhitespace(_ unit: UInt16) -> Bool {
        unit == TreeViewBoxDrawingReader.space || (0x09...0x0D).contains(unit)
    }
}

/// The text a tree view's tokens are read from, built line by line, as `TreeViewTokenSource(lines:)` joins its lines.
struct TreeViewSourceBuilder {
    private var bytes: [UInt8] = []
    private var lineStarts: [Int] = []
    private var writtenLines: [Int] = []

    init(byteCapacity: Int, lineCapacity: Int) {
        bytes.reserveCapacity(byteCapacity)
        lineStarts.reserveCapacity(lineCapacity)
        writtenLines.reserveCapacity(lineCapacity)
    }

    mutating func append(_ line: Slice<UnsafeBufferPointer<UInt8>>, writtenLine: Int) {
        startLine(writtenLine: writtenLine)
        bytes.append(contentsOf: UnsafeBufferPointer(rebasing: line))
    }

    /// A branch's line: four spaces a level, then the name's units, each ASCII or box drawing, in UTF-8.
    mutating func appendBranch(depth: Int, name: ArraySlice<UInt16>, writtenLine: Int) {
        startLine(writtenLine: writtenLine)
        bytes.append(contentsOf: repeatElement(MermaidByte.space, count: 4 * depth))
        for unit in name {
            if unit < 0x80 {
                bytes.append(UInt8(unit))
            } else {
                bytes.append(0xE2)
                bytes.append(0x80 | UInt8((unit >> 6) & 0x3F))
                bytes.append(0x80 | UInt8(unit & 0x3F))
            }
        }
    }

    private mutating func startLine(writtenLine: Int) {
        if !lineStarts.isEmpty { bytes.append(MermaidByte.newline) }
        lineStarts.append(bytes.count)
        writtenLines.append(writtenLine)
    }

    var source: TreeViewTokenSource {
        TreeViewTokenSource(bytes: bytes, lineStarts: lineStarts, writtenLines: writtenLines)
    }
}
