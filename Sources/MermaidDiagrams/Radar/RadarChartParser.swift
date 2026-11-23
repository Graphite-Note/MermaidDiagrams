/**
 * File: RadarChartParser.swift
 * ----------------------------
 * Layer: Core
 * Description: Reads a radar chart's statements after its `radar-beta` keyword: axes, curves, options and titles.
 *
 * Authors: Bahey Shalash
 * Version: 0.5
 * Date: 23/11/2026
 */

/// Reads the statements after the `radar-beta` keyword (and an optional `:`) as Mermaid's grammar does: `axis id["Label"],
/// …`, `curve id["Label"]{1, 2, 3}` or `{axis: 1, other: 2}`, the options `showLegend true`, `ticks 5`, `max 10`, `min 0`
/// and `graticule polygon`, several of one kind joined by commas, and `title …`, `accTitle: …`, `accDescr: …` or
/// `accDescr { … }`. Axes, curves and options follow one another on a line or on lines of their own; only a title
/// statement ends its line. A curve's named entries are matched with the axes once the whole text is read, so a curve may
/// come before the axes it names.
struct RadarChartParser {
    private var cursor: MermaidTextCursor
    private var chart = RadarChart()
    private var statements = MermaidTitleStatements()
    private var writtenCurves: [WrittenCurve] = []
    private var entryCount = 0
    private let limits: MermaidDiagramLimits

    /// A curve as written: its values, or its values by axis name.
    struct WrittenCurve {
        let name: String
        let label: DiagramLabel
        let line: Int
        let entries: [(axisName: String?, value: Double)]
    }

    private init(cursor: MermaidTextCursor, limits: MermaidDiagramLimits) {
        self.cursor = cursor
        self.limits = limits
    }

