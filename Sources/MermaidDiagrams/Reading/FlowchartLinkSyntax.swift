/**
 * File: FlowchartLinkSyntax.swift
 * -------------------------------
 * Layer: Core
 * Description: Reads a link between two nodes on bytes: its stroke, its marks, how many ranks it spans, its text in
 *              bars or inside it, and the identifier written before it.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.3
 * Date: 24/11/2026
 */

import Foundation

/// What a link between two nodes says: its stroke, its marks, how many ranks it spans and its text.
struct FlowchartLink {
    var stroke: FlowchartEdgeStroke
    var sourceArrowhead: FlowchartArrowhead
    var targetArrowhead: FlowchartArrowhead
    var minimumRankSpan: Int
    var label = FlowchartLabelReference.none
    /// The identifier written before the link (`e1@-->`), empty when there is none.
    var identifier = MermaidTextRange.empty
}

/// Reads a link: `-->`, `---`, `-.->`, `==>`, `~~~` and their longer forms, a mark at either end (`<`, `>`, `o`, `x`),
/// the text in bars after it (`-->|text|`) or inside it (`-- text -->`, `-. text .->`, `== text ==>`), and an
/// identifier before it (`e1@-->`), which is read and left.
extension FlowchartParser {
    /// Reads a link at the position, or returns nil and moves nothing when none starts there.
    mutating func readLink() throws(MermaidDiagramReadError) -> FlowchartLink? {
        var lookahead = position
        var identifier = MermaidTextRange.empty
        // Pele's `LINK_ID`: the characters up to the last `@` of the run, which neither `{` nor `"` follows; spaces may
        // stand between it and the link, as Pele's link pattern starts with any.
        if let end = bytes.endOfLinkIdentifier(at: position) {
            identifier = MermaidTextRange(start: position, end: end - 1)
            lookahead = end
            while MermaidByte.isSpace(bytes[lookahead]) { lookahead += 1 }
        }
        guard var link = try readOperator(at: &lookahead) else { return nil }
        link.identifier = identifier
        position = lookahead
        skipSpaces()
        if bytes[position] == MermaidByte.verticalBar {
            let opening = position
            position += 1
            do {
                link.label = try readText(closedBy: FlowchartClosings("|"), openedAt: opening).0
            } catch .invalidSyntax(let line, .unclosedShape) {
                throw .invalidSyntax(line: line, problem: .unclosedEdgeLabel)
            }
        }
        return link
    }

    /// The operator itself, with any text written inside it.
    private mutating func readOperator(at lookahead: inout Int) throws(MermaidDiagramReadError) -> FlowchartLink? {
        let tildeCount = bytes.run(of: MermaidByte.tilde, at: lookahead)
        if tildeCount >= 3 {
            lookahead += tildeCount
            return FlowchartLink(stroke: .invisible, sourceArrowhead: .none, targetArrowhead: .none, minimumRankSpan: tildeCount - 2)
        }
        var end = lookahead
        var sourceArrowhead = FlowchartArrowhead.none
        // `<`, `o` or `x` right before the first `-` or `=`.
        let next = bytes[end + 1]
        if next == MermaidByte.hyphen || next == MermaidByte.equals, let arrowhead = Self.arrowhead(forMark: bytes[end], isSourceEnd: true) {
            sourceArrowhead = arrowhead
            end += 1
        }
        let link: FlowchartLink?
        switch bytes[end] {
        case MermaidByte.equals: link = try readRun(of: MermaidByte.equals, stroke: .thick, sourceArrowhead: sourceArrowhead, at: &end)
        case MermaidByte.hyphen where bytes[end + 1] == MermaidByte.period: link = try readDotted(sourceArrowhead: sourceArrowhead, at: &end)
        case MermaidByte.hyphen: link = try readRun(of: MermaidByte.hyphen, stroke: .solid, sourceArrowhead: sourceArrowhead, at: &end)
        default: link = nil
        }
        if link != nil { lookahead = end }
        return link
    }

    /// `-->`, `---`, `==>`, `===` and their longer forms; two signs followed by no mark start text inside the link.
    private mutating func readRun(of sign: UInt8, stroke: FlowchartEdgeStroke, sourceArrowhead: FlowchartArrowhead,
                                  at end: inout Int) throws(MermaidDiagramReadError) -> FlowchartLink? {
        let count = bytes.run(of: sign, at: end)
        guard count >= 2 else { return nil }
        let opening = end
        end += count
        if let arrowhead = Self.arrowhead(forMark: bytes[end], isSourceEnd: false) {
            end += 1
            return FlowchartLink(stroke: stroke, sourceArrowhead: sourceArrowhead, targetArrowhead: arrowhead, minimumRankSpan: count - 1)
        }
        if count >= 3 { return FlowchartLink(stroke: stroke, sourceArrowhead: sourceArrowhead, targetArrowhead: .none, minimumRankSpan: count - 2) }
        return try readTextInside(at: &end, closingSign: sign, stroke: stroke, sourceArrowhead: sourceArrowhead, openedAt: opening)
    }

