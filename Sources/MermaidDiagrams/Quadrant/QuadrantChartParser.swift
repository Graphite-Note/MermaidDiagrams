/**
 * File: QuadrantChartParser.swift
 * -------------------------------
 * Layer: Core
 * Description: Reads a quadrant chart's statements from their tokens, as Mermaid's quadrant grammar does.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.4
 * Date: 25/11/2026
 */

/// Reads a quadrant chart's statements after its `quadrantChart` keyword from their tokens (`QuadrantChartLexer`), as
/// Mermaid's quadrant grammar does: `title …`, `x-axis low --> high` and `y-axis low --> high` (the high end may be
/// left out; an arrow with nothing after it is drawn after the low end's text), `quadrant-1` to `quadrant-4` and
/// their texts, points (`Name:::class: [x, y] radius: 10, color: #ff3300`), `classDef name styles`, accessibility
/// statements, each ending at a line break, a semicolon or the end of the text. A text is quoted, a Markdown string, or
/// words with the spaces and hyphens between them.
struct QuadrantChartParser {
    private let tokens: [QuadrantChartToken]
    private let statements: [MermaidAccessibilityStatement]
    private let bytes: [UInt8]
    private var index = 0
    private var builder: QuadrantChartBuilder
    /// The ranges of the styles of the point or class read last, kept from one to the next.
    private var styles: [MermaidTextRange] = []

