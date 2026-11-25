/**
 * File: ReferencePieChartParser.swift
 * -----------------------------------
 * Layer: Tests
 * Description: 0.7.0's PieChartParser, frozen as main de81532 had it, which the pie chart reader is compared with.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

@testable import MermaidDiagrams

/// Reads a pie chart's statements after its `pie` keyword, as Mermaid's grammar does: `showData` on the keyword's
/// line, then, each ending its line, `title …`, `accTitle: …`, `accDescr: …` or `accDescr { … }`, and slices
/// (`"label" : value`). `%%` starts a comment, and `%%{ … }%%` is a directive, which is left.
struct ReferencePieChartParser {
    private var cursor: MermaidTextCursor
    private var chart = PieChart()
    /// The labels of the slices kept, as written: a later slice with one of them is left out.
    private var keptLabels: Set<String> = []
    private let limits: MermaidDiagramLimits

    private init(cursor: MermaidTextCursor, limits: MermaidDiagramLimits) {
        self.cursor = cursor
        self.limits = limits
    }

    /// Reads the pie chart whose `pie` keyword ends at the cursor.
    static func parse(_ cursor: MermaidTextCursor, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> PieChart {
        var parser = ReferencePieChartParser(cursor: cursor, limits: limits)
        parser.chart.options = PieChartOptions(MermaidConfigurationOptions(section: "pie", in: cursor))
        parser.readShowData()
        try parser.readStatements()
        parser.chart.seriesColors = MermaidThemeSeriesPalette.pieChart.seriesColors(in: cursor)
        return parser.chart
    }

    private mutating func readShowData() {
        cursor.skipSpaces()
        guard ReferencePieChartStatementText.isAtKeyword(Self.showData, cursor) else { return }
        cursor.advance(by: Self.showData.count)
        chart.showsValues = true
    }

    private mutating func readStatements() throws(MermaidDiagramReadError) {
        while true {
            ReferencePieChartStatementText.skipSpacesAndComments(&cursor)
            guard let byte = cursor.peek() else { return }
            if byte == MermaidByte.newline || byte == MermaidByte.carriageReturn {
                cursor.advance()
                continue
            }
            try readStatement(startingWith: byte)
            try expectLineEnd()
        }
    }

    private mutating func readStatement(startingWith byte: UInt8) throws(MermaidDiagramReadError) {
        if byte == MermaidByte.quotationMark || byte == ReferencePieChartStatementText.apostrophe { return try readSlice() }
        if ReferencePieChartStatementText.isAtKeyword(Self.title, cursor) {
            cursor.advance(by: Self.title.count)
            let title = ReferencePieChartStatementText.readLineValue(&cursor)
            if !title.isEmpty { chart.title = title }
            return
        }
        var lookahead = cursor
        if lookahead.hasPrefix(Self.accessibilityTitle) {
            lookahead.advance(by: Self.accessibilityTitle.count)
            lookahead.skipSpaces()
            if lookahead.peek() == MermaidByte.colon {
                lookahead.advance()
                cursor = lookahead
                chart.accessibilityTitle = ReferencePieChartStatementText.readLineValue(&cursor)
                return
            }
        } else if cursor.hasPrefix(Self.accessibilityDescription) {
            lookahead.advance(by: Self.accessibilityDescription.count)
            if let description = try ReferencePieChartStatementText.readAccessibilityDescription(&lookahead) {
                cursor = lookahead
                chart.accessibilityDescription = description
                return
            }
        }
        throw .invalidSyntax(line: cursor.line, problem: .unexpectedText(cursor.excerpt()))
    }

    /// `"label" : value`, where the value is `0`, a whole number that does not start with 0, or a decimal number.
    private mutating func readSlice() throws(MermaidDiagramReadError) {
        let line = cursor.line
        let label = try ReferencePieChartStatementText.readString(&cursor)
        cursor.skipSpaces()
        guard cursor.peek() == MermaidByte.colon else { throw .invalidSyntax(line: cursor.line, problem: .expectedSliceValue) }
        cursor.advance()
        cursor.skipSpaces()
        guard let value = ReferencePieChartStatementText.readNumber(&cursor) else { throw .invalidSyntax(line: cursor.line, problem: .expectedSliceValue) }
        guard value >= 0 else { throw .invalidSyntax(line: line, problem: .negativeSliceValue(label: label)) }
        guard !keptLabels.contains(label) else { return }
        guard chart.slices.count < limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
        keptLabels.insert(label)
        chart.slices.append(PieChartSlice(label: DiagramLabelDecoder.label(from: label, form: .plain), value: value))
    }

    /// A statement ends its line: spaces and a comment may follow it, then a line break or the end of the text.
    private mutating func expectLineEnd() throws(MermaidDiagramReadError) {
        ReferencePieChartStatementText.skipSpacesAndComments(&cursor)
        guard let byte = cursor.peek(), byte != MermaidByte.newline, byte != MermaidByte.carriageReturn else { return }
        throw .invalidSyntax(line: cursor.line, problem: .unexpectedText(cursor.excerpt()))
    }

    private static let showData = Array("showData".utf8)
    private static let title = Array("title".utf8)
    private static let accessibilityTitle = Array("accTitle".utf8)
    private static let accessibilityDescription = Array("accDescr".utf8)
}
