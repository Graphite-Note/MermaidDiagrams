/**
 * File: PacketDiagramParser.swift
 * -------------------------------
 * Layer: Core
 * Description: Reads a packet diagram's statements after its `packet` keyword: its fields and its titles.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// Reads the statements after the `packet` or `packet-beta` keyword as Mermaid's grammar does, each ending its line: a
/// field (`0-15: "Source Port"`, `106: "URG"`, `+16: "Length"`), then `title …`, `accTitle: …`, `accDescr: …` or
/// `accDescr { … }`. `%%` starts a comment. The fields are checked as Mermaid checks them: contiguous from bit 0, no
/// range ending before it starts, no `+0`.
struct PacketDiagramParser {
    private var cursor: MermaidTextCursor
    private var diagram = PacketDiagram()
    private var statements = MermaidTitleStatements()
    private let limits: MermaidDiagramLimits
    /// The last bit of the fields so far, -1 before the first.
    private var lastBit = -1

    /// No number is read beyond this one, which is where JavaScript's numbers stop counting whole bits.
    private static let largestBit = 9_007_199_254_740_992

    private init(cursor: MermaidTextCursor, limits: MermaidDiagramLimits) {
        self.cursor = cursor
        self.limits = limits
    }

    static func parse(_ cursor: MermaidTextCursor, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> PacketDiagram {
        var parser = PacketDiagramParser(cursor: cursor, limits: limits)
        parser.diagram.options = PacketOptions(MermaidConfigurationOptions(section: "packet", in: cursor.bytes))
        try parser.readStatements()
        parser.diagram.title = parser.statements.title
        parser.diagram.accessibilityTitle = parser.statements.accessibilityTitle
        parser.diagram.accessibilityDescription = parser.statements.accessibilityDescription
        return parser.diagram
    }

    private mutating func readStatements() throws(MermaidDiagramReadError) {
        while true {
            MermaidTitleStatements.skipBlank(&cursor)
            guard let byte = cursor.peek() else { return }
            if MermaidByte.isDigit(byte) || byte == UInt8(ascii: "+") {
                try readField()
            } else if try !statements.read(&cursor) {
                throw .invalidSyntax(line: cursor.line, problem: .unexpectedText(cursor.excerpt()))
            }
            try MermaidTitleStatements.expectLineEnd(&cursor)
        }
    }

    /// `first`, `first-last` or `+bits`, then `:` and the label between quotation marks.
    private mutating func readField() throws(MermaidDiagramReadError) {
        let line = cursor.line
        var firstBit: Int?
        var lastBitWritten: Int?
        var bitCount: Int?
        if cursor.peek() == UInt8(ascii: "+") {
            cursor.advance()
            cursor.skipSpaces()
            bitCount = try readNumber()
        } else {
            firstBit = try readNumber()
            cursor.skipSpaces()
            // A block of front matter is dropped wherever the lexer meets it, between a field's number and its dash too.
            if MermaidTitleStatements.skipFrontMatterBlock(&cursor) { cursor.skipSpaces() }
            if cursor.peek() == MermaidByte.hyphen {
                cursor.advance()
                cursor.skipSpaces()
                lastBitWritten = try readNumber()
            }
        }
        cursor.skipSpaces()
        guard cursor.peek() == MermaidByte.colon else { throw .invalidSyntax(line: cursor.line, problem: .packet(.expectedColon)) }
        cursor.advance()
        cursor.skipSpaces()
        guard let quotation = cursor.peek(), quotation == MermaidByte.quotationMark || quotation == PieChartStatementText.apostrophe else {
            throw .invalidSyntax(line: cursor.line, problem: .packet(.expectedFieldLabel))
        }
        let label = try PieChartStatementText.readString(&cursor)
        try add(label: label, firstBit: firstBit, lastBitWritten: lastBitWritten, bitCount: bitCount, line: line)
    }

    /// Checks the field as Mermaid's database does, in its order, and adds it.
    private mutating func add(label: String, firstBit written: Int?, lastBitWritten: Int?, bitCount: Int?, line: Int) throws(MermaidDiagramReadError) {
        if let written, let lastBitWritten, lastBitWritten < written {
            throw .invalidSyntax(line: line, problem: .packet(.endBeforeStart(firstBit: written, lastBit: lastBitWritten)))
        }
        let firstBit = written ?? lastBit + 1
        guard firstBit == lastBit + 1 else {
            throw .invalidSyntax(line: line, problem: .packet(.notContiguous(firstBit: firstBit, lastBit: lastBitWritten ?? firstBit,
                                                                              expectedFirstBit: lastBit + 1)))
        }
        guard bitCount != 0 else { throw .invalidSyntax(line: line, problem: .packet(.zeroBitField(firstBit: firstBit))) }
        let end = lastBitWritten ?? min(firstBit + (bitCount ?? 1) - 1, Self.largestBit)
        guard diagram.fields.count < limits.maximumNodeCount, end / diagram.options.bitsPerRow < limits.maximumNodeCount else {
            throw .tooManyNodes(limit: limits.maximumNodeCount)
        }
        lastBit = end
        diagram.fields.append(PacketField(label: label, firstBit: firstBit, lastBit: end))
    }

    /// A whole number: `0`, or digits that do not start with 0, not followed by a `.`; a number past 2⁵³ is read as 2⁵³.
    private mutating func readNumber() throws(MermaidDiagramReadError) -> Int {
        guard let first = cursor.peek(), MermaidByte.isDigit(first) else { throw .invalidSyntax(line: cursor.line, problem: .packet(.expectedBitNumber)) }
        var value = 0
        while let byte = cursor.peek(), MermaidByte.isDigit(byte) {
            value = min(value * 10 + Int(byte - UInt8(ascii: "0")), Self.largestBit)
            cursor.advance()
            if first == UInt8(ascii: "0") { break }
        }
        if cursor.peek() == MermaidByte.period { throw .invalidSyntax(line: cursor.line, problem: .unexpectedText(cursor.excerpt())) }
        return value
    }
}