    static func parse(_ cursor: MermaidTextCursor, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> QuadrantChart {
        var parser = QuadrantChartParser(tokens: try QuadrantChartLexer.tokens(after: cursor), bytes: cursor.bytes,
                                         builder: QuadrantChartBuilder(bytes: cursor.bytes, limits: limits))
        try parser.readStatements()
        var chart = parser.builder.chart
        chart.options = QuadrantChartOptions(MermaidConfigurationOptions(section: "quadrantChart", in: cursor))
        return chart
    }

    private init(tokens: QuadrantChartTokens, bytes: [UInt8], builder: QuadrantChartBuilder) {
        self.tokens = tokens.tokens
        statements = tokens.statements
        self.bytes = bytes
        self.builder = builder
    }

    private var current: QuadrantChartToken? {
        index < tokens.count ? tokens[index] : nil
    }

    private mutating func readStatements() throws(MermaidDiagramReadError) {
        while index < tokens.count {
            while current?.kind == .space { index += 1 }
            guard let token = current else { return }
            try readStatement(startingWith: token)
            guard let end = current else { return }
            guard end.kind == .lineBreak || end.kind == .semicolon else { throw unexpected(end) }
            index += 1
        }
    }

    /// The statement `token` starts; a line break or a semicolon starts none.
    private mutating func readStatement(startingWith token: QuadrantChartToken) throws(MermaidDiagramReadError) {
        if token.kind == .classDefinition {
            try readClassDefinition()
        } else if token.kind == .xAxis || token.kind == .yAxis {
            try readAxis(isHorizontal: token.kind == .xAxis)
        } else if let quadrant = QuadrantChartTokenKind.quadrants.firstIndex(of: token.kind) {
            index += 1
            builder.setQuadrantLabel(at: quadrant, try requiredText(after: token))
        } else if token.kind == .title {
            index += 1
            builder.setTitle(String(decoding: bytes[token.content.lowerBound..<token.content.upperBound], as: UTF8.self))
        } else if token.kind == .accessibility {
            index += 1
            builder.apply(statements[token.second.lowerBound])
        } else if QuadrantChartTokenKind.textStarts.contains(token.kind) {
            try readPoint(startingWith: token)
        }
    }

    /// `x-axis` or `y-axis`, a text, then `-->` and the high end's text; `-->` with nothing after it puts an arrow after
    /// the low end's text, as in Mermaid.
    private mutating func readAxis(isHorizontal: Bool) throws(MermaidDiagramReadError) {
        let keyword = tokens[index]
        index += 1
        var low = try requiredText(after: keyword)
        var high: QuadrantChartText?
        if current?.kind == .axisArrow {
            index += 1
            high = readText()
            if high == nil { low.append(Self.arrowAfterText, in: bytes) }
        }
        builder.setAxisLabels(low: low, high: high, isHorizontal: isHorizontal)
    }

    /// A point: its text, its class after `:::`, its coordinates, and the styles after them.
    private mutating func readPoint(startingWith token: QuadrantChartToken) throws(MermaidDiagramReadError) {
        guard let label = readText() else { return }
        var className: String?
        if let classToken = current, classToken.kind == .className {
            className = String(decoding: bytes[classToken.content.lowerBound..<classToken.content.upperBound], as: UTF8.self)
            index += 1
        }
        guard let pointToken = current, pointToken.kind == .point else {
            throw .invalidSyntax(line: current?.line ?? token.line, problem: .expectedPointCoordinates)
        }
        index += 1
        styles.removeAll(keepingCapacity: true)
        if current.map({ next in QuadrantChartTokenKind.stylePieces.contains(next.kind) }) == true { try readStyles() }
        try builder.addPoint(QuadrantChartWrittenPoint(label: label, className: className, xCoordinate: pointToken.content,
                                                       yCoordinate: pointToken.second), styles: styles, line: token.line)
    }

    /// `classDef`, one space, the class's name, one space, and its styles.
    private mutating func readClassDefinition() throws(MermaidDiagramReadError) {
        let keyword = tokens[index]
        index += 1
        try expectSpace()
        let nameStart = index
        while let piece = current, QuadrantChartTokenKind.classNamePieces.contains(piece.kind) { index += 1 }
        let name = writtenRange(fromToken: nameStart)
        guard !name.isEmpty else { throw current.map(unexpected) ?? .invalidSyntax(line: keyword.line, problem: .expectedName) }
        try expectSpace()
        styles.removeAll(keepingCapacity: true)
        try readStyles()
        try builder.addClass(String(decoding: bytes[name.lowerBound..<name.upperBound], as: UTF8.self), styles: styles, line: keyword.line)
    }

    /// Styles separated by commas, each made of letters, digits, colons, spaces, `#` and hyphens, without the spaces at
    /// its ends: their ranges, added to `styles`.
    private mutating func readStyles() throws(MermaidDiagramReadError) {
        while true {
            let styleStart = index
            while let piece = current, QuadrantChartTokenKind.stylePieces.contains(piece.kind) { index += 1 }
            guard index > styleStart else { throw .invalidSyntax(line: current?.line ?? tokens[index - 1].line, problem: .expectedPointStyle) }
            styles.append(writtenRange(fromToken: styleStart))
            guard current?.kind == .comma else { return }
            index += 1
        }
    }

    /// A text: a quoted or Markdown string or a word, then words, spaces and hyphens, without the spaces at its ends, as
    /// Mermaid's database keeps it. Nil when none starts here.
    private mutating func readText() -> QuadrantChartText? {
        guard let first = current, QuadrantChartTokenKind.textStarts.contains(first.kind) else { return nil }
        let firstIndex = index
        index += 1
        while let piece = current, QuadrantChartTokenKind.textContinuations.contains(piece.kind) { index += 1 }
        guard first.kind == .string || first.kind == .markdownString else {
            return QuadrantChartText(range: writtenRange(fromToken: firstIndex), isMarkdown: false)
        }
        let quoted = first.content
        let restEnd = tokens[index - 1].end
        // A quoted text alone, ASCII, is its bytes trimmed as JavaScript trims them; with words after it, or beyond
        // ASCII, it is the text and the words joined and trimmed.
        if first.end == restEnd, !bytes[quoted.lowerBound..<quoted.upperBound].contains(where: { byte in byte >= 0x80 }) {
            var start = quoted.lowerBound
            var end = quoted.upperBound
            while start < end, Self.isJavaScriptASCIIWhitespace(bytes[start]) { start += 1 }
            while end > start, Self.isJavaScriptASCIIWhitespace(bytes[end - 1]) { end -= 1 }
            return QuadrantChartText(range: MermaidTextRange(start: start, end: end), isMarkdown: first.kind == .markdownString)
        }
        let text = String(decoding: bytes[quoted.lowerBound..<quoted.upperBound], as: UTF8.self)
            + String(decoding: bytes[first.end..<restEnd], as: UTF8.self)
        return QuadrantChartText(text: Self.trimmed(text), isMarkdown: first.kind == .markdownString)
    }

    /// The range of the tokens from `firstIndex` up to the current one, without the spaces at its ends. They follow one
    /// another in the text, since only a comment is skipped between tokens and a comment ends its line.
    private func writtenRange(fromToken firstIndex: Int) -> MermaidTextRange {
        guard index > firstIndex else { return .empty }
        var start = tokens[firstIndex].start
        var end = tokens[index - 1].end
        while start < end, Self.isSpaceOrLineBreak(bytes[start]) { start += 1 }
        while end > start, Self.isSpaceOrLineBreak(bytes[end - 1]) { end -= 1 }
        return MermaidTextRange(start: start, end: end)
    }

    /// The ASCII white space JavaScript's `trim` removes: a tab, a line feed, a vertical tab, a form feed, a carriage
    /// return or a space, as Unicode's white space property holds them.
    private static func isJavaScriptASCIIWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || (0x09...0x0D).contains(byte)
    }

