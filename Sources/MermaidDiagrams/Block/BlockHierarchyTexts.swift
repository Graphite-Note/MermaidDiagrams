/**
 * File: BlockHierarchyTexts.swift
 * -------------------------------
 * Layer: Core
 * Description: What the block hierarchy does with texts: identifiers keyed as Swift's Strings are, texts split at
 *              commas by Characters, classes and styles given to blocks, edges counted per pair of ends, and the texts
 *              the reading makes written after the text's bytes.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import Foundation

extension BlockHierarchy {
    /// `text`, or for a text beyond ASCII its composed form after the text's bytes, which canonically equivalent texts
    /// share.
    mutating func key(of text: BlockText) -> BlockText {
        guard !isASCII(text) else { return text }
        return appendDerived(string(text).precomposedStringWithCanonicalMapping)
    }

    /// Whether two texts are equal as Swift's Strings are.
    func sameText(_ first: BlockText, _ second: BlockText) -> Bool {
        if BlockBytes.same(first, second, in: bytes) { return true }
        guard !isASCII(first) || !isASCII(second) else { return false }
        return string(first) == string(second)
    }

    func isASCII(_ text: BlockText) -> Bool {
        !bytes[text.lowerBound..<text.upperBound].contains { byte in byte >= 0x80 }
    }

    func string(_ text: BlockText) -> String {
        String(decoding: bytes[text.lowerBound..<text.upperBound], as: UTF8.self)
    }

    /// The pieces of `text` between commas, as Swift's `split(separator: ",", omittingEmptySubsequences: false)` splits
    /// it, by Characters: at the bytes of each comma, but beyond ASCII only at a comma no combining mark follows.
    func pieces(of text: BlockText) -> [BlockText] {
        if isASCII(text) {
            var pieces: [BlockText] = []
            var start = text.lowerBound
            for index in text.lowerBound...text.upperBound where index == text.upperBound || bytes[index] == PlaneMapByte.comma {
                pieces.append(BlockText(start: start, count: index - start))
                start = index + 1
            }
            return pieces
        }
        let whole = string(text)
        var pieces: [BlockText] = []
        for piece in whole.split(separator: ",", omittingEmptySubsequences: false) {
            let offset = whole.utf8.distance(from: whole.utf8.startIndex, to: piece.startIndex)
            pieces.append(BlockText(start: text.lowerBound + offset, count: piece.utf8.count))
        }
        return pieces
    }

    // MARK: Classes and styles

    /// `class a,b name`: each identifier between commas, trimmed, given the class, in order.
    mutating func assignClass(_ className: BlockText, to identifiers: BlockText) {
        for piece in pieces(of: identifiers) {
            let blockIndex = named(BlockBytes.trimmed(piece, in: bytes))
            let link = Int32(classLinks.count)
            classLinks.append(BlockClassLink(name: className, next: -1))
            if blocks[blockIndex].lastClassLink >= 0 {
                classLinks[Int(blocks[blockIndex].lastClassLink)].next = link
            } else {
                blocks[blockIndex].firstClassLink = link
            }
            blocks[blockIndex].lastClassLink = link
        }
    }

    /// A copy of `block`'s chain of class names, for the block that takes them, so that the waiting block keeps its own.
    mutating func copiedClassLinks(of block: BlockRecord) -> (first: Int32, last: Int32) {
        var first: Int32 = -1
        var last: Int32 = -1
        var link = Int(block.firstClassLink)
        while link >= 0 {
            let copy = Int32(classLinks.count)
            classLinks.append(BlockClassLink(name: classLinks[link].name, next: -1))
            if last >= 0 { classLinks[Int(last)].next = copy } else { first = copy }
            last = copy
            link = Int(classLinks[link].next)
        }
        return (first, last)
    }

    /// The declarations between commas, as Pele splits them, untrimmed.
    mutating func split(_ declarations: BlockText) -> BlockSlice {
        let first = texts.count
        texts.append(contentsOf: pieces(of: declarations))
        return BlockSlice(first: first, count: texts.count - first)
    }

    /// Pele's `addStyleClass`: each declaration between commas, its first semicolon dropped and trimmed.
    mutating func addClass(_ name: BlockText, declarations: BlockText) {
        let number = classNames.intern(key(of: name), in: bytes)
        while classIndicesByNameNumber.count <= number { classIndicesByNameNumber.append(-1) }
        if classIndicesByNameNumber[number] < 0 {
            classIndicesByNameNumber[number] = Int32(classes.count)
            classes.append(BlockClassRecord(name: name, styles: []))
        }
        let classIndex = Int(classIndicesByNameNumber[number])
        for piece in pieces(of: declarations) {
            classes[classIndex].styles.append(BlockBytes.trimmed(withoutFirstSemicolon(piece), in: bytes))
        }
    }

    /// `text` with its first semicolon taken out, as `String.remove(at:)` takes out its first `;` Character: the
    /// semicolon's bytes, unless a combining mark follows it, which makes another Character.
    mutating func withoutFirstSemicolon(_ text: BlockText) -> BlockText {
        guard isASCII(text) else {
            var fixed = string(text)
            guard let semicolon = fixed.firstIndex(of: ";") else { return text }
            fixed.remove(at: semicolon)
            return appendDerived(fixed)
        }
        guard let semicolon = bytes[text.lowerBound..<text.upperBound].firstIndex(of: UInt8(ascii: ";")) else { return text }
        if semicolon == text.upperBound - 1 { return BlockText(start: text.lowerBound, count: Int(text.count) - 1) }
        return appendDerived(bytes[text.lowerBound..<semicolon] + bytes[(semicolon + 1)..<text.upperBound])
    }

    // MARK: Edges

    mutating func addEdge(_ draft: BlockEdgeDraft) {
        let source = intern(draft.source)
        let target = intern(draft.target)
        let key = UInt64(UInt32(source)) << 32 | UInt64(UInt32(target))
        let count = (edgeCountsByEnds[key] ?? 0) + 1
        edgeCountsByEnds[key] = count
        let values = bytes.withUnsafeBufferPointer { buffer in
            BlockSyntaxValues.linkValues(UnsafeBufferPointer(rebasing: buffer[draft.link.lowerBound..<draft.link.upperBound]))
        }
        edges.append(BlockEdgeRecord(ordinal: count, source: draft.source, target: draft.target, sourceNumber: Int32(source), targetNumber: Int32(target),
                                     label: draft.label, sourceArrowhead: Self.arrowheadCode(values.source),
                                     targetArrowhead: Self.arrowheadCode(values.target), isThick: values.isThick, isDotted: values.isDotted))
    }

    static func arrowheadCode(_ arrowhead: FlowchartArrowhead) -> UInt8 {
        UInt8(BlockModel.arrowheads.firstIndex(of: arrowhead) ?? 0)
    }

    // MARK: Texts the reading makes

    /// `id-<number>`, Pele's `generateId`, after the text's bytes.
    mutating func generatedIdentifier(_ number: Int) -> BlockText {
        let start = bytes.count
        bytes.append(contentsOf: Self.identifierPrefix)
        appendDigits(of: number)
        return BlockText(start: start, count: bytes.count - start)
    }

    static let identifierPrefix: [UInt8] = Array("id-".utf8)

    /// `<identifier>-<cell>`, a space's cell.
    mutating func appendDerived(identifier: BlockText, suffix cell: Int) -> BlockText {
        let start = bytes.count
        bytes.reserveCapacity(bytes.count + Int(identifier.count) + 21)
        for index in identifier.lowerBound..<identifier.upperBound { bytes.append(bytes[index]) }
        bytes.append(PlaneMapByte.hyphen)
        appendDigits(of: cell)
        return BlockText(start: start, count: bytes.count - start)
    }

    /// The decimal digits of `number`, which is not negative, as `String(number)` writes them.
    mutating func appendDigits(of number: Int) {
        var digits: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                     UInt8) = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        guard number >= 0 else { return bytes.append(contentsOf: String(number).utf8) }
        var remaining = number
        var count = 0
        withUnsafeMutableBytes(of: &digits) { buffer in
            repeat {
                buffer[19 - count] = UInt8(ascii: "0") + UInt8(remaining % 10)
                remaining /= 10
                count += 1
            } while remaining > 0
            bytes.append(contentsOf: buffer[(20 - count)...])
        }
    }

    mutating func appendDerived(_ text: String) -> BlockText {
        let start = bytes.count
        bytes.append(contentsOf: text.utf8)
        return BlockText(start: start, count: bytes.count - start)
    }

    mutating func appendDerived(_ text: ArraySlice<UInt8>) -> BlockText {
        let start = bytes.count
        bytes.append(contentsOf: text)
        return BlockText(start: start, count: bytes.count - start)
    }
}