    /// `-.->`, `-.-`, `-..->` and their text form `-. text .->`.
    private mutating func readDotted(sourceArrowhead: FlowchartArrowhead, at end: inout Int) throws(MermaidDiagramReadError) -> FlowchartLink? {
        let opening = end
        end += 1
        let periodCount = bytes.run(of: MermaidByte.period, at: end)
        end += periodCount
        guard bytes[end] == MermaidByte.hyphen else {
            return try readTextInside(at: &end, closingSign: MermaidByte.period, stroke: .dotted, sourceArrowhead: sourceArrowhead, openedAt: opening)
        }
        end += 1
        var targetArrowhead = FlowchartArrowhead.none
        if let arrowhead = Self.arrowhead(forMark: bytes[end], isSourceEnd: false) {
            targetArrowhead = arrowhead
            end += 1
        }
        return FlowchartLink(stroke: .dotted, sourceArrowhead: sourceArrowhead, targetArrowhead: targetArrowhead, minimumRankSpan: periodCount)
    }

    /// Text inside a link, up to the first closing operator on the same line, which gives the target's mark and the span.
    /// A run of periods that closes nothing is passed whole: no period inside it closes either.
    private mutating func readTextInside(at end: inout Int, closingSign: UInt8, stroke: FlowchartEdgeStroke, sourceArrowhead: FlowchartArrowhead,
                                         openedAt opening: Int) throws(MermaidDiagramReadError) -> FlowchartLink {
        let textStart = end
        while end < bytes.count, bytes.base[end] != MermaidByte.newline {
            let closing = closingSign == MermaidByte.period ? closingDotted(at: end) : closingRun(of: closingSign, at: end)
            if let (length, targetArrowhead, span) = closing {
                let label = edgeTextLabel(textStart..<end)
                end += length
                return FlowchartLink(stroke: stroke, sourceArrowhead: sourceArrowhead, targetArrowhead: targetArrowhead, minimumRankSpan: span, label: label)
            }
            end += closingSign == MermaidByte.period ? max(bytes.run(of: MermaidByte.period, at: end), 1) : 1
        }
        throw .invalidSyntax(line: bytes.line(at: opening), problem: .unclosedEdgeLabel)
    }

    /// The text inside a link as 0.7.0 made it: trimmed of spaces, tabs and line breaks, unquoted, then decoded. ASCII
    /// text is unquoted on its bytes, whose characters they are; other text through its characters.
    private mutating func edgeTextLabel(_ written: Range<Int>) -> FlowchartLabelReference {
        let trimmed = trimmedRange(from: written.lowerBound, to: written.upperBound)
        guard isASCII(trimmed) else {
            let unquoted = FlowchartTextSyntax.unquoted(bytes.string(from: trimmed.lowerBound, to: trimmed.upperBound))
            return decoded(DiagramLabelDecoder.label(from: unquoted.text, form: unquoted.form))
        }
        let unquoted = unquotedRange(trimmed)
        return writtenLabel(unquoted.range, form: unquoted.form)
    }

    /// The operator that closes text inside a solid or thick link: two or more signs and a mark, or three or more.
    private func closingRun(of sign: UInt8, at position: Int) -> (length: Int, arrowhead: FlowchartArrowhead, span: Int)? {
        let count = bytes.run(of: sign, at: position)
        guard count >= 2 else { return nil }
        if let arrowhead = Self.arrowhead(forMark: bytes[position + count], isSourceEnd: false) { return (count + 1, arrowhead, count - 1) }
        return count >= 3 ? (count, .none, count - 2) : nil
    }

    /// The operator that closes text inside a dotted link: `.-` or `.->` (and `..->` for a longer one).
    private func closingDotted(at position: Int) -> (length: Int, arrowhead: FlowchartArrowhead, span: Int)? {
        let periodCount = bytes.run(of: MermaidByte.period, at: position)
        guard periodCount >= 1, bytes[position + periodCount] == MermaidByte.hyphen else { return nil }
        if let arrowhead = Self.arrowhead(forMark: bytes[position + periodCount + 1], isSourceEnd: false) {
            return (periodCount + 2, arrowhead, periodCount)
        }
        return (periodCount + 1, .none, periodCount)
    }

    @inline(__always) private static func arrowhead(forMark mark: UInt8, isSourceEnd: Bool) -> FlowchartArrowhead? {
        switch mark {
        case MermaidByte.greaterThan: isSourceEnd ? nil : .arrow
        case MermaidByte.lessThan: isSourceEnd ? .arrow : nil
        case MermaidByte.letterO: .circle
        case MermaidByte.letterX: .cross
        default: nil
        }
    }
}