    private static func isSpaceOrLineBreak(_ byte: UInt8) -> Bool {
        MermaidByte.isWhitespace(byte) || byte == verticalTab || byte == formFeed
    }

    /// `text` without the white space at its ends, as JavaScript's `trim` leaves it.
    private static func trimmed(_ text: String) -> String {
        var scalars = Substring(text).unicodeScalars
        while let first = scalars.first, first.properties.isWhitespace { scalars = scalars.dropFirst() }
        while let last = scalars.last, last.properties.isWhitespace { scalars = scalars.dropLast() }
        return String(Substring(scalars))
    }

    /// The text after `keyword`, which must have one.
    private mutating func requiredText(after keyword: QuadrantChartToken) throws(MermaidDiagramReadError) -> QuadrantChartText {
        guard let text = readText() else { throw .invalidSyntax(line: current?.line ?? keyword.line, problem: .expectedAxisOrQuadrantText) }
        return text
    }

    /// One space or tab, as `classDef` takes one before and after the class's name.
    private mutating func expectSpace() throws(MermaidDiagramReadError) {
        guard let space = current, space.kind == .space else {
            throw current.map(unexpected) ?? .invalidSyntax(line: tokens[index - 1].line, problem: .expectedName)
        }
        index += 1
    }

    /// The error of a token where it does not belong: its first characters, after the spaces a keyword takes.
    private func unexpected(_ token: QuadrantChartToken) -> MermaidDiagramReadError {
        var cursor = MermaidTextCursor(bytes: bytes)
        cursor.advance(by: token.start)
        cursor.skipSpaces()
        return .invalidSyntax(line: token.line, problem: .unexpectedText(cursor.excerpt()))
    }

    /// What Mermaid writes after an axis's low end when its arrow has no high end, there without the space after it,
    /// which Mermaid's database trims.
    static let arrowAfterText = " ⟶"
    private static let verticalTab: UInt8 = 0x0B
    private static let formFeed: UInt8 = 0x0C
}

/// A text of a quadrant chart as written, and whether it is a Markdown string: the range of the bytes it is, or, for a
/// text a quotation and words make or an axis's arrow ends, the text made.
struct QuadrantChartText {
    private(set) var range: MermaidTextRange
    private(set) var text: String?
    let isMarkdown: Bool

    init(range: MermaidTextRange, isMarkdown: Bool) {
        self.range = range
        text = nil
        self.isMarkdown = isMarkdown
    }

    init(text: String, isMarkdown: Bool) {
        range = .empty
        self.text = text
        self.isMarkdown = isMarkdown
    }

    /// Whether the text has no character.
    var isEmpty: Bool { text.map(\.isEmpty) ?? range.isEmpty }

    /// Adds `suffix` after the text, whose bytes are `bytes`' when it is a range of them.
    mutating func append(_ suffix: String, in bytes: [UInt8]) {
        text = (text ?? String(decoding: bytes[range.lowerBound..<range.upperBound], as: UTF8.self)) + suffix
    }
}

/// A point as its statement writes it, before its coordinates and styles are read: its coordinates as the ranges of
/// their bytes.
struct QuadrantChartWrittenPoint {
    let label: QuadrantChartText
    let className: String?
    let xCoordinate: MermaidTextRange
    let yCoordinate: MermaidTextRange
}