    static func parse(_ cursor: MermaidTextCursor, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> RadarChart {
        var parser = RadarChartParser(cursor: cursor, limits: limits)
        parser.chart.appearance = RadarAppearance(MermaidConfigurationOptions(section: "radar", in: cursor))
        parser.skipOptionalColon()
        try parser.readStatements()
        try parser.finish()
        parser.chart.seriesColors = MermaidThemeSeriesPalette.radar.seriesColors(in: cursor)
        return parser.chart
    }

    /// `radar-beta:` or `radar-beta :`.
    private mutating func skipOptionalColon() {
        var lookahead = cursor
        lookahead.skipSpaces()
        guard lookahead.peek() == MermaidByte.colon else { return }
        lookahead.advance()
        cursor = lookahead
    }

    private mutating func readStatements() throws(MermaidDiagramReadError) {
        while true {
            MermaidTitleStatements.skipBlank(&cursor)
            guard !cursor.isAtEnd else { return }
            if try statements.read(&cursor) {
                try MermaidTitleStatements.expectLineEnd(&cursor)
                continue
            }
            let line = cursor.line
            let word = RadarChartWords.name(in: cursor) ?? ""
            switch word {
            case "axis": try readAxes()
            case "curve": try readCurves()
            case _ where RadarChartWords.options.contains(word): try readOptions()
            default: throw .invalidSyntax(line: line, problem: .unexpectedText(cursor.excerpt()))
            }
        }
    }

    /// Axes and curves are named at most as many as the diagram's nodes.
    private func checkRoomForOneMore() throws(MermaidDiagramReadError) {
        guard chart.axes.count + writtenCurves.count < limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
    }

    // MARK: Axes and curves

    /// `axis` and one or more axes joined by commas.
    private mutating func readAxes() throws(MermaidDiagramReadError) {
        cursor.advance(by: RadarChartWords.axis.count)
        repeat {
            try checkRoomForOneMore()
            let name = try readName()
            let label = try readOptionalLabel()
            chart.axes.append(RadarAxis(name: name, label: label ?? DiagramLabelDecoder.label(from: name, form: .plain)))
        } while acceptComma()
    }

    /// `curve` and one or more curves joined by commas.
    private mutating func readCurves() throws(MermaidDiagramReadError) {
        cursor.advance(by: RadarChartWords.curve.count)
        repeat {
            try checkRoomForOneMore()
            let line = cursor.line
            let name = try readName()
            let label = try readOptionalLabel()
            guard cursor.peek() == MermaidByte.openingBrace else { throw problem(.expectedOpeningBrace) }
            cursor.advance()
            let entries = try readEntries()
            writtenCurves.append(WrittenCurve(name: name, label: label ?? DiagramLabelDecoder.label(from: name, form: .plain), line: line, entries: entries))
        } while acceptComma()
    }

    /// The entries of a curve after its `{` to its `}`: numbers, or axis names each with a number (and an optional colon);
    /// never both. Line breaks may come after the `{`, after a comma and before the `}`, not before a comma.
    private mutating func readEntries() throws(MermaidDiagramReadError) -> [(axisName: String?, value: Double)] {
        skipLineBreaks()
        let isNamed = RadarChartWords.isName(RadarChartWords.name(in: cursor))
        guard isNamed || cursor.peek().map(MermaidByte.isDigit) == true else { throw problem(.expectedName) }
        var entries: [(axisName: String?, value: Double)] = []
        while true {
            guard entryCount < limits.maximumEdgeCount else { throw .tooManyChartValues(limit: limits.maximumEdgeCount) }
            entryCount += 1
            var axisName: String?
            if isNamed {
                axisName = try readName()
                cursor.skipSpaces()
                if cursor.peek() == MermaidByte.colon {
                    cursor.advance()
                    cursor.skipSpaces()
                }
            }
            entries.append((axisName, try readNumber()))
            // The comma follows the entry on its line; line breaks may come after it, or before the `}`.
            guard acceptComma() else {
                skipLineBreaks()
                break
            }
            skipLineBreaks()
        }
        guard cursor.peek() == MermaidByte.closingBrace else { throw problem(.expectedClosingBrace) }
        cursor.advance()
        return entries
    }

    // MARK: Options

    /// One option, and more joined by commas.
    private mutating func readOptions() throws(MermaidDiagramReadError) {
        try readOption()
        while acceptComma() {
            cursor.skipSpaces()
            guard let word = RadarChartWords.name(in: cursor), RadarChartWords.options.contains(word) else { throw problem(.expectedOption) }
            try readOption()
        }
    }

    private mutating func readOption() throws(MermaidDiagramReadError) {
        let word = RadarChartWords.name(in: cursor) ?? ""
        cursor.advance(by: word.utf8.count)
        cursor.skipSpaces()
        switch word {
        case "showLegend":
            chart.options.showsLegend = try readWord(from: ["true", "false"], problem: .expectedBoolean) == "true"
        case "graticule":
            chart.options.graticule = RadarGraticule(rawValue: try readWord(from: ["circle", "polygon"], problem: .expectedGraticule)) ?? .circle
        case "ticks": chart.options.tickCount = min(try readNumber(), RadarChartOptions.largestTickCount)
        case "max": chart.options.maximum = try readNumber()
        default: chart.options.minimum = try readNumber()
        }
    }

    /// One of `words` at the cursor, taken whatever follows it (`falsecurve` is `false` and a `curve`), as Mermaid's lexer
    /// takes the value of an option.
    private mutating func readWord(from words: [String], problem expected: RadarSyntaxProblem) throws(MermaidDiagramReadError) -> String {
        for word in words where cursor.hasPrefix(Array(word.utf8)) {
            cursor.advance(by: word.utf8.count)
            return word
        }
        throw problem(expected)
    }

    // MARK: Pieces

    private func problem(_ problem: RadarSyntaxProblem) -> MermaidDiagramReadError {
        .invalidSyntax(line: cursor.line, problem: .radar(problem))
    }

    private mutating func skipLineBreaks() {
        MermaidTitleStatements.skipBlank(&cursor)
    }

    /// A comma after spaces; moves past it.
    private mutating func acceptComma() -> Bool {
        var lookahead = cursor
        lookahead.skipSpaces()
        guard lookahead.peek() == MermaidByte.comma else { return false }
        lookahead.advance()
        cursor = lookahead
        return true
    }

    /// A name after spaces: letters, digits, underscores and hyphens, starting with a letter or an underscore, not a word
    /// the grammar keeps.
    private mutating func readName() throws(MermaidDiagramReadError) -> String {
        cursor.skipSpaces()
        guard let name = RadarChartWords.name(in: cursor), RadarChartWords.isName(name) else { throw problem(.expectedName) }
        cursor.advance(by: name.utf8.count)
        return name
    }

    /// `["Label"]` after spaces, or nil when no `[` follows.
    private mutating func readOptionalLabel() throws(MermaidDiagramReadError) -> DiagramLabel? {
        cursor.skipSpaces()
        guard cursor.peek() == MermaidByte.openingBracket else { return nil }
        cursor.advance()
        cursor.skipSpaces()
        guard let quotation = cursor.peek(), quotation == MermaidByte.quotationMark || quotation == PieChartStatementText.apostrophe else {
            throw problem(.expectedLabel)
        }
        let text = try PieChartStatementText.readString(&cursor)
        cursor.skipSpaces()
        guard cursor.peek() == MermaidByte.closingBracket else { throw problem(.expectedLabel) }
        cursor.advance()
        return DiagramLabelDecoder.label(from: text, form: .plain)
    }

    /// A number after spaces: digits with an optional fraction, no sign, no leading zero before more digits.
    private mutating func readNumber() throws(MermaidDiagramReadError) -> Double {
        cursor.skipSpaces()
        guard let number = RadarChartWords.number(at: &cursor) else { throw problem(.expectedNumber) }
        return number
    }

    // MARK: End

    /// Gives each curve its values by the axes' order, now that every axis is known, and the titles.
    private mutating func finish() throws(MermaidDiagramReadError) {
        for written in writtenCurves {
            chart.curves.append(RadarCurve(name: written.name, label: written.label, values: try values(of: written)))
        }
        chart.title = statements.title
        chart.accessibilityTitle = statements.accessibilityTitle
        chart.accessibilityDescription = statements.accessibilityDescription
    }

    /// The values of a curve of numbers as written; of a curve of named entries, one per axis, the first entry of an axis
    /// winning.
    private func values(of written: WrittenCurve) throws(MermaidDiagramReadError) -> [Double] {
        guard written.entries.first?.axisName != nil else { return written.entries.map(\.value) }
        guard !chart.axes.isEmpty else { throw .invalidSyntax(line: written.line, problem: .radar(.entriesNamedBeforeAxes(curve: written.name))) }
        var byAxis: [String: Double] = [:]
        for entry in written.entries {
            if let name = entry.axisName, byAxis[name] == nil { byAxis[name] = entry.value }
        }
        return try chart.axes.map { axis throws(MermaidDiagramReadError) in
            guard let value = byAxis[axis.name] else {
                throw .invalidSyntax(line: written.line, problem: .radar(.missingEntry(curve: written.name, axis: axis.label.spokenText)))
            }
            return value
        }
    }
}
