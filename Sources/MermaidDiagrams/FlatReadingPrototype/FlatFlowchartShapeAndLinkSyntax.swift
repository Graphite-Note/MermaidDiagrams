/**
 * File: FlatFlowchartShapeAndLinkSyntax.swift
 * -------------------------------------------
 * Layer: Core (design prototype, not for merging as is)
 * Description: A node's shape and text, and a link with its marks, length and text, read on bytes as
 *              FlowchartNodeSyntax, FlowchartTextSyntax and FlowchartLinkSyntax read them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import Foundation

struct FlatNodeDefinition {
    var shape: FlowchartNodeShape?
    var label: FlatLabel?
    var hasBlankWrittenLabel = true
    var asksForCollapsedView = false
    /// Whether the attributes wrote an icon's or a picture's attributes, kept in the reader's `writtenAssetAttributes`.
    var hasAssetAttributes = false
}

/// A set of ASCII bytes as two words.
struct FlatByteMask {
    var low: UInt64 = 0
    var high: UInt64 = 0

    static let brackets: FlatByteMask = {
        var mask = FlatByteMask()
        for byte in Array("()[]{}".utf8) { mask.insert(byte) }
        return mask
    }()

    @inline(__always) mutating func insert(_ byte: UInt8) {
        if byte < 64 { low |= 1 &<< UInt64(byte) } else if byte < 128 { high |= 1 &<< UInt64(byte - 64) }
    }

    @inline(__always) func contains(_ byte: UInt8) -> Bool {
        byte < 64 ? (low &>> UInt64(byte)) & 1 != 0 : byte < 128 && (high &>> UInt64(byte - 64)) & 1 != 0
    }
}

struct FlatLink {
    var stroke: FlowchartEdgeStroke
    var sourceArrowhead: FlowchartArrowhead
    var targetArrowhead: FlowchartArrowhead
    var minimumRankSpan: Int
    var label: FlatLabel = .none
    var identifierStart = 0
    var identifierEnd = 0
}

/// Up to three closings of a shape's text, each up to three bytes, with no list made.
struct FlatClosings {
    var first: (UInt8, UInt8, UInt8, Int)
    var second: (UInt8, UInt8, UInt8, Int) = (0, 0, 0, 0)
    var third: (UInt8, UInt8, UInt8, Int) = (0, 0, 0, 0)
    var count = 1

    init(_ text: StaticString) { first = Self.closing(text) }

    init(_ first: StaticString, _ second: StaticString) {
        self.first = Self.closing(first)
        self.second = Self.closing(second)
        count = 2
    }

    init(_ first: StaticString, _ second: StaticString, _ third: StaticString) {
        self.first = Self.closing(first)
        self.second = Self.closing(second)
        self.third = Self.closing(third)
        count = 3
    }

    private static func closing(_ text: StaticString) -> (UInt8, UInt8, UInt8, Int) {
        let start = text.utf8Start
        let length = text.utf8CodeUnitCount
        return (start[0], length > 1 ? start[1] : 0, length > 2 ? start[2] : 0, length)
    }

    @inline(__always) private static func matches(_ closing: (UInt8, UInt8, UInt8, Int), in bytes: FlatBytes, at position: Int) -> Bool {
        guard bytes[position] == closing.0 else { return false }
        if closing.3 > 1, bytes[position + 1] != closing.1 { return false }
        if closing.3 > 2, bytes[position + 2] != closing.2 { return false }
        return position + closing.3 <= bytes.count
    }

    /// The index of the first closing at `position`, or nil.
    @inline(__always) func match(in bytes: FlatBytes, at position: Int) -> Int? {
        if Self.matches(first, in: bytes, at: position) { return 0 }
        if count > 1, Self.matches(second, in: bytes, at: position) { return 1 }
        if count > 2, Self.matches(third, in: bytes, at: position) { return 2 }
        return nil
    }

    /// The bytes at which plain text in `state` may stop.
    func stopMask(state: FlowchartTextState) -> FlatByteMask {
        var mask = FlatByteMask.brackets
        if state == .text { mask.insert(MermaidByte.verticalBar) }
        if state != .trapezoid { mask.insert(MermaidByte.quotationMark) }
        mask.insert(first.0)
        if count > 1 { mask.insert(second.0) }
        if count > 2 { mask.insert(third.0) }
        return mask
    }

    func length(_ index: Int) -> Int {
        index == 0 ? first.3 : index == 1 ? second.3 : third.3
    }
}

extension FlatFlowchartReader {
    // MARK: Shapes

    mutating func readShape() throws(FlatReadingBailOut) -> FlatNodeDefinition? {
        let byte = bytes[position]
        let opening: Int
        let closings: FlatClosings
        let shapes: (FlowchartNodeShape, FlowchartNodeShape, FlowchartNodeShape)
        var state = FlowchartTextState.text
        switch byte {
        case 0x28: // (
            switch bytes[position + 1] {
            case 0x28 where bytes[position + 2] == 0x28: (opening, closings, shapes) = (3, FlatClosings(")))"), (.doubleCircle, .doubleCircle, .doubleCircle))
            case 0x28: (opening, closings, shapes) = (2, FlatClosings("))"), (.circle, .circle, .circle))
            case MermaidByte.openingBracket: (opening, closings, shapes) = (2, FlatClosings("])"), (.stadium, .stadium, .stadium))
            case MermaidByte.hyphen:
                (opening, closings, shapes) = (2, FlatClosings("-)", "/)", "))"), (.ellipse, .ellipse, .ellipse))
                state = .ellipse
            default: (opening, closings, shapes) = (1, FlatClosings(")"), (.roundedRectangle, .roundedRectangle, .roundedRectangle))
            }
        case MermaidByte.openingBracket:
            switch bytes[position + 1] {
            case MermaidByte.verticalBar: return try readRectangleWithProperty()
            case MermaidByte.openingBracket: (opening, closings, shapes) = (2, FlatClosings("]]"), (.subroutine, .subroutine, .subroutine))
            case 0x28: (opening, closings, shapes) = (2, FlatClosings(")]"), (.cylinder, .cylinder, .cylinder))
            case 0x2F:
                (opening, closings, shapes) = (2, FlatClosings("/]", "\\]"), (.leanRight, .trapezoid, .trapezoid))
                state = .trapezoid
            case 0x5C:
                (opening, closings, shapes) = (2, FlatClosings("\\]", "/]"), (.leanLeft, .invertedTrapezoid, .invertedTrapezoid))
                state = .trapezoid
            default: (opening, closings, shapes) = (1, FlatClosings("]"), (.rectangle, .rectangle, .rectangle))
            }
        case MermaidByte.greaterThan: (opening, closings, shapes) = (1, FlatClosings("]"), (.asymmetric, .asymmetric, .asymmetric))
        case MermaidByte.openingBrace:
            if bytes[position + 1] == MermaidByte.openingBrace {
                (opening, closings, shapes) = (2, FlatClosings("}}"), (.hexagon, .hexagon, .hexagon))
            } else {
                (opening, closings, shapes) = (1, FlatClosings("}"), (.diamond, .diamond, .diamond))
            }
        default: return nil
        }
        position += opening
        let (label, closing) = try readText(closedBy: closings, state: state)
        return FlatNodeDefinition(shape: closing == 0 ? shapes.0 : closing == 1 ? shapes.1 : shapes.2, label: label)
    }

    private mutating func readRectangleWithProperty() throws(FlatReadingBailOut) -> FlatNodeDefinition {
        position += 2
        for separator in [MermaidByte.colon, MermaidByte.verticalBar] {
            let wordStart = position
            while position < bytes.count, case let byte = bytes.base[position], byte != separator, !MermaidByte.isSpace(byte),
                  !MermaidByte.endsStatement(byte), byte != MermaidByte.colon, byte != MermaidByte.verticalBar,
                  byte != MermaidByte.closingBracket { position += 1 }
            guard position > wordStart, bytes[position] == separator, position < bytes.count else { throw FlatReadingBailOut() }
            position += 1
        }
        let (label, _) = try readText(closedBy: FlatClosings("]"), state: .text)
        return FlatNodeDefinition(shape: .rectangle, label: label)
    }

    // MARK: Text

    /// FlowchartTextSyntax.readText: the label and which closing ended it.
    mutating func readText(closedBy closings: FlatClosings, state: FlowchartTextState) throws(FlatReadingBailOut) -> (FlatLabel, Int) {
        if startsInvisibleLink() { throw FlatReadingBailOut() }
        var stringRange: Range<Int>?
        var form = DiagramLabelDecoder.Form.plain
        var hasToken = false
        if bytes[position] == MermaidByte.quotationMark {
            let (range, stringForm) = try readString()
            stringRange = range
            form = stringForm
            hasToken = !range.isEmpty
        }
        let plainStart = position
        // Bytes that may end plain text: the state's own and the closings' first bytes; any other is passed by a table.
        let stops = closings.stopMask(state: state)
        while position < bytes.count {
            let byte = bytes.base[position]
            if stops.contains(byte) {
                if closings.match(in: bytes, at: position) != nil || state.endsPlainText(byte) { break }
            }
            position += 1
        }
        let plainEnd = position
        if plainEnd > plainStart { hasToken = true }
        guard let closing = closings.match(in: bytes, at: position), hasToken else { throw FlatReadingBailOut() }
        position += closings.length(closing)
        let written: Range<Int>
        if let stringRange {
            guard plainEnd == plainStart else {
                // A string followed by plain text: their joined text is decoded as the present reader decodes it.
                let joined = string(from: stringRange.lowerBound, to: stringRange.upperBound) + string(from: plainStart, to: plainEnd)
                return (decoded(DiagramLabelDecoder.label(from: Self.foundationTrimmed(joined), form: form)), closing)
            }
            written = stringRange
        } else {
            written = plainStart..<plainEnd
        }
        return (labelOfWrittenText(written, form: form), closing)
    }

    /// The text of brackets after FlowchartTextSyntax's trimming: kept when its ends are printable ASCII, else
    /// trimmed of Foundation's white space and line breaks (ASCII ones on bytes; beyond ASCII through String).
    private mutating func labelOfWrittenText(_ written: Range<Int>, form: DiagramLabelDecoder.Form) -> FlatLabel {
        var start = written.lowerBound
        var end = written.upperBound
        if start < end, Self.isPrintableASCII(bytes.base[start]), Self.isPrintableASCII(bytes.base[end - 1]) {
            return writtenLabel(FlatTextRange(start: Int32(start), end: Int32(end)), form: form)
        }
        while start < end, Self.isASCIIWhitespace(bytes.base[start]) { start += 1 }
        while end > start, Self.isASCIIWhitespace(bytes.base[end - 1]) { end -= 1 }
        if start < end, bytes.base[start] >= 0x80 || bytes.base[end - 1] >= 0x80 {
            let text = Self.foundationTrimmed(string(from: written.lowerBound, to: written.upperBound))
            return decoded(DiagramLabelDecoder.label(from: text, form: form))
        }
        return writtenLabel(FlatTextRange(start: Int32(start), end: Int32(end)), form: form)
    }

    static func foundationTrimmed(_ text: String) -> String {
        MermaidByte.startsAndEndsWithPrintableASCII(text) ? text : text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @inline(__always) static func isPrintableASCII(_ byte: UInt8) -> Bool {
        byte > 0x20 && byte < 0x7F
    }

    private mutating func readString() throws(FlatReadingBailOut) -> (Range<Int>, DiagramLabelDecoder.Form) {
        position += 1
        let isMarkdown = bytes[position] == MermaidByte.graveAccent
        if isMarkdown { position += 1 }
        let start = position
        while position < bytes.count, case let byte = bytes.base[position], byte != MermaidByte.quotationMark,
              !(isMarkdown && byte == MermaidByte.graveAccent) { position += 1 }
        let end = position
        if isMarkdown {
            guard bytes[position] == MermaidByte.graveAccent, bytes[position + 1] == MermaidByte.quotationMark else { throw FlatReadingBailOut() }
            position += 2
            return (start..<end, .markdown)
        }
        guard position < bytes.count else { throw FlatReadingBailOut() }
        position += 1
        return (start..<end, .plain)
    }

    private func startsInvisibleLink() -> Bool {
        var lookahead = position
        while lookahead < bytes.count {
            let byte = bytes.base[lookahead]
            if byte == MermaidByte.tilde { return bytes[lookahead + 1] == MermaidByte.tilde && bytes[lookahead + 2] == MermaidByte.tilde }
            let length = bytes.whitespaceLength(at: lookahead)
            guard length > 0 else { return false }
            lookahead += length
        }
        return false
    }

    /// The label DiagramLabelDecoder makes of the text at `raw`, as it receives it: an empty text, or one its byte test
    /// finds unmarked, is the range trimmed as JavaScript trims; anything else is decoded now.
    mutating func writtenLabel(_ raw: FlatTextRange, form: DiagramLabelDecoder.Form) -> FlatLabel {
        let rawBytes = UnsafeBufferPointer(rebasing: bytes.buffer[Int(raw.start)..<Int(raw.end)])
        if rawBytes.isEmpty { return FlatLabel(kind: .line, range: raw) }
        guard DiagramLabelLineBreaks.isUnmarked(rawBytes, isLiteral: form == .literal) else {
            switch form {
            case .plain: return FlatLabel(kind: .writtenPlain, range: raw)
            case .markdown: return FlatLabel(kind: .writtenMarkdown, range: raw)
            case .literal: return decoded(DiagramLabelDecoder.label(from: string(from: Int(raw.start), to: Int(raw.end)), form: form))
            }
        }
        var start = Int(raw.start)
        var end = Int(raw.end)
        while start < end, Self.isASCIIWhitespace(bytes.base[start]) { start += 1 }
        while end > start, Self.isASCIIWhitespace(bytes.base[end - 1]) { end -= 1 }
        if start < end, bytes.base[start] >= 0x80 || bytes.base[end - 1] >= 0x80 {
            return decoded(DiagramLabel(lines: [JavaScriptStringTrimming.trimmed(string(from: Int(raw.start), to: Int(raw.end)))]))
        }
        return FlatLabel(kind: .line, range: FlatTextRange(start: Int32(start), end: Int32(end)))
    }

    // MARK: Links

    mutating func readLink() throws(FlatReadingBailOut) -> FlatLink? {
        var lookahead = position
        var identifierStart = 0
        var identifierEnd = 0
        if let end = bytes.endOfLinkIdentifier(at: position) {
            identifierStart = position
            identifierEnd = end - 1
            lookahead = end
            while MermaidByte.isSpace(bytes[lookahead]) { lookahead += 1 }
        }
        guard var link = try readOperator(at: &lookahead) else { return nil }
        link.identifierStart = identifierStart
        link.identifierEnd = identifierEnd
        position = lookahead
        skipSpaces()
        if bytes[position] == MermaidByte.verticalBar {
            position += 1
            link.label = try readText(closedBy: FlatClosings("|"), state: .text).0
        }
        return link
    }

    private mutating func readOperator(at lookahead: inout Int) throws(FlatReadingBailOut) -> FlatLink? {
        let tildeCount = bytes.run(of: MermaidByte.tilde, at: lookahead)
        if tildeCount >= 3 {
            lookahead += tildeCount
            return FlatLink(stroke: .invisible, sourceArrowhead: .none, targetArrowhead: .none, minimumRankSpan: tildeCount - 2)
        }
        var operatorEnd = lookahead
        var sourceArrowhead = FlowchartArrowhead.none
        let next = bytes[operatorEnd + 1]
        if operatorEnd + 1 < bytes.count, next == MermaidByte.hyphen || next == MermaidByte.equals,
           let arrowhead = Self.arrowhead(forMark: bytes[operatorEnd], isSourceEnd: true) {
            sourceArrowhead = arrowhead
            operatorEnd += 1
        }
        let link: FlatLink?
        switch bytes[operatorEnd] {
        case MermaidByte.equals: link = try readRun(of: MermaidByte.equals, stroke: .thick, sourceArrowhead: sourceArrowhead, at: &operatorEnd)
        case MermaidByte.hyphen where bytes[operatorEnd + 1] == MermaidByte.period: link = try readDotted(sourceArrowhead: sourceArrowhead, at: &operatorEnd)
        case MermaidByte.hyphen: link = try readRun(of: MermaidByte.hyphen, stroke: .solid, sourceArrowhead: sourceArrowhead, at: &operatorEnd)
        default: link = nil
        }
        if link != nil { lookahead = operatorEnd }
        return link
    }

    private mutating func readRun(of sign: UInt8, stroke: FlowchartEdgeStroke, sourceArrowhead: FlowchartArrowhead,
                                  at end: inout Int) throws(FlatReadingBailOut) -> FlatLink? {
        let count = bytes.run(of: sign, at: end)
        guard count >= 2 else { return nil }
        end += count
        if let arrowhead = Self.arrowhead(forMark: bytes[end], isSourceEnd: false) {
            end += 1
            return FlatLink(stroke: stroke, sourceArrowhead: sourceArrowhead, targetArrowhead: arrowhead, minimumRankSpan: count - 1)
        }
        if count >= 3 { return FlatLink(stroke: stroke, sourceArrowhead: sourceArrowhead, targetArrowhead: .none, minimumRankSpan: count - 2) }
        return try readTextInside(at: &end, closingSign: sign, stroke: stroke, sourceArrowhead: sourceArrowhead)
    }

    private mutating func readDotted(sourceArrowhead: FlowchartArrowhead, at end: inout Int) throws(FlatReadingBailOut) -> FlatLink? {
        end += 1
        let periodCount = bytes.run(of: MermaidByte.period, at: end)
        end += periodCount
        guard bytes[end] == MermaidByte.hyphen else {
            return try readTextInside(at: &end, closingSign: MermaidByte.period, stroke: .dotted, sourceArrowhead: sourceArrowhead)
        }
        end += 1
        var targetArrowhead = FlowchartArrowhead.none
        if let arrowhead = Self.arrowhead(forMark: bytes[end], isSourceEnd: false) {
            targetArrowhead = arrowhead
            end += 1
        }
        return FlatLink(stroke: .dotted, sourceArrowhead: sourceArrowhead, targetArrowhead: targetArrowhead, minimumRankSpan: periodCount)
    }

    /// `-- text -->`, `== text ==>`, `-. text .->`: the text up to the closing run, on its line.
    private mutating func readTextInside(at end: inout Int, closingSign: UInt8, stroke: FlowchartEdgeStroke,
                                         sourceArrowhead: FlowchartArrowhead) throws(FlatReadingBailOut) -> FlatLink {
        let textStart = end
        while end < bytes.count, bytes.base[end] != MermaidByte.newline {
            if let (length, targetArrowhead, span) = closingSign == MermaidByte.period ? closingDotted(at: end) : closingRun(of: closingSign, at: end) {
                let label = edgeTextLabel(from: textStart, to: end)
                end += length
                return FlatLink(stroke: stroke, sourceArrowhead: sourceArrowhead, targetArrowhead: targetArrowhead, minimumRankSpan: span, label: label)
            }
            end += 1
        }
        throw FlatReadingBailOut()
    }

    /// The cursor's trimmedText, unquoted (FlowchartTextSyntax.unquoted), then decoded: on bytes for ASCII text.
    private mutating func edgeTextLabel(from textStart: Int, to textEnd: Int) -> FlatLabel {
        var start = textStart
        var end = textEnd
        while start < end, MermaidByte.isWhitespace(bytes.base[start]) { start += 1 }
        while end > start, MermaidByte.isWhitespace(bytes.base[end - 1]) { end -= 1 }
        for index in start..<end where bytes.base[index] >= 0x80 {
            let written = FlowchartTextSyntax.unquoted(string(from: start, to: end))
            return decoded(DiagramLabelDecoder.label(from: written.text, form: written.form))
        }
        var form = DiagramLabelDecoder.Form.plain
        if end - start >= 2, bytes.base[start] == MermaidByte.quotationMark, bytes.base[end - 1] == MermaidByte.quotationMark {
            start += 1
            end -= 1
            if end - start >= 2, bytes.base[start] == MermaidByte.graveAccent, bytes.base[end - 1] == MermaidByte.graveAccent {
                start += 1
                end -= 1
                form = .markdown
            }
        }
        return writtenLabel(FlatTextRange(start: Int32(start), end: Int32(end)), form: form)
    }

    private func closingRun(of sign: UInt8, at position: Int) -> (length: Int, arrowhead: FlowchartArrowhead, span: Int)? {
        let count = bytes.run(of: sign, at: position)
        guard count >= 2 else { return nil }
        if let arrowhead = Self.arrowhead(forMark: bytes[position + count], isSourceEnd: false) { return (count + 1, arrowhead, count - 1) }
        return count >= 3 ? (count, .none, count - 2) : nil
    }

    private func closingDotted(at position: Int) -> (length: Int, arrowhead: FlowchartArrowhead, span: Int)? {
        let periodCount = bytes.run(of: MermaidByte.period, at: position)
        guard periodCount >= 1, bytes[position + periodCount] == MermaidByte.hyphen else { return nil }
        if let arrowhead = Self.arrowhead(forMark: bytes[position + periodCount + 1], isSourceEnd: false) { return (periodCount + 2, arrowhead, periodCount) }
        return (periodCount + 1, .none, periodCount)
    }

    @inline(__always) static func arrowhead(forMark mark: UInt8, isSourceEnd: Bool) -> FlowchartArrowhead? {
        switch mark {
        case MermaidByte.greaterThan: isSourceEnd ? nil : .arrow
        case MermaidByte.lessThan: isSourceEnd ? .arrow : nil
        case MermaidByte.letterO: .circle
        case MermaidByte.letterX: .cross
        default: nil
        }
    }
}
